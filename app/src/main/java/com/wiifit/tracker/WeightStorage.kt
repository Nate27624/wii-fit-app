package com.wiifit.tracker

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class WeightRecord(
    val id: Long = System.currentTimeMillis(),
    val timestamp: String = Instant.now().toString(),
    val weightLbs: Double,
    val weightKg: Double,
    val note: String = "",
) {
    fun formattedDate(): String {
        return try {
            val inst = Instant.parse(timestamp)
            DateTimeFormatter.ofPattern("MMM d, yyyy")
                .withZone(ZoneId.systemDefault())
                .format(inst)
        } catch (_: Exception) { timestamp }
    }

    fun formattedTime(): String {
        return try {
            val inst = Instant.parse(timestamp)
            DateTimeFormatter.ofPattern("h:mm a")
                .withZone(ZoneId.systemDefault())
                .format(inst)
        } catch (_: Exception) { "" }
    }
}

class WeightStorage(context: Context) {
    private val file = File(context.filesDir, "weights.json")
    private val gson = Gson()
    private val type = object : TypeToken<MutableList<WeightRecord>>() {}.type

    fun load(): List<WeightRecord> {
        if (!file.exists()) return emptyList()
        return try {
            gson.fromJson(file.readText(), type) ?: emptyList()
        } catch (_: Exception) { emptyList() }
    }

    fun save(record: WeightRecord) {
        val list = load().toMutableList()
        list.add(record)
        file.writeText(gson.toJson(list))
    }

    fun delete(id: Long) {
        val list = load().filter { it.id != id }.toMutableList()
        file.writeText(gson.toJson(list))
    }

    fun clear() {
        file.delete()
    }
}
