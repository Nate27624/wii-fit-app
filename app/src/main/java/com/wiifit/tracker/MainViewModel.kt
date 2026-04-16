package com.wiifit.tracker

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MainViewModel(app: Application) : AndroidViewModel(app) {

    val board = WiiBalanceBoard(app)
    val boardState: StateFlow<WiiBoardState> = board.state

    private val storage = WeightStorage(app)
    private val _records = MutableStateFlow<List<WeightRecord>>(emptyList())
    val records: StateFlow<List<WeightRecord>> = _records.asStateFlow()

    private val _permissionsGranted = MutableStateFlow(false)
    val permissionsGranted: StateFlow<Boolean> = _permissionsGranted.asStateFlow()

    init {
        loadRecords()
    }

    fun setPermissionsGranted(granted: Boolean) {
        _permissionsGranted.value = granted
        if (granted) board.startScan()
    }

    fun startScan() = board.startScan()
    fun disconnect() = board.disconnect()

    fun logWeight() {
        val s = boardState.value
        if (s.weightLbs < 5.0) return
        val rec = WeightRecord(
            weightLbs = String.format("%.1f", s.weightLbs).toDouble(),
            weightKg  = String.format("%.2f", s.weightKg).toDouble(),
        )
        viewModelScope.launch {
            storage.save(rec)
            loadRecords()
        }
    }

    fun deleteRecord(id: Long) {
        viewModelScope.launch {
            storage.delete(id)
            loadRecords()
        }
    }

    private fun loadRecords() {
        viewModelScope.launch {
            _records.value = storage.load().sortedByDescending { it.id }
        }
    }

    override fun onCleared() {
        super.onCleared()
        board.cleanup()
    }
}
