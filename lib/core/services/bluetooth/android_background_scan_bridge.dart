import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to native Android background scanning APIs.
class AndroidBackgroundScanBridge {
  static const MethodChannel _channel =
      MethodChannel('com.example.radius/ble_background_scan');

  /// Starts a PendingIntent-based scan (Android background-capable).
  static Future<bool> startPendingIntentScan({
    required List<String> serviceUuids,
    int? manufacturerId,
    Uint8List? manufacturerData,
    Uint8List? manufacturerMask,
    String scanMode = 'low_power',
    int reportDelayMs = 0,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final ok = await _channel.invokeMethod<bool>('startPendingIntentScan', {
      'serviceUuids': serviceUuids,
      'manufacturerId': manufacturerId,
      'manufacturerData': manufacturerData,
      'manufacturerMask': manufacturerMask,
      'scanMode': scanMode,
      'reportDelayMs': reportDelayMs,
    });
    return ok ?? false;
  }

  static Future<void> stopPendingIntentScan() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('stopPendingIntentScan');
  }

  /// Returns and clears buffered scan results captured while the app was woken
  /// via PendingIntent/FGS callbacks.
  static Future<List<Map<String, dynamic>>>
      consumePendingIntentScanResults() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'consumePendingIntentScanResults',
    );
    if (raw == null) return const [];

    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Future<bool> startDiscoveryForegroundService({
    required List<String> serviceUuids,
    int? manufacturerId,
    Uint8List? manufacturerData,
    Uint8List? manufacturerMask,
    String scanMode = 'balanced',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final ok =
        await _channel.invokeMethod<bool>('startDiscoveryForegroundService', {
      'serviceUuids': serviceUuids,
      'manufacturerId': manufacturerId,
      'manufacturerData': manufacturerData,
      'manufacturerMask': manufacturerMask,
      'scanMode': scanMode,
    });
    return ok ?? false;
  }

  static Future<void> stopDiscoveryForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('stopDiscoveryForegroundService');
  }
}
