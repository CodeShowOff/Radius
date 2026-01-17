package com.example.radius

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.Intent
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
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
        private const val DEBUG_MANUFACTURER_ID = 0xFFFF

        // Signature to distinguish Radius packets from other apps.
        // Format: ['R','D', version=1] + packedAnonymousIdBytes
        private val RADIUS_MAGIC = byteArrayOf(0x52, 0x44, 0x01)
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
                val txPowerLevel = call.argument<Int>("androidTxPowerLevel") ?: 2
                val advertiseMode = call.argument<Int>("androidAdvertiseMode") ?: 2
                val manufacturerId = call.argument<Number>("manufacturerId")?.toInt()
                    ?: if (BuildConfig.DEBUG) DEBUG_MANUFACTURER_ID else 0
                
                if (anonymousId == null) {
                    result.error("INVALID_ARGUMENT", "anonymousId is required", null)
                    return
                }

                startAdvertising(anonymousId, serviceUuid, manufacturerId, txPowerLevel, advertiseMode, result)
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
            "updateAdvertisement" -> {
                val anonymousId = call.argument<String>("anonymousId")
                val serviceUuid = call.argument<String>("serviceUuid") ?: RADIUS_SERVICE_UUID
                val txPowerLevel = call.argument<Int>("androidTxPowerLevel") ?: 2
                val advertiseMode = call.argument<Int>("androidAdvertiseMode") ?: 2
                val manufacturerId = call.argument<Number>("manufacturerId")?.toInt()
                    ?: if (BuildConfig.DEBUG) DEBUG_MANUFACTURER_ID else 0
                
                if (anonymousId == null) {
                    result.error("INVALID_ARGUMENT", "anonymousId is required", null)
                    return
                }

                // Restart advertising with new data
                stopAdvertising()
                startAdvertising(anonymousId, serviceUuid, manufacturerId, txPowerLevel, advertiseMode, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startAdvertising(
        anonymousId: String,
        serviceUuid: String,
        manufacturerId: Int,
        txPowerLevel: Int,
        advertiseMode: Int,
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
            // Start a minimal foreground service to keep advertising reliable when
            // the app is backgrounded (Android often throttles/halts advertising otherwise).
            startBleForegroundService()

            // Configure advertising settings
            val mode = when (advertiseMode) {
                0 -> AdvertiseSettings.ADVERTISE_MODE_LOW_POWER
                1 -> AdvertiseSettings.ADVERTISE_MODE_BALANCED
                else -> AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
            }

            val txPower = when (txPowerLevel) {
                0 -> AdvertiseSettings.ADVERTISE_TX_POWER_LOW
                1 -> AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM
                else -> AdvertiseSettings.ADVERTISE_TX_POWER_HIGH
            }

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(mode)
                .setTxPowerLevel(txPower)
                .setConnectable(false)
                .setTimeout(0) // Advertise indefinitely
                .build()

            // Convert anonymous ID (hex string) into compact bytes.
            // This keeps the advertising payload small enough to fit within the 31-byte legacy ADV limit.
            val idBytes = hexToBytes(anonymousId)

            // Prefix with a small signature to avoid collisions with other 0xFFFF advertisers.
            val payload = ByteArray(RADIUS_MAGIC.size + idBytes.size)
            System.arraycopy(RADIUS_MAGIC, 0, payload, 0, RADIUS_MAGIC.size)
            System.arraycopy(idBytes, 0, payload, RADIUS_MAGIC.size, idBytes.size)
            
            android.util.Log.d("BleAdvertiser", "Starting advertising with ID: $anonymousId (${idBytes.size} bytes)")

            // Configure advertising data
            if (!BuildConfig.DEBUG && (manufacturerId == 0 || manufacturerId == DEBUG_MANUFACTURER_ID)) {
                android.util.Log.w(
                    "BleAdvertiser",
                    "Production manufacturerId is not configured (id=$manufacturerId). " +
                        "Pass --dart-define=RADIUS_MANUFACTURER_ID=<Bluetooth SIG company id>"
                )
            }
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addManufacturerData(manufacturerId, payload)
                .build()

            // Put the service UUID in scan response to avoid exceeding the legacy 31-byte ADV limit.
            val scanResponse = try {
                AdvertiseData.Builder()
                    .setIncludeDeviceName(false)
                    .setIncludeTxPowerLevel(false)
                    .addServiceUuid(ParcelUuid(UUID.fromString(serviceUuid)))
                    .build()
            } catch (e: Exception) {
                null
            }
            
            android.util.Log.d(
                "BleAdvertiser",
                "Advertising data configured with service UUID: $serviceUuid, manufacturer ID: 0x${manufacturerId.toString(16)}"
            )

            // Start advertising
            if (scanResponse != null) {
                advertiser?.startAdvertising(settings, data, scanResponse, advertisingCallback)
            } else {
                advertiser?.startAdvertising(settings, data, advertisingCallback)
            }

            isAdvertising = true
            result.success(true)

        } catch (e: Exception) {
            stopBleForegroundService()
            result.error("ADVERTISING_FAILED", e.message, null)
        }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val normalized = hex.trim()
        require(normalized.length % 2 == 0) { "Hex string must have even length" }
        val out = ByteArray(normalized.length / 2)
        var i = 0
        while (i < normalized.length) {
            val byteStr = normalized.substring(i, i + 2)
            out[i / 2] = byteStr.toInt(16).toByte()
            i += 2
        }
        return out
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

        stopBleForegroundService()
    }

    private fun startBleForegroundService() {
        try {
            val intent = Intent(context, BleForegroundService::class.java).apply {
                action = BleForegroundService.ACTION_START
            }
            ContextCompat.startForegroundService(context, intent)
        } catch (_: Exception) {
            // Best-effort. Advertising may still work without the service.
        }
    }

    private fun stopBleForegroundService() {
        try {
            context.stopService(Intent(context, BleForegroundService::class.java))
        } catch (_: Exception) {
            // Best-effort.
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
            stopBleForegroundService()
            channel.invokeMethod("onAdvertisingError", errorMessage)
        }
    }
}
