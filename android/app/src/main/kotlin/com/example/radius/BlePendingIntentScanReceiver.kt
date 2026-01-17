package com.example.radius

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.ParcelUuid
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Receives background BLE scan results delivered via PendingIntent.
 */
class BlePendingIntentScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action != ACTION_PENDING_INTENT_SCAN) return

            val results: List<ScanResult>? = intent.getParcelableArrayListExtra(
                BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT
            )

            if (results.isNullOrEmpty()) return

            val arr = JSONArray()
            for (r in results) {
                arr.put(scanResultToJson(r))
            }

            val wrapper = JSONObject()
            wrapper.put("type", "batch")
            wrapper.put("tsMs", System.currentTimeMillis())
            wrapper.put("results", arr)

            BleScanResultStore.add(context, wrapper)
        } catch (e: Exception) {
            Log.w("BlePendingReceiver", "Failed to handle scan intent", e)
        }
    }

    private fun scanResultToJson(result: ScanResult): JSONObject {
        val obj = JSONObject()
        obj.put("address", result.device?.address ?: "")
        obj.put("rssi", result.rssi)
        obj.put("timestampNanos", result.timestampNanos)

        val record = result.scanRecord
        obj.put("deviceName", record?.deviceName ?: "")

        val uuids = JSONArray()
        val serviceUuids: List<ParcelUuid>? = record?.serviceUuids
        if (serviceUuids != null) {
            for (u in serviceUuids) {
                uuids.put(u.uuid.toString())
            }
        }
        obj.put("serviceUuids", uuids)

        // Manufacturer data (SparseArray<Int, ByteArray>) => JSON object of base64 values.
        val mfg = JSONObject()
        val msd = record?.manufacturerSpecificData
        if (msd != null) {
            for (i in 0 until msd.size()) {
                val key = msd.keyAt(i)
                val value = msd.get(key)
                if (value != null) {
                    mfg.put(key.toString(), BleScanResultStore.encodeBytes(value))
                }
            }
        }
        obj.put("manufacturerData", mfg)

        return obj
    }

    companion object {
        const val ACTION_PENDING_INTENT_SCAN = "com.example.radius.action.PENDING_INTENT_SCAN"
    }
}
