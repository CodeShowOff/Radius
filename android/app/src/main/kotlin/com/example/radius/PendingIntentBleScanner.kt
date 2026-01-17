package com.example.radius

import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID

object PendingIntentBleScanner {
    private const val TAG = "PendingIntentBleScanner"

    private fun scanner(context: Context): BluetoothLeScanner? {
        val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bm.adapter ?: return null
        return adapter.bluetoothLeScanner
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, BlePendingIntentScanReceiver::class.java).apply {
            action = BlePendingIntentScanReceiver.ACTION_PENDING_INTENT_SCAN
        }
        return PendingIntent.getBroadcast(
            context,
            2001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun start(
        context: Context,
        serviceUuids: List<String>,
        manufacturerId: Int?,
        manufacturerData: ByteArray?,
        manufacturerMask: ByteArray?,
        scanMode: Int,
        reportDelayMs: Long
    ) {
        val s = scanner(context) ?: throw IllegalStateException("BluetoothLeScanner unavailable")

        val settings = ScanSettings.Builder()
            .setScanMode(scanMode)
            .setReportDelay(reportDelayMs)
            .build()

        val filters = mutableListOf<ScanFilter>()

        // OR semantics across filter list: add separate filters when possible.
        for (uuidStr in serviceUuids) {
            try {
                val uuid = UUID.fromString(uuidStr)
                filters.add(
                    ScanFilter.Builder()
                        .setServiceUuid(ParcelUuid(uuid))
                        .build()
                )
            } catch (_: Exception) {
                // Ignore invalid UUID.
            }
        }

        if (manufacturerId != null && manufacturerData != null) {
            val b = ScanFilter.Builder()
            if (manufacturerMask != null) {
                b.setManufacturerData(manufacturerId, manufacturerData, manufacturerMask)
            } else {
                b.setManufacturerData(manufacturerId, manufacturerData)
            }
            filters.add(b.build())
        }

        val pi = pendingIntent(context)

        Log.i(TAG, "start pending-intent scan: filters=${filters.size} scanMode=$scanMode")
        s.startScan(filters, settings, pi)
    }

    fun stop(context: Context) {
        val s = scanner(context) ?: return
        val pi = pendingIntent(context)
        try {
            Log.i(TAG, "stop pending-intent scan")
            s.stopScan(pi)
        } catch (e: Exception) {
            Log.w(TAG, "stopScan failed", e)
        }
    }
}
