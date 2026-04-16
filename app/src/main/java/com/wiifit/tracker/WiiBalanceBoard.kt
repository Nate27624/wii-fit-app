package com.wiifit.tracker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import kotlin.math.abs

private const val TAG = "WiiBoard"

/** Wii HID output report IDs (sent from us → board) */
private const val OUT_LEDS       = 0x11
private const val OUT_MODE       = 0x12
private const val OUT_WRITE_MEM  = 0x16
private const val OUT_READ_MEM   = 0x17
private const val OUT_STATUS_REQ = 0x15

/** Wii HID input report IDs (received from board) */
private const val IN_STATUS      = 0x20
private const val IN_READ_RESULT = 0x21
private const val IN_ACK         = 0x22
private const val IN_EXT8        = 0x32  // Core Buttons + 8 Extension bytes
private const val IN_EXT19       = 0x34  // Core Buttons + 19 Extension bytes

/** L2CAP PSM channels for Wii HID */
private const val PSM_CONTROL    = 0x11
private const val PSM_INTERRUPT  = 0x13

/** Reporting mode: continuous, 8 extension bytes (balance board data) */
private const val CONTINUOUS     = 0x04.toByte()

data class WiiBoardState(
    val status: ConnectionStatus = ConnectionStatus.IDLE,
    val weightLbs: Double = 0.0,
    val weightKg: Double = 0.0,
    val batteryPct: Int = 0,
    val error: String? = null,
    val scanning: Boolean = false,
)

enum class ConnectionStatus {
    IDLE, SCANNING, FOUND, CONNECTING, CONNECTED, STREAMING, DISCONNECTED, ERROR
}

/**
 * Calibration from EEPROM (3 points × 4 sensors).
 * Sensor order: [0]=TopRight, [1]=BottomRight, [2]=TopLeft, [3]=BottomLeft
 */
data class WBC_Calibration(
    val kg0:  IntArray = IntArray(4) { 430  },  // typical factory values
    val kg17: IntArray = IntArray(4) { 2100 },
    val kg34: IntArray = IntArray(4) { 3800 },
)

private fun calcSensorKg(raw: Int, k0: Int, k17: Int, k34: Int): Double {
    if (k17 <= k0) return 0.0
    val w = if (raw < k17)
        17.0 * (raw - k0).toDouble() / (k17 - k0).toDouble()
    else
        17.0 + 17.0 * (raw - k17).toDouble() / (k34 - k17).toDouble()
    return w.coerceAtLeast(0.0)
}

/**
 * Manages the Bluetooth connection to the Wii Balance Board.
 *
 * Connection flow:
 *  1. startScan() → discovers the board
 *  2. connectToDevice() → pairs + opens L2CAP PSM 0x13 (HID interrupt)
 *  3. Sends init HID commands → receives weight data
 */
@SuppressLint("MissingPermission")
class WiiBalanceBoard(private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(WiiBoardState())
    val state: StateFlow<WiiBoardState> = _state.asStateFlow()

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter

    private var socket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null

    private var calibration = WBC_Calibration()
    private var initialized = false
    private var calBytesExpected = 24
    private var calBytesReceived = 0
    private val calBuffer = mutableListOf<Byte>()

    // ─── BroadcastReceiver for discovery ─────────────────────────────────────

    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val dev = if (android.os.Build.VERSION.SDK_INT >= 33)
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    else
                        @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

                    val name = dev?.name ?: return
                    Log.d(TAG, "Found: $name  ${dev.address}")

                    if (name.contains("Nintendo RVL")) {
                        Log.d(TAG, "→ Balance Board found!")
                        adapter?.cancelDiscovery()
                        setState { copy(status = ConnectionStatus.FOUND, scanning = false) }
                        scope.launch { connectToDevice(dev) }
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    if (state.value.status == ConnectionStatus.SCANNING) {
                        // Restart if still scanning (board wasn't found yet)
                        Log.d(TAG, "Scan finished without finding board — restarting")
                        adapter?.startDiscovery()
                    }
                }
                BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                    // Intercept pairing to inject the correct PIN
                    val dev = if (android.os.Build.VERSION.SDK_INT >= 33)
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    else
                        @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

                    val variant = intent.getIntExtra(BluetoothDevice.EXTRA_PAIRING_VARIANT, -1)
                    Log.d(TAG, "Pairing request: variant=$variant  dev=${dev?.address}")

                    if (variant == BluetoothDevice.PAIRING_VARIANT_PIN) {
                        // Compute PIN = our BT MAC address reversed
                        val pin = buildPin()
                        Log.d(TAG, "Setting PIN: ${pin.joinToString(" ") { "0x%02X".format(it) }}")
                        dev?.setPin(pin)
                        abortBroadcast()
                    } else if (variant == BluetoothDevice.PAIRING_VARIANT_PASSKEY_CONFIRMATION) {
                        dev?.setPairingConfirmation(true)
                        abortBroadcast()
                    }
                }
            }
        }
    }

    /** Compute PIN = host BT MAC address bytes in reverse order */
    private fun buildPin(): ByteArray {
        val macStr = adapter?.address ?: return ByteArray(6)
        val bytes = macStr.split(":").map { it.toInt(16).toByte() }.toByteArray()
        return bytes.reversedArray()
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    fun startScan() {
        if (adapter == null) {
            setState { copy(status = ConnectionStatus.ERROR, error = "Bluetooth not available") }
            return
        }
        if (!adapter.isEnabled) {
            setState { copy(status = ConnectionStatus.ERROR, error = "Bluetooth is off") }
            return
        }

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
            priority = IntentFilter.SYSTEM_HIGH_PRIORITY
        }
        context.registerReceiver(discoveryReceiver, filter)

        setState { copy(status = ConnectionStatus.SCANNING, scanning = true, error = null) }
        adapter.startDiscovery()
        Log.d(TAG, "Discovery started")
    }

    fun stopScan() {
        adapter?.cancelDiscovery()
        try { context.unregisterReceiver(discoveryReceiver) } catch (_: Exception) {}
        setState { copy(scanning = false) }
    }

    fun disconnect() {
        scope.launch {
            try {
                socket?.close()
            } catch (_: Exception) {}
            socket = null
            initialized = false
            setState { copy(status = ConnectionStatus.DISCONNECTED, weightLbs = 0.0, weightKg = 0.0) }
        }
    }

    fun cleanup() {
        scope.cancel()
        stopScan()
        disconnect()
    }

    // ─── Connection ───────────────────────────────────────────────────────────

    private suspend fun connectToDevice(device: BluetoothDevice) {
        setState { copy(status = ConnectionStatus.CONNECTING) }
        adapter?.cancelDiscovery()

        // Pair if needed
        if (device.bondState == BluetoothDevice.BOND_NONE) {
            Log.d(TAG, "Initiating pairing...")
            device.createBond()
            // Give Android up to 15 seconds to complete pairing
            var waited = 0
            while (device.bondState != BluetoothDevice.BOND_BONDED && waited < 15000) {
                delay(500)
                waited += 500
            }
            if (device.bondState != BluetoothDevice.BOND_BONDED) {
                Log.w(TAG, "Pairing didn't complete — trying anyway")
            } else {
                Log.d(TAG, "Paired successfully!")
            }
        }

        // Open L2CAP interrupt channel (PSM 0x13) via reflection
        try {
            Log.d(TAG, "Opening L2CAP PSM 0x13 (HID interrupt)...")

            // Use reflection to access the Classic Bluetooth L2CAP socket
            val m = device.javaClass.getDeclaredMethod("createL2capSocket", Int::class.javaPrimitiveType)
            val sock = m.invoke(device, PSM_INTERRUPT) as BluetoothSocket
            socket = sock

            withContext(Dispatchers.IO) { sock.connect() }

            inputStream  = sock.inputStream
            outputStream = sock.outputStream

            Log.d(TAG, "L2CAP connected!")
            setState { copy(status = ConnectionStatus.CONNECTED) }

            initBoard()
            readLoop()

        } catch (e: Exception) {
            Log.e(TAG, "Connection failed: ${e.message}")
            setState { copy(status = ConnectionStatus.ERROR, error = "Connection failed: ${e.message}") }
        }
    }

    // ─── Board Init ───────────────────────────────────────────────────────────

    private suspend fun initBoard() {
        Log.d(TAG, "Initialising board...")

        // 1. Turn on LED 1
        sendReport(OUT_LEDS, byteArrayOf(0x10))
        delay(50)

        // 2. Disable extension encryption
        writeReg(0xA400F0, byteArrayOf(0x55))
        delay(50)
        writeReg(0xA400FB, byteArrayOf(0x00))
        delay(50)

        // 3. Read calibration from EEPROM (24 bytes at 0x0024)
        calBuffer.clear()
        calBytesExpected = 24
        calBytesReceived = 0
        readEEPROM(0x0024u, 24)

        // 4. If calibration not received in 4 s, start anyway
        scope.launch {
            delay(4000)
            if (!initialized) {
                Log.w(TAG, "Calibration timeout — starting with defaults")
                startStreaming()
            }
        }
    }

    private fun sendReport(id: Int, payload: ByteArray) {
        try {
            val buf = ByteArray(2 + payload.size)
            buf[0] = 0xa2.toByte()
            buf[1] = id.toByte()
            payload.copyInto(buf, 2)
            outputStream?.write(buf)
            outputStream?.flush()
        } catch (e: IOException) {
            Log.e(TAG, "sendReport failed: ${e.message}")
        }
    }

    private fun writeReg(address: Long, data: ByteArray) {
        val p = ByteArray(20)
        p[0] = 0x04  // register space
        p[1] = ((address shr 16) and 0xFF).toByte()
        p[2] = ((address shr 8)  and 0xFF).toByte()
        p[3] = ( address         and 0xFF).toByte()
        p[4] = data.size.toByte()
        data.copyInto(p, 5)
        sendReport(OUT_WRITE_MEM, p)
    }

    private fun readEEPROM(address: UInt, len: Int) {
        val p = ByteArray(6)
        p[0] = 0x00  // EEPROM space
        p[1] = ((address shr 16) and 0xFFu).toByte()
        p[2] = ((address shr 8)  and 0xFFu).toByte()
        p[3] = ( address         and 0xFFu).toByte()
        p[4] = ((len shr 8) and 0xFF).toByte()
        p[5] = (len and 0xFF).toByte()
        sendReport(OUT_READ_MEM, p)
    }

    private suspend fun startStreaming() {
        if (initialized) return
        initialized = true
        Log.d(TAG, "Starting data stream (mode 0x32)...")
        sendReport(OUT_MODE, byteArrayOf(CONTINUOUS, IN_EXT8.toByte()))
        setState { copy(status = ConnectionStatus.STREAMING) }
    }

    // ─── Read Loop ────────────────────────────────────────────────────────────

    private suspend fun readLoop() {
        val buf = ByteArray(128)
        while (socket?.isConnected == true) {
            try {
                val n = withContext(Dispatchers.IO) { inputStream!!.read(buf) }
                if (n < 2) continue
                processReport(buf, n)
            } catch (e: IOException) {
                Log.w(TAG, "Read error: ${e.message}")
                setState { copy(status = ConnectionStatus.DISCONNECTED) }
                break
            }
        }
    }

    private suspend fun processReport(buf: ByteArray, n: Int) {
        if (buf[0] != 0xa1.toByte()) return
        when (buf[1].toInt() and 0xFF) {
            IN_STATUS -> {
                val bat = ((buf[7].toInt() and 0xFF) / 192.0 * 100).toInt()
                Log.d(TAG, "Status: battery=$bat%")
                setState { copy(batteryPct = bat) }
                if (!initialized) startStreaming()
            }
            IN_READ_RESULT -> {
                if (n < 7) return
                val se  = buf[4].toInt() and 0xFF
                val err = se and 0x0F
                if (err != 0) {
                    Log.w(TAG, "EEPROM read error: $err")
                    startStreaming()
                    return
                }
                val size = (se shr 4) + 1
                for (i in 0 until minOf(size, n - 7)) calBuffer.add(buf[7 + i])
                calBytesReceived += size
                if (calBytesReceived >= calBytesExpected) {
                    parseCalibration(calBuffer.toByteArray())
                    startStreaming()
                }
            }
            IN_EXT8, IN_EXT19 -> {
                if (n < 12) return
                processWeight(buf, offset = 4)
            }
        }
    }

    private fun parseCalibration(data: ByteArray) {
        if (data.size < 24) return
        val kg0  = IntArray(4) { i -> ((data[i * 2].toInt() and 0xFF) shl 8) or (data[i * 2 + 1].toInt() and 0xFF) }
        val kg17 = IntArray(4) { i -> ((data[8 + i * 2].toInt() and 0xFF) shl 8) or (data[9 + i * 2].toInt() and 0xFF) }
        val kg34 = IntArray(4) { i -> ((data[16 + i * 2].toInt() and 0xFF) shl 8) or (data[17 + i * 2].toInt() and 0xFF) }
        calibration = WBC_Calibration(kg0, kg17, kg34)
        Log.d(TAG, "Calibration:  0kg=${kg0.toList()}  17kg=${kg17.toList()}  34kg=${kg34.toList()}")
    }

    private var lastLoggedLbs = -999.0

    private fun processWeight(buf: ByteArray, offset: Int) {
        val raw  = IntArray(4) { i ->
            ((buf[offset + i * 2].toInt() and 0xFF) shl 8) or (buf[offset + i * 2 + 1].toInt() and 0xFF)
        }
        val kg   = DoubleArray(4) { i -> calcSensorKg(raw[i], calibration.kg0[i], calibration.kg17[i], calibration.kg34[i]) }
        val totalKg  = kg.sum()
        val totalLbs = totalKg * 2.20462

        if (abs(totalLbs - lastLoggedLbs) >= 0.3) {
            Log.d(TAG, "⚖️ %.1f lbs  (%.2f kg)".format(totalLbs, totalKg))
            lastLoggedLbs = totalLbs
        }

        setState { copy(weightLbs = totalLbs, weightKg = totalKg) }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private fun setState(block: WiiBoardState.() -> WiiBoardState) {
        _state.value = _state.value.block()
    }
}
