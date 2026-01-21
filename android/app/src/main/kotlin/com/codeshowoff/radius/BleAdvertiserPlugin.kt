package com.codeshowoff.radius

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.app.Application
import android.os.Bundle
import android.content.Context
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Native Android BLE Advertiser Plugin
 * 
 * Simplified BLE advertising using Service Data.
 * Broadcasts Service UUID (0xBEEF) with username in Service Data.
 */
class BleAdvertiserPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false
    private var componentCallbacks: ComponentCallbacks2? = null
    private var activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null

    companion object {
        private const val CHANNEL_NAME = "com.codeshowoff.radius/ble_advertiser"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser

        // Keep advertising even when UI is hidden to allow discovery.
        // Only stop on low memory conditions.
        val callbacks = object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                // Only stop advertising if memory is critically low
                if (level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE) {
                    stopAdvertising()
                }
            }

            override fun onConfigurationChanged(newConfig: Configuration) {
                // No-op
            }

            override fun onLowMemory() {
                stopAdvertising()
            }
        }
        context.registerComponentCallbacks(callbacks)
        componentCallbacks = callbacks

        // Only stop advertising when app is DESTROYED, not when backgrounded.
        // This allows advertising to continue while app is in recents/background
        // so other devices can discover us.
        val app = context.applicationContext as? Application
        if (app != null) {
            val lifecycle = object : Application.ActivityLifecycleCallbacks {
                override fun onActivityCreated(activity: android.app.Activity, savedInstanceState: Bundle?) {}
                override fun onActivityStarted(activity: android.app.Activity) {}
                override fun onActivityResumed(activity: android.app.Activity) {}
                override fun onActivityPaused(activity: android.app.Activity) {}
                override fun onActivityStopped(activity: android.app.Activity) {}
                override fun onActivitySaveInstanceState(activity: android.app.Activity, outState: Bundle) {}
                
                override fun onActivityDestroyed(activity: android.app.Activity) {
                    // Only stop when activity is fully destroyed
                    if (activity.isFinishing) {
                        stopAdvertising()
                    }
                }
            }
            app.registerActivityLifecycleCallbacks(lifecycle)
            activityLifecycleCallbacks = lifecycle
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        componentCallbacks?.let {
            try {
                context.unregisterComponentCallbacks(it)
            } catch (_: Exception) {
                // Ignore unregister failures
            }
        }
        componentCallbacks = null

        val app = context.applicationContext as? Application
        activityLifecycleCallbacks?.let {
            try {
                app?.unregisterActivityLifecycleCallbacks(it)
            } catch (_: Exception) {
                // Ignore unregister failures
            }
        }
        activityLifecycleCallbacks = null

        stopAdvertising()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> {
                val serviceUuid16 = call.argument<String>("serviceUuid16")
                val serviceData = call.argument<ByteArray>("serviceData")

                if (serviceUuid16 == null) {
                    result.error("INVALID_ARGUMENT", "serviceUuid16 is required", null)
                    return
                }

                if (!Regex("^[0-9a-fA-F]{4}$").matches(serviceUuid16)) {
                    result.error("INVALID_ARGUMENT", "serviceUuid16 must be 4 hex chars (e.g., BEEF)", null)
                    return
                }

                if (serviceData == null || serviceData.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "serviceData (username bytes) is required", null)
                    return
                }

                if (serviceData.size != 7) {
                    result.error("INVALID_ARGUMENT", "serviceData must be exactly 7 bytes", null)
                    return
                }

                startAdvertising(serviceUuid16, serviceData, result)
            }
            "stopAdvertising" -> {
                stopAdvertising()
                result.success(true)
            }
            "isAdvertising" -> {
                result.success(isAdvertising)
            }
            "getCapabilities" -> {
                val supported = advertiser != null
                val adapter = bluetoothAdapter
                result.success(
                    mapOf(
                        "isAdvertisingSupported" to supported,
                        "isMultipleAdvertisementSupported" to (adapter?.isMultipleAdvertisementSupported ?: false),
                        "isBluetoothEnabled" to (adapter?.isEnabled ?: false)
                    )
                )
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startAdvertising(
        serviceUuid16: String,
        serviceData: ByteArray,
        result: MethodChannel.Result
    ) {
        // Re-initialize advertiser if it's null (can happen if Bluetooth was off during plugin init)
        if (advertiser == null) {
            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        }
        
        if (advertiser == null) {
            result.error("BLE_UNAVAILABLE", "BLE advertising not supported on this device", null)
            return
        }

        if (isAdvertising) {
            result.success(true)
            return
        }

        try {
            // Configure advertising settings for low latency (better discoverability)
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false)
                .setTimeout(0) // Advertise indefinitely
                .build()

            // Build the Bluetooth Base UUID from the 16-bit UUID.
            // Note: ParcelUuid/UUID are 128-bit objects in code, but Android will
            // emit the AD structure as 16-bit when using the base UUID form.
            val baseUuidString = "0000${serviceUuid16.lowercase()}-0000-1000-8000-00805f9b34fb"
            val uuid = UUID.fromString(baseUuidString)
            val parcelUuid = ParcelUuid(uuid)

            android.util.Log.d(
                "BleAdvertiser",
                "Starting advertising with Service UUID16: 0x$serviceUuid16, username: ${String(serviceData)}"
            )

            // Keep payload minimal: only Service Data (UUID16 + 7 bytes).
            // This fits comfortably in the 31-byte ADV packet and avoids using a
            // 128-bit Service UUID list which would crowd out the username.
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addServiceData(parcelUuid, serviceData)
                .build()

            // Start advertising (no scan response)
            advertiser?.startAdvertising(settings, data, advertisingCallback)

            isAdvertising = true
            result.success(true)

        } catch (e: Exception) {
            android.util.Log.e("BleAdvertiser", "Failed to start advertising: ${e.message}")
            result.error("ADVERTISING_FAILED", e.message, null)
        }
    }

    private fun stopAdvertising() {
        if (isAdvertising && advertiser != null) {
            try {
                // Mark stopped first to keep callers/lifecycle triggers idempotent.
                isAdvertising = false
                advertiser?.stopAdvertising(advertisingCallback)
                android.util.Log.d("BleAdvertiser", "Advertising stopped")
            } catch (e: Exception) {
                // Ignore errors when stopping
            }
        }
    }

    private val advertisingCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            android.util.Log.d("BleAdvertiser", "✓ Advertising started successfully! Mode: ${settingsInEffect.mode}, TxPower: ${settingsInEffect.txPowerLevel}")
            isAdvertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            val errorMessage = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                else -> "Unknown error: $errorCode"
            }
            
            android.util.Log.e("BleAdvertiser", "✗ Advertising failed: $errorMessage (code: $errorCode)")
            channel.invokeMethod("onAdvertisingError", errorMessage)
        }
    }
}
