package com.example.radius

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists BLE scan results delivered via PendingIntent/FGS so Flutter can
 * consume them when the engine is running.
 */
object BleScanResultStore {
    private const val PREFS = "radius_ble_scan"
    private const val KEY_BUFFER = "pending_intent_scan_buffer"
    private const val MAX_ITEMS = 100

    fun add(context: Context, event: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_BUFFER, null)
        val arr = if (existing.isNullOrBlank()) JSONArray() else JSONArray(existing)

        arr.put(event)

        // Trim oldest.
        while (arr.length() > MAX_ITEMS) {
            // JSONArray has no remove until API 19; we are 31+, so it's fine.
            arr.remove(0)
        }

        prefs.edit().putString(KEY_BUFFER, arr.toString()).apply()
    }

    fun consume(context: Context): JSONArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_BUFFER, null)
        prefs.edit().remove(KEY_BUFFER).apply()
        return if (existing.isNullOrBlank()) JSONArray() else JSONArray(existing)
    }

    fun encodeBytes(bytes: ByteArray): String {
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    fun decodeBytes(b64: String): ByteArray {
        return Base64.decode(b64, Base64.NO_WRAP)
    }
}
