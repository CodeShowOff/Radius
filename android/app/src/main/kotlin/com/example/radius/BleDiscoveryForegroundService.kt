package com.example.radius

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodCall
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Opt-in foreground service to keep continuous BLE discovery running reliably.
 *
 * Started only after user consent.
 */
class BleDiscoveryForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    private var scanning = false
    private var callback: ScanCallback? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopScanning()
                @Suppress("DEPRECATION")
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                ensureChannel()
                startForeground(NOTIFICATION_ID, buildNotification())
                startScanning(intent)
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Radius background discovery")
            .setContentText("Keeping Bluetooth discovery active in the background")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Radius Background Discovery",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Keeps Radius BLE discovery active"
        manager.createNotificationChannel(channel)
    }

    private fun startScanning(intent: Intent) {
        if (scanning) return

        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bm.adapter ?: return
        val scanner = adapter.bluetoothLeScanner ?: return

        val serviceUuids = intent.getStringArrayListExtra(EXTRA_SERVICE_UUIDS) ?: arrayListOf()
        val manufacturerId = intent.getIntExtra(EXTRA_MANUFACTURER_ID, -1)
        val manufacturerData = intent.getByteArrayExtra(EXTRA_MANUFACTURER_DATA)
        val manufacturerMask = intent.getByteArrayExtra(EXTRA_MANUFACTURER_MASK)
        val scanMode = intent.getIntExtra(EXTRA_SCAN_MODE, ScanSettings.SCAN_MODE_LOW_POWER)

        val settings = ScanSettings.Builder()
            .setScanMode(scanMode)
            .build()

        val filters = mutableListOf<ScanFilter>()
        for (uuidStr in serviceUuids) {
            try {
                filters.add(
                    ScanFilter.Builder()
                        .setServiceUuid(ParcelUuid(UUID.fromString(uuidStr)))
                        .build()
                )
            } catch (_: Exception) {
            }
        }
        if (manufacturerId >= 0 && manufacturerData != null) {
            val b = ScanFilter.Builder()
            if (manufacturerMask != null) {
                b.setManufacturerData(manufacturerId, manufacturerData, manufacturerMask)
            } else {
                b.setManufacturerData(manufacturerId, manufacturerData)
            }
            filters.add(b.build())
        }

        callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                storeResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                for (r in results) {
                    storeResult(r)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "Scan failed: $errorCode")
            }
        }

        Log.i(TAG, "FGS scan start: filters=${filters.size} scanMode=$scanMode")
        scanner.startScan(filters, settings, callback)
        scanning = true
    }

    private fun storeResult(result: ScanResult) {
        val record = result.scanRecord
        val obj = JSONObject()
        obj.put("address", result.device?.address ?: "")
        obj.put("rssi", result.rssi)
        obj.put("timestampNanos", result.timestampNanos)
        obj.put("deviceName", record?.deviceName ?: "")

        val uuids = JSONArray()
        val serviceUuids = record?.serviceUuids
        if (serviceUuids != null) {
            for (u in serviceUuids) {
                uuids.put(u.uuid.toString())
            }
        }
        obj.put("serviceUuids", uuids)

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

        val wrapper = JSONObject()
        wrapper.put("type", "single")
        wrapper.put("tsMs", System.currentTimeMillis())
        wrapper.put("results", JSONArray().put(obj))

        BleScanResultStore.add(this, wrapper)
    }

    private fun stopScanning() {
        if (!scanning) return
        try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bm.adapter ?: return
            val scanner = adapter.bluetoothLeScanner ?: return
            callback?.let { scanner.stopScan(it) }
        } catch (e: Exception) {
            Log.w(TAG, "stopScan failed", e)
        } finally {
            callback = null
            scanning = false
        }
    }

    companion object {
        private const val TAG = "BleDiscoveryFGS"

        private const val CHANNEL_ID = "radius_ble_discovery"
        private const val NOTIFICATION_ID = 1101

        private const val ACTION_START = "com.example.radius.action.START_BLE_DISCOVERY"
        private const val ACTION_STOP = "com.example.radius.action.STOP_BLE_DISCOVERY"

        private const val EXTRA_SERVICE_UUIDS = "serviceUuids"
        private const val EXTRA_MANUFACTURER_ID = "manufacturerId"
        private const val EXTRA_MANUFACTURER_DATA = "manufacturerData"
        private const val EXTRA_MANUFACTURER_MASK = "manufacturerMask"
        private const val EXTRA_SCAN_MODE = "scanMode"

        fun buildStartIntent(context: Context, call: MethodCall): Intent {
            val serviceUuids = call.argument<List<String>>("serviceUuids") ?: emptyList()
            val manufacturerId = call.argument<Number>("manufacturerId")?.toInt() ?: -1
            val manufacturerData = call.argument<ByteArray>("manufacturerData")
            val manufacturerMask = call.argument<ByteArray>("manufacturerMask")

            val scanModeStr = call.argument<String>("scanMode") ?: "low_power"
            val scanMode = when (scanModeStr) {
                "low_latency" -> ScanSettings.SCAN_MODE_LOW_LATENCY
                "balanced" -> ScanSettings.SCAN_MODE_BALANCED
                else -> ScanSettings.SCAN_MODE_LOW_POWER
            }

            return Intent(context, BleDiscoveryForegroundService::class.java).apply {
                action = ACTION_START
                putStringArrayListExtra(EXTRA_SERVICE_UUIDS, ArrayList(serviceUuids))
                putExtra(EXTRA_MANUFACTURER_ID, manufacturerId)
                if (manufacturerData != null) putExtra(EXTRA_MANUFACTURER_DATA, manufacturerData)
                if (manufacturerMask != null) putExtra(EXTRA_MANUFACTURER_MASK, manufacturerMask)
                putExtra(EXTRA_SCAN_MODE, scanMode)
            }
        }

        fun buildStopIntent(context: Context): Intent {
            return Intent(context, BleDiscoveryForegroundService::class.java).apply {
                action = ACTION_STOP
            }
        }
    }
}
