package com.codeshowoff.radius

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID

/**
 * Foreground service that keeps BLE advertising alive even when the app is
 * backgrounded or swiped away from recents.
 *
 * Lifecycle:
 *  1. Flutter calls startForegroundService via MethodChannel with the username.
 *  2. This service starts advertising and shows a persistent notification.
 *  3. When Bluetooth is toggled off → advertising stops automatically.
 *     When Bluetooth comes back on → advertising restarts automatically.
 *  4. Flutter calls stopForegroundService to tear everything down.
 */
class BleForegroundService : Service() {

    companion object {
        private const val TAG = "BleForegroundService"
        private const val CHANNEL_ID = "ble_advertising_channel"
        private const val NOTIFICATION_ID = 9274
        const val ACTION_START = "com.codeshowoff.radius.BLE_START"
        const val ACTION_STOP = "com.codeshowoff.radius.BLE_STOP"
        const val EXTRA_SERVICE_UUID16 = "serviceUuid16"
        const val EXTRA_SERVICE_DATA = "serviceData"
    }

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false

    // Advertising parameters saved so we can restart after BT toggle.
    private var savedServiceUuid16: String? = null
    private var savedServiceData: ByteArray? = null

    private var bluetoothStateReceiver: BroadcastReceiver? = null

    // ────────────────────────── Service lifecycle ──────────────────────────

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")

        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = btManager.adapter
        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser

        createNotificationChannel()
        registerBluetoothStateReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.d(TAG, "Received STOP action")
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val uuid16 = intent?.getStringExtra(EXTRA_SERVICE_UUID16) ?: savedServiceUuid16
                val data = intent?.getByteArrayExtra(EXTRA_SERVICE_DATA) ?: savedServiceData

                if (uuid16 != null && data != null) {
                    savedServiceUuid16 = uuid16
                    savedServiceData = data
                    startForeground(NOTIFICATION_ID, buildNotification())
                    startAdvertising()
                } else {
                    Log.w(TAG, "No advertising parameters – stopping")
                    stopSelf()
                }
            }
        }
        // If the system kills us, restart with the last intent so advertising resumes.
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        Log.d(TAG, "Service destroyed")
        stopAdvertising()
        unregisterBluetoothStateReceiver()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App swiped away from recents — keep service alive
        Log.d(TAG, "Task removed (app swiped away) — advertising continues")
        super.onTaskRemoved(rootIntent)
    }

    // ──────────────────────── Bluetooth state listener ────────────────────

    private fun registerBluetoothStateReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
                when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                    BluetoothAdapter.STATE_ON -> {
                        Log.d(TAG, "Bluetooth turned ON – restarting advertising")
                        // Re-acquire in case object changed
                        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
                        startAdvertising()
                    }
                    BluetoothAdapter.STATE_OFF,
                    BluetoothAdapter.STATE_TURNING_OFF -> {
                        Log.d(TAG, "Bluetooth turning OFF – stopping advertising")
                        stopAdvertising()
                    }
                }
            }
        }
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        registerReceiver(receiver, filter)
        bluetoothStateReceiver = receiver
    }

    private fun unregisterBluetoothStateReceiver() {
        bluetoothStateReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        bluetoothStateReceiver = null
    }

    // ────────────────────────── BLE advertising ──────────────────────────

    private fun startAdvertising() {
        if (isAdvertising) return

        val uuid16 = savedServiceUuid16 ?: return
        val data = savedServiceData ?: return

        // Re-acquire advertiser (can become null after BT toggle)
        if (advertiser == null) {
            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        }
        val adv = advertiser ?: run {
            Log.e(TAG, "BluetoothLeAdvertiser is null – cannot advertise")
            return
        }

        try {
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false)
                .setTimeout(0)
                .build()

            val baseUuidString = "0000${uuid16.lowercase()}-0000-1000-8000-00805f9b34fb"
            val parcelUuid = ParcelUuid(UUID.fromString(baseUuidString))

            val advData = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addServiceData(parcelUuid, data)
                .build()

            adv.startAdvertising(settings, advData, advertiseCallback)
            Log.d(TAG, "Advertising started (username=${String(data)})")
            isAdvertising = true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start advertising: ${e.message}")
        }
    }

    private fun stopAdvertising() {
        if (!isAdvertising) return
        try {
            isAdvertising = false
            advertiser?.stopAdvertising(advertiseCallback)
            Log.d(TAG, "Advertising stopped")
        } catch (_: Exception) {}
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.d(TAG, "✓ Advertising started successfully")
            isAdvertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            val msg = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                else -> "Unknown ($errorCode)"
            }
            Log.e(TAG, "✗ Advertising failed: $msg")
        }
    }

    // ──────────────────────── Notification helpers ────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "BLE Discovery",
            NotificationManager.IMPORTANCE_MIN      // hidden from status bar, only in drawer
        ).apply {
            description = "Keeps Bluetooth advertising active so nearby users can find you"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        // Tap opens bluetooth settings page
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            action = Intent.ACTION_VIEW
            data = android.net.Uri.parse("radius://settings/bluetooth")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Radius")
            .setContentText("Discoverable by nearby users")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }
}
