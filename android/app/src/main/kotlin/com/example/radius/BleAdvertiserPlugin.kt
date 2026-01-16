package com.example.radius

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Native Android BLE Advertiser Plugin
 * 
 * Provides BLE peripheral/advertising functionality using Android's
 * BluetoothLeAdvertiser API.
 */
class BleAdvertiserPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false

    companion object {
        private const val CHANNEL_NAME = "com.example.radius/ble_advertiser"
        private const val RADIUS_SERVICE_UUID = "00001234-0000-1000-8000-00805f9b34fb"
        private const val MANUFACTURER_ID = 0xFFFF
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stopAdvertising()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> {
                val anonymousId = call.argument<String>("anonymousId")
                val serviceUuid = call.argument<String>("serviceUuid") ?: RADIUS_SERVICE_UUID
                
                if (anonymousId == null) {
                    result.error("INVALID_ARGUMENT", "anonymousId is required", null)
                    return
                }

                startAdvertising(anonymousId, serviceUuid, result)
            }
            "stopAdvertising" -> {
                stopAdvertising()
                result.success(true)
            }
            "isAdvertising" -> {
                result.success(isAdvertising)
            }
            "updateAdvertisement" -> {
                val anonymousId = call.argument<String>("anonymousId")
                val serviceUuid = call.argument<String>("serviceUuid") ?: RADIUS_SERVICE_UUID
                
                if (anonymousId == null) {
                    result.error("INVALID_ARGUMENT", "anonymousId is required", null)
                    return
                }

                // Restart advertising with new data
                stopAdvertising()
                startAdvertising(anonymousId, serviceUuid, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startAdvertising(
        anonymousId: String,
        serviceUuid: String,
        result: MethodChannel.Result
    ) {
        if (advertiser == null) {
            result.error("BLE_UNAVAILABLE", "BLE advertising not supported on this device", null)
            return
        }

        if (isAdvertising) {
            result.success(true)
            return
        }

        try {
            // Configure advertising settings
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)  // Changed for better discovery
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)      // Changed for better range
                .setConnectable(false)
                .setTimeout(0) // Advertise indefinitely
                .build()

            // Convert anonymous ID to bytes
            val idBytes = anonymousId.toByteArray(Charsets.UTF_8)
            
            android.util.Log.d("BleAdvertiser", "Starting advertising with ID: $anonymousId (${idBytes.size} bytes)")

            // Configure advertising data
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addServiceUuid(ParcelUuid.fromString(serviceUuid))
                .addManufacturerData(MANUFACTURER_ID, idBytes)
                .build()
            
            android.util.Log.d("BleAdvertiser", "Advertising data configured with service UUID: $serviceUuid, manufacturer ID: 0x${MANUFACTURER_ID.toString(16)}")

            // Start advertising
            advertiser?.startAdvertising(settings, data, advertisingCallback)

            isAdvertising = true
            result.success(true)

        } catch (e: Exception) {
            result.error("ADVERTISING_FAILED", e.message, null)
        }
    }

    private fun stopAdvertising() {
        if (isAdvertising && advertiser != null) {
            try {
                advertiser?.stopAdvertising(advertisingCallback)
            } catch (e: Exception) {
                // Ignore errors when stopping
            }
            isAdvertising = false
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
