package com.example.radius

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service to keep BLE advertising reliable on Android.
 *
 * Many Android devices throttle/stop BLE advertising when the app is backgrounded
 * unless a foreground service (with a persistent notification) is running.
 */
class BleForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                @Suppress("DEPRECATION")
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                ensureNotificationChannel()
                startForeground(NOTIFICATION_ID, buildNotification())
                return START_STICKY
            }
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Radius is active")
            .setContentText("Bluetooth discovery is running")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            // Use a system icon to avoid resource coupling.
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Radius Bluetooth",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Keeps Radius BLE discovery active"
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "radius_ble"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.example.radius.action.START_BLE"
        const val ACTION_STOP = "com.example.radius.action.STOP_BLE"
    }
}
