package com.example.radius

import android.bluetooth.le.ScanSettings
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Exposes Android background scan APIs to Flutter.
 */
class BleBackgroundScanPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    companion object {
        private const val CHANNEL_NAME = "com.example.radius/ble_background_scan"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startPendingIntentScan" -> {
                try {
                    val serviceUuids = call.argument<List<String>>("serviceUuids") ?: emptyList()
                    val manufacturerId = call.argument<Number>("manufacturerId")?.toInt()
                    val manufacturerData = call.argument<ByteArray>("manufacturerData")
                    val manufacturerMask = call.argument<ByteArray>("manufacturerMask")

                    val scanModeStr = call.argument<String>("scanMode") ?: "low_power"
                    val scanMode = when (scanModeStr) {
                        "low_latency" -> ScanSettings.SCAN_MODE_LOW_LATENCY
                        "balanced" -> ScanSettings.SCAN_MODE_BALANCED
                        else -> ScanSettings.SCAN_MODE_LOW_POWER
                    }

                    val reportDelayMs = call.argument<Number>("reportDelayMs")?.toLong() ?: 0L

                    PendingIntentBleScanner.start(
                        context,
                        serviceUuids,
                        manufacturerId,
                        manufacturerData,
                        manufacturerMask,
                        scanMode,
                        reportDelayMs
                    )
                    result.success(true)
                } catch (e: Exception) {
                    result.error("START_FAILED", e.message, null)
                }
            }

            "stopPendingIntentScan" -> {
                PendingIntentBleScanner.stop(context)
                result.success(true)
            }

            "consumePendingIntentScanResults" -> {
                val arr: JSONArray = BleScanResultStore.consume(context)
                val out = mutableListOf<Map<String, Any?>>()
                for (i in 0 until arr.length()) {
                    val wrapper = arr.optJSONObject(i) ?: continue
                    // wrapper has {type, tsMs, results:[...]}
                    val resultsArr = wrapper.optJSONArray("results") ?: JSONArray()
                    for (j in 0 until resultsArr.length()) {
                        val r = resultsArr.optJSONObject(j) ?: continue
                        out.add(jsonToMap(r))
                    }
                }
                result.success(out)
            }

            "startDiscoveryForegroundService" -> {
                try {
                    val intent = BleDiscoveryForegroundService.buildStartIntent(context, call)
                    androidx.core.content.ContextCompat.startForegroundService(context, intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("FGS_START_FAILED", e.message, null)
                }
            }

            "stopDiscoveryForegroundService" -> {
                try {
                    context.startService(
                        BleDiscoveryForegroundService.buildStopIntent(context)
                    )
                } catch (_: Exception) {
                }
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun jsonToMap(obj: JSONObject): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["address"] = obj.optString("address", "")
        out["rssi"] = obj.optInt("rssi", -127)
        out["timestampNanos"] = obj.optLong("timestampNanos", 0L)
        out["deviceName"] = obj.optString("deviceName", "")

        val uuids = obj.optJSONArray("serviceUuids") ?: JSONArray()
        val uuidList = mutableListOf<String>()
        for (i in 0 until uuids.length()) {
            uuidList.add(uuids.optString(i, ""))
        }
        out["serviceUuids"] = uuidList

        val mfg = obj.optJSONObject("manufacturerData") ?: JSONObject()
        val mfgMap = HashMap<Int, ByteArray>()
        val keys = mfg.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            val b64 = mfg.optString(k, "")
            if (b64.isNotEmpty()) {
                try {
                    mfgMap[k.toInt()] = BleScanResultStore.decodeBytes(b64)
                } catch (_: Exception) {
                }
            }
        }
        out["manufacturerData"] = mfgMap

        return out
    }
}
