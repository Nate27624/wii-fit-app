package com.wiifit.tracker

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    private val bluetoothPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { perms ->
        val granted = perms.entries.all { it.value }
        viewModel.setPermissionsGranted(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        requestBluetoothPermissions()

        setContent {
            AppTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MainScreen(viewModel)
                }
            }
        }
    }

    private fun requestBluetoothPermissions() {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            permissions.add(Manifest.permission.BLUETOOTH)
            permissions.add(Manifest.permission.BLUETOOTH_ADMIN)
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        val needed = permissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (needed.isEmpty()) {
            viewModel.setPermissionsGranted(true)
        } else {
            bluetoothPermissionLauncher.launch(needed.toTypedArray())
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel) {
    val boardState by viewModel.boardState.collectAsState()
    val records by viewModel.records.collectAsState()
    val permissionsGranted by viewModel.permissionsGranted.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Wii Fit Tracker") },
                actions = {
                    if (permissionsGranted && boardState.status != ConnectionStatus.STREAMING) {
                        IconButton(onClick = { viewModel.startScan() }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Scan")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (!permissionsGranted) {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Text(
                        text = "Bluetooth permissions are required to connect to the Balance Board.",
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(16.dp)
                    )
                }
            }

            ScaleCard(boardState, viewModel)

            Text(
                text = "History",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 8.dp)
            )

            if (records.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxWidth().weight(1f),
                    contentAlignment = Alignment.Center
                ) {
                    Text("No records yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(records, key = { it.id }) { record ->
                        RecordItem(record) { viewModel.deleteRecord(it.id) }
                    }
                }
            }
        }
    }
}

@Composable
fun ScaleCard(state: WiiBoardState, viewModel: MainViewModel) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Status Badge
            val badgePair = when (state.status) {
                ConnectionStatus.IDLE -> Pair(MaterialTheme.colorScheme.surfaceVariant, "Ready")
                ConnectionStatus.SCANNING -> Pair(MaterialTheme.colorScheme.primaryContainer, "Scanning...")
                ConnectionStatus.FOUND -> Pair(MaterialTheme.colorScheme.secondaryContainer, "Board Found")
                ConnectionStatus.CONNECTING -> Pair(MaterialTheme.colorScheme.secondaryContainer, "Connecting...")
                ConnectionStatus.CONNECTED -> Pair(MaterialTheme.colorScheme.tertiaryContainer, "Initializing...")
                ConnectionStatus.STREAMING -> Pair(Color(0xFF4CAF50), "Connected")
                ConnectionStatus.DISCONNECTED -> Pair(MaterialTheme.colorScheme.errorContainer, "Disconnected")
                ConnectionStatus.ERROR -> Pair(MaterialTheme.colorScheme.errorContainer, "Error")
            }
            val badgeColor = badgePair.first
            val badgeText = badgePair.second

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(badgeColor)
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Text(
                    text = badgeText,
                    color = MaterialTheme.colorScheme.onSurface,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold
                )
            }

            if (state.status == ConnectionStatus.STREAMING) {
                Text(
                    text = "${String.format("%.1f", state.weightLbs)}",
                    fontSize = 64.sp,
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = "lbs",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                
                Text(
                    text = "Battery: ${state.batteryPct}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Button(
                    onClick = { viewModel.logWeight() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state.weightLbs >= 5.0
                ) {
                    Text("Log Weight")
                }
            } else {
                Text(
                    text = if (state.status == ConnectionStatus.SCANNING) 
                             "Press the RED SYNC button on your Balance Board"
                           else if (state.status == ConnectionStatus.ERROR)
                             state.error ?: "Unknown error"
                           else "Press scan to find your Balance Board",
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(vertical = 24.dp)
                )

                if (state.status == ConnectionStatus.IDLE || state.status == ConnectionStatus.DISCONNECTED || state.status == ConnectionStatus.ERROR) {
                    Button(onClick = { viewModel.startScan() }) {
                        Text("Scan for Board")
                    }
                } else if (state.status == ConnectionStatus.SCANNING) {
                    CircularProgressIndicator()
                }
            }
        }
    }
}

@Composable
fun RecordItem(record: WeightRecord, onDelete: (WeightRecord) -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "${record.weightLbs} lbs",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${record.formattedDate()} at ${record.formattedTime()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = { onDelete(record) }) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}
