import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';
import 'ble_device.dart';
import 'ble_id_generator.dart';
import 'ble_scanner_tuning.dart';
import 'ble_safe_logging.dart';
import 'rssi_smoothing.dart';
import '../logging/device_log.dart';

/// Scanning mode used to tune filters for foreground vs background constraints.
enum BleScanMode {
  /// Foreground/user-active scanning.
  ///
  /// Uses a best-effort OR strategy between manufacturer-data and service-UUID
  /// matching by alternating short scan phases.
  foreground,

  /// Background/low-power scanning.
  ///
  /// Prefers service-UUID matching because some OS background APIs require it.
  backgroundLowPower,
}

enum _ScanPhase {
  manufacturer,
  serviceUuid,
  unfilteredFallback,
}

/// Handles BLE scanning for nearby Radius devices.
class BleScanner {
  final Map<String, BleDevice> _discoveredDevices = {};
  final Map<String, RssiVisibilityTracker> _rssiTrackers = {};
  final _devicesController = StreamController<List<BleDevice>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _staleDeviceTimer;
  Timer? _phaseTimer;
  Timer? _overallStopTimer;
  Completer<void>? _scanCompletedCompleter;
  bool _isScanning = false;
  String? _lastError;
  // Base enter threshold for the current scan session.
  // Historically this was a single-sample filter; it is now treated as the
  // scan-session enter threshold, with hysteresis + smoothing applied.
  int _minRssiThreshold = BleConstants.minimumRssiThreshold;

  BleScannerTuning _tuning = const BleScannerTuning();

  BleScanMode _currentMode = BleScanMode.foreground;
  bool _allowUnfilteredFallback = false;
  bool _fallbackAttempted = false;
  _ScanPhase _currentPhase = _ScanPhase.manufacturer;
  int _phaseIndex = 0;

  // Diagnostics counters (best-effort, for debugging only)
  int _scanBatchCount = 0;
  int _rawScanResultCount = 0;
  int _msdMatchedCount = 0;
  int _serviceUuidMatchedCount = 0;
  int _parsedRadiusCount = 0;
  int _filteredByRssiCount = 0;
  int _filteredInvalidPayloadCount = 0;
  int _parsedViaManufacturerPhaseCount = 0;
  int _parsedViaServiceUuidPhaseCount = 0;
  int _parsedViaFallbackPhaseCount = 0;
  DateTime? _lastScanStartedAt;
  DateTime? _lastScanStoppedAt;
  DateTime? _lastSummaryLogAt;

  BleScannerTuning get tuning => BleScannerTuningOverrides.value ?? _tuning;

  void setTuning(BleScannerTuning tuning) {
    _tuning = tuning;
    _rssiTrackers.clear();

    // If scanning is active, restart stale pruning with new interval.
    if (_isScanning) {
      _startStaleDeviceTimer();
    }
  }

  /// Ingests a BLE advertisement decoded by a native background scan path.
  ///
  /// This reuses the same Radius payload parsing + RSSI smoothing/hysteresis
  /// logic as the FlutterBluePlus scan pipeline.
  void ingestAdvertisement({
    required String deviceId,
    required int rssi,
    required Map<int, List<int>> manufacturerData,
    required List<String> serviceUuids,
    String? deviceName,
    DateTime? observedAt,
  }) {
    final at = observedAt ?? DateTime.now();
    final hasServiceUuid = _serviceUuidsContainRadius(serviceUuids);

    final decoded = _decodeAnonymousId(
      manufacturerData: manufacturerData,
      hasServiceUuid: hasServiceUuid,
    );
    if (decoded == null) {
      _filteredInvalidPayloadCount++;
      return;
    }

    // Count decoded Radius devices regardless of whether they end up being visible.
    _parsedRadiusCount++;
    _parsedViaServiceUuidPhaseCount++;

    final device = _applyVisibilityAndBuildDevice(
      anonymousId: decoded.anonymousId,
      isRadiusDevice: decoded.isRadiusDevice,
      deviceId: deviceId,
      rssi: rssi,
      deviceName: deviceName,
      observedAt: at,
    );

    if (device != null) {
      _discoveredDevices[device.anonymousId] = device;
    } else {
      _discoveredDevices.remove(decoded.anonymousId);
    }

    _emitDevices();
  }

  /// Stream of discovered nearby devices.
  Stream<List<BleDevice>> get devicesStream => _devicesController.stream;

  /// Currently discovered devices.
  List<BleDevice> get discoveredDevices => _discoveredDevices.values.toList();

  /// Whether scanning is currently active.
  bool get isScanning => _isScanning;

  /// Last error message from scanning operations.
  String? get lastError => _lastError;

  // ============== Diagnostics (best-effort) ==============

  int get scanBatchCount => _scanBatchCount;
  int get rawScanResultCount => _rawScanResultCount;
  int get msdMatchedCount => _msdMatchedCount;
  int get serviceUuidMatchedCount => _serviceUuidMatchedCount;
  int get parsedRadiusCount => _parsedRadiusCount;
  int get filteredByRssiCount => _filteredByRssiCount;
  int get filteredInvalidPayloadCount => _filteredInvalidPayloadCount;
  int get parsedViaManufacturerPhaseCount => _parsedViaManufacturerPhaseCount;
  int get parsedViaServiceUuidPhaseCount => _parsedViaServiceUuidPhaseCount;
  int get parsedViaFallbackPhaseCount => _parsedViaFallbackPhaseCount;
  DateTime? get lastScanStartedAt => _lastScanStartedAt;
  DateTime? get lastScanStoppedAt => _lastScanStoppedAt;

  void resetDiagnostics() {
    _scanBatchCount = 0;
    _rawScanResultCount = 0;
    _msdMatchedCount = 0;
    _serviceUuidMatchedCount = 0;
    _parsedRadiusCount = 0;
    _filteredByRssiCount = 0;
    _filteredInvalidPayloadCount = 0;
    _parsedViaManufacturerPhaseCount = 0;
    _parsedViaServiceUuidPhaseCount = 0;
    _parsedViaFallbackPhaseCount = 0;
    _lastScanStartedAt = null;
    _lastScanStoppedAt = null;
  }

  /// Starts scanning for nearby BLE devices.
  Future<void> startScan({
    Duration? duration,
    bool continuous = false,
    AndroidScanMode androidScanMode = AndroidScanMode.lowPower,
    int? minRssiThreshold,
    BleScanMode mode = BleScanMode.foreground,
    bool allowUnfilteredFallback = false,
  }) async {
    if (_isScanning) return;

    _isScanning = true;
    _lastError = null;
    _minRssiThreshold = minRssiThreshold ?? BleConstants.minimumRssiThreshold;
    _lastScanStartedAt = DateTime.now();

    _currentMode = mode;
    _allowUnfilteredFallback = allowUnfilteredFallback;
    _fallbackAttempted = false;
    _phaseIndex = 0;
    _currentPhase = _currentMode == BleScanMode.backgroundLowPower
        ? _ScanPhase.serviceUuid
        : _ScanPhase.manufacturer;
    DeviceLog.instance.info('ble.scan', 'startScan()', data: {
      'continuous': continuous,
      'mode': mode.name,
      'allowUnfilteredFallback': allowUnfilteredFallback,
      'androidScanMode': androidScanMode.toString(),
      'timeoutMs': (continuous
          ? null
          : (duration ??
                  const Duration(seconds: BleConstants.scanDurationSeconds))
              .inMilliseconds),
      'minRssiThreshold': _minRssiThreshold,
      'withMsdCompanyId': BleConstants.manufacturerId,
      'withServiceUuid': BleConstants.radiusServiceUuid,
      'msdPrefix': '524401',
    });

    // Start the stale device cleanup timer
    _startStaleDeviceTimer();

    // Configure scan settings
    final scanDuration =
        duration ?? const Duration(seconds: BleConstants.scanDurationSeconds);

    try {
      // Track completion for non-continuous (bounded) scan sessions.
      _scanCompletedCompleter = continuous ? null : Completer<void>();

      // Cancel any existing subscription first
      _scanSubscription?.cancel();

      // Set up scan result listener
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        _handleScanResults,
        onError: (error) {
          _lastError = 'Scan error: $error';
          _isScanning = false;
        },
      );

      // Foreground OR-logic implementation:
      // flutter_blue_plus provides platform-level filters (withServices/withMsd), but
      // those are typically AND'ed when combined. To achieve OR behavior, we alternate
      // short scan phases (service UUID phase + manufacturer-data phase) and union
      // results in-app.
      //
      // Background/low-power mode prefers service UUID filtering because OS background
      // scanning often requires service-based matching.
      await _startScanPhase(androidScanMode: androidScanMode);

      // Rotate phases in foreground to approximate OR logic.
      _phaseTimer?.cancel();
      if (_currentMode == BleScanMode.foreground) {
        _phaseTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
          if (!_isScanning) return;
          await _advancePhase(androidScanMode: androidScanMode);
        });
      }

      // Stop the overall scan after scanDuration for non-continuous scans.
      _overallStopTimer?.cancel();
      if (!continuous) {
        _overallStopTimer = Timer(scanDuration, () {
          stopScan();
        });
      }

      // Preserve legacy behavior: bounded scans only complete when the scan ends.
      if (!continuous) {
        await (_scanCompletedCompleter?.future ?? Future.value());
      }
    } catch (e) {
      _lastError = 'Failed to start scan: $e';
      _isScanning = false;
      _scanCompletedCompleter = null;
      DeviceLog.instance.error('ble.scan', 'startScan() failed',
          error: e,
          stackTrace: StackTrace.current,
          data: {'lastError': _lastError});
      rethrow;
    }
  }

  Future<void> _advancePhase({required AndroidScanMode androidScanMode}) async {
    // Optional unfiltered fallback:
    // Some Android stacks only match service UUID filters if the UUID is present in
    // the primary advertisement (not just scan response). Our Android advertiser
    // places the service UUID in the scan response to stay under the 31-byte ADV limit.
    // If service-UUID-based filtering yields no results, optionally do a short unfiltered
    // scan (foreground + opt-in only) to capture missed devices, then resume filtered.
    if (_allowUnfilteredFallback && !_fallbackAttempted) {
      final noRadiusSoFar = _parsedRadiusCount == 0;
      if (noRadiusSoFar) {
        _fallbackAttempted = true;
        _currentPhase = _ScanPhase.unfilteredFallback;
        DeviceLog.instance.warning(
            'ble.scan', 'Entering unfiltered fallback scan',
            data: {'durationMs': 1200});
        await _restartPlatformScan(
          androidScanMode: androidScanMode,
          withServices: const [],
          withMsd: const [],
        );
        // After a short fallback window, return to filtered OR phases.
        Timer(const Duration(milliseconds: 1200), () async {
          if (!_isScanning) return;
          _currentPhase = _ScanPhase.serviceUuid;
          await _restartPlatformScan(
            androidScanMode: androidScanMode,
            withServices: <Guid>[Guid(BleConstants.radiusServiceUuid)],
            withMsd: const [],
          );
        });
        return;
      }
    }

    // Foreground phase rotation: manufacturer <-> service UUID.
    _phaseIndex = (_phaseIndex + 1) % 2;
    _currentPhase =
        _phaseIndex == 0 ? _ScanPhase.manufacturer : _ScanPhase.serviceUuid;
    await _startScanPhase(androidScanMode: androidScanMode);
  }

  Future<void> _startScanPhase(
      {required AndroidScanMode androidScanMode}) async {
    if (_currentMode == BleScanMode.backgroundLowPower) {
      _currentPhase = _ScanPhase.serviceUuid;
    }

    switch (_currentPhase) {
      case _ScanPhase.manufacturer:
        await _restartPlatformScan(
          androidScanMode: androidScanMode,
          withServices: const [],
          withMsd: [
            MsdFilter(
              BleConstants.manufacturerId,
              data: <int>[0x52, 0x44, 0x01],
              mask: <int>[0xFF, 0xFF, 0xFF],
            ),
          ],
        );
        return;

      case _ScanPhase.serviceUuid:
        await _restartPlatformScan(
          androidScanMode: androidScanMode,
          withServices: <Guid>[Guid(BleConstants.radiusServiceUuid)],
          withMsd: const [],
        );
        return;

      case _ScanPhase.unfilteredFallback:
        await _restartPlatformScan(
          androidScanMode: androidScanMode,
          withServices: const [],
          withMsd: const [],
        );
        return;
    }
  }

  Future<void> _restartPlatformScan({
    required AndroidScanMode androidScanMode,
    required List<Guid> withServices,
    required List<MsdFilter> withMsd,
  }) async {
    try {
      // Stop any existing platform scan before switching filters.
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // Best-effort.
    }

    DeviceLog.instance.debug('ble.scan', 'platform scan phase', data: {
      'phase': _currentPhase.name,
      'withServices': withServices.map((g) => g.toString()).toList(),
      'withMsdCompanyId': withMsd.isEmpty ? null : BleConstants.manufacturerId,
    });

    await FlutterBluePlus.startScan(
      withServices: withServices,
      withMsd: withMsd,
      timeout: null,
      androidScanMode: androidScanMode,
      continuousUpdates: true,
      continuousDivisor: 1,
    );
  }

  /// Stops the current scan.
  Future<void> stopScan() async {
    if (!_isScanning) return;

    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
    } finally {
      _isScanning = false;
      _lastScanStoppedAt = DateTime.now();
      _phaseTimer?.cancel();
      _phaseTimer = null;
      _overallStopTimer?.cancel();
      _overallStopTimer = null;
      _staleDeviceTimer?.cancel();

      final completer = _scanCompletedCompleter;
      _scanCompletedCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }

      DeviceLog.instance.info('ble.scan', 'stopScan()', data: {
        'discoveredCount': _discoveredDevices.length,
        'rawScanResultCount': _rawScanResultCount,
        'parsedRadiusCount': _parsedRadiusCount,
        'serviceUuidMatchedCount': _serviceUuidMatchedCount,
        'filteredByRssiCount': _filteredByRssiCount,
        'filteredInvalidPayloadCount': _filteredInvalidPayloadCount,
        'parsedViaManufacturerPhaseCount': _parsedViaManufacturerPhaseCount,
        'parsedViaServiceUuidPhaseCount': _parsedViaServiceUuidPhaseCount,
        'parsedViaFallbackPhaseCount': _parsedViaFallbackPhaseCount,
      });
    }
  }

  /// Handles incoming scan results.
  void _handleScanResults(List<ScanResult> results) {
    _scanBatchCount++;
    _rawScanResultCount += results.length;

    if (kDebugMode && results.isNotEmpty) {
      logDebug('scanner batch received', {
        'batchSize': results.length,
      });
    }

    // Rate-limited summary log for diagnosing scan pipelines.
    final now = DateTime.now();
    if (_lastSummaryLogAt == null ||
        now.difference(_lastSummaryLogAt!).inSeconds >= 2) {
      _lastSummaryLogAt = now;
      DeviceLog.instance.debug('ble.scan', 'scan batch', data: {
        'batchSize': results.length,
        'rawTotal': _rawScanResultCount,
        'msdMatchedTotal': _msdMatchedCount,
        'serviceUuidMatchedTotal': _serviceUuidMatchedCount,
        'parsedRadiusTotal': _parsedRadiusCount,
        'discoveredCount': _discoveredDevices.length,
        'minRssiThreshold': _minRssiThreshold,
        'phase': _currentPhase.name,
        'mode': _currentMode.name,
      });
    }

    final nowForBatch = DateTime.now();
    for (final result in results) {
      final manufacturerData = result.advertisementData.manufacturerData;
      if (manufacturerData.containsKey(BleConstants.manufacturerId)) {
        _msdMatchedCount++;
      }

      final hasServiceUuid = _hasRadiusServiceUuid(result.advertisementData);
      if (hasServiceUuid) {
        _serviceUuidMatchedCount++;
      }

      // Log all devices with manufacturer data in debug mode
      if (kDebugMode) {
        final mfgData = manufacturerData;
        if (mfgData.isNotEmpty) {
          // Print first bytes of our manufacturer payload if present.
          // Expected: 0x52 0x44 0x01 ... ("RD\x01") + packed anonymous ID.
          final our = mfgData[BleConstants.manufacturerId];
          final prefix = (our == null || our.isEmpty)
              ? ''
              : our
                  .take(6)
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(' ');

          // In debug builds we keep raw payloads for troubleshooting.
          // In release builds, logDebug() redacts sensitive fields.
          logDebug('scanner advertisement', {
            'remoteId': result.device.remoteId.str,
            'advName': result.advertisementData.advName,
            'rssi': result.rssi,
            'manufacturerData': mfgData,
            'radiusPayloadPrefix': prefix.isEmpty ? null : prefix,
          });
        }
      }

      final device = _processDevice(result, observedAt: nowForBatch);
      if (device != null) {
        _discoveredDevices[device.anonymousId] = device;
      }
    }

    _emitDevices();
  }

  BleDevice? _processDevice(ScanResult result, {required DateTime observedAt}) {
    final hasServiceUuid = _hasRadiusServiceUuid(result.advertisementData);

    // Try to extract anonymous ID from manufacturer data.
    // Note: service UUID presence can be used as an additional signal that this is
    // likely our device, but manufacturer data is still required to decode the ID.
    final manufacturerData = result.advertisementData.manufacturerData
        .map((k, v) => MapEntry(k, v.toList()));

    final decoded = _decodeAnonymousId(
      manufacturerData: manufacturerData,
      hasServiceUuid: hasServiceUuid,
    );
    final anonymousId = decoded?.anonymousId;
    final isRadiusDevice = decoded?.isRadiusDevice ?? false;

    // If no anonymous ID found from manufacturer data, this is not a Radius device
    // We filter by manufacturer ID in scan, so if we get here without valid data,
    // the device had our manufacturer ID but invalid data format
    if (anonymousId == null) {
      _filteredInvalidPayloadCount++;
      return null; // Not a valid Radius device
    }

    // Count decoded Radius devices regardless of whether they end up being visible.
    _parsedRadiusCount++;
    switch (_currentPhase) {
      case _ScanPhase.manufacturer:
        _parsedViaManufacturerPhaseCount++;
        break;
      case _ScanPhase.serviceUuid:
        _parsedViaServiceUuidPhaseCount++;
        break;
      case _ScanPhase.unfilteredFallback:
        _parsedViaFallbackPhaseCount++;
        break;
    }
    if (kDebugMode) {
      logDebug('scanner decoded radius device', {
        'anonymousId': anonymousId,
        'phase': _currentPhase.name,
      });
    }

    return _applyVisibilityAndBuildDevice(
      anonymousId: anonymousId,
      isRadiusDevice: isRadiusDevice,
      deviceId: result.device.remoteId.str,
      rssi: result.rssi,
      deviceName: result.advertisementData.advName.isNotEmpty
          ? result.advertisementData.advName
          : null,
      observedAt: observedAt,
    );
  }

  _DecodedRadius? _decodeAnonymousId({
    required Map<int, List<int>> manufacturerData,
    required bool hasServiceUuid,
  }) {
    if (manufacturerData.isEmpty) return null;

    String? anonymousId;
    var isRadiusDevice = false;

    final ourData = manufacturerData[BleConstants.manufacturerId];
    if (ourData != null && ourData.isNotEmpty) {
      anonymousId = BleIdGenerator.parseAnonymousIdFromManufacturerData(
        Uint8List.fromList(ourData),
      );
      if (anonymousId != null) {
        isRadiusDevice = true;
      }
    }

    if (anonymousId == null && hasServiceUuid) {
      for (final bytes in manufacturerData.values) {
        if (bytes.isEmpty) continue;
        anonymousId = BleIdGenerator.parseAnonymousIdFromManufacturerData(
          Uint8List.fromList(bytes),
        );
        if (anonymousId != null) {
          isRadiusDevice = true;
          break;
        }
      }
    }

    if (anonymousId == null) return null;
    return _DecodedRadius(
        anonymousId: anonymousId, isRadiusDevice: isRadiusDevice);
  }

  BleDevice? _applyVisibilityAndBuildDevice({
    required String anonymousId,
    required bool isRadiusDevice,
    required String deviceId,
    required int rssi,
    required DateTime observedAt,
    String? deviceName,
  }) {
    final t = tuning;

    final enterThresholdDbm = t.enterThresholdOverrideDbm ??
        RssiVisibilityTracker.clampDbm(_minRssiThreshold);
    final exitThresholdDbm = _effectiveExitThreshold(enterThresholdDbm, t);

    final tracker = _rssiTrackers.putIfAbsent(
      anonymousId,
      () => RssiVisibilityTracker(
        smoothing: t.rssiSmoothing,
        lastSeen: observedAt,
        isVisible: false,
      ),
    );

    // If tuning changed after tracker creation, recreate tracker.
    if (tracker.smoothing.windowSize != t.rssiSmoothing.windowSize ||
        tracker.smoothing.mode != t.rssiSmoothing.mode ||
        tracker.smoothing.emaAlpha != t.rssiSmoothing.emaAlpha) {
      _rssiTrackers[anonymousId] = RssiVisibilityTracker(
        smoothing: t.rssiSmoothing,
        lastSeen: tracker.lastSeen,
        isVisible: tracker.isVisible,
      );
    }

    final active = _rssiTrackers[anonymousId]!;
    active.observe(
      rssi: rssi,
      at: observedAt,
      enterThresholdDbm: enterThresholdDbm,
      exitThresholdDbm: exitThresholdDbm,
    );

    final smoothed = active.smoothedRssi;
    if (!active.isVisible || smoothed == null) {
      _filteredByRssiCount++;
      return null;
    }

    final proximity = BleDevice.calculateProximity(smoothed);

    return BleDevice(
      anonymousId: anonymousId,
      deviceId: deviceId,
      rssi: smoothed,
      proximity: proximity,
      lastSeen: observedAt,
      isRadiusDevice: isRadiusDevice,
      deviceName:
          (deviceName != null && deviceName.isNotEmpty) ? deviceName : null,
    );
  }

  bool _serviceUuidsContainRadius(List<String> serviceUuids) {
    final target = BleConstants.radiusServiceUuid.toLowerCase();
    for (final u in serviceUuids) {
      final s = u.toLowerCase();
      if (s.contains(target)) return true;
    }
    return false;
  }

  /// Starts timer to remove stale devices.
  void _startStaleDeviceTimer() {
    _staleDeviceTimer?.cancel();
    _staleDeviceTimer = Timer.periodic(
      tuning.staleCleanupInterval,
      (_) => _removeStaleDevices(),
    );
  }

  /// Removes devices that haven't been seen recently.
  void _removeStaleDevices() {
    final now = DateTime.now();
    final staleThreshold = tuning.staleGracePeriod;

    _rssiTrackers.removeWhere((id, tracker) {
      final isStale = now.difference(tracker.lastSeen) > staleThreshold;
      if (isStale) {
        _discoveredDevices.remove(id);
      }
      return isStale;
    });

    // Extra safety: also prune any visible devices that were created before we
    // introduced tracker-based lastSeen, or if map drift occurs.
    _discoveredDevices.removeWhere((id, device) {
      final tracker = _rssiTrackers[id];
      if (tracker != null) return false;
      return now.difference(device.lastSeen) > staleThreshold;
    });

    _emitDevices();
  }

  int _effectiveExitThreshold(int enterThresholdDbm, BleScannerTuning tuning) {
    final override = tuning.exitThresholdOverrideDbm;
    if (override != null) {
      // Ensure exit is not stronger than enter.
      return RssiVisibilityTracker.clampDbm(
        override > enterThresholdDbm ? enterThresholdDbm : override,
      );
    }
    return RssiVisibilityTracker.deriveExitThreshold(
      enterThresholdDbm: enterThresholdDbm,
      hysteresisDb: tuning.hysteresisDb,
    );
  }

  /// Emits the current list of devices.
  void _emitDevices() {
    // Sort by proximity (closest first)
    final sorted = _discoveredDevices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    _devicesController.add(sorted);
  }

  /// Clears all discovered devices.
  void clearDevices() {
    _discoveredDevices.clear();
    _emitDevices();
  }

  /// Gets devices filtered by proximity.
  List<BleDevice> getDevicesByProximity(BleProximity proximity) {
    return _discoveredDevices.values
        .where((d) => d.proximity == proximity)
        .toList();
  }

  /// Gets count of nearby devices (within threshold).
  int get nearbyDeviceCount {
    return _discoveredDevices.values
        .where((d) => d.rssi >= BleConstants.nearbyRssiThreshold)
        .length;
  }

  /// Disposes resources.
  void dispose() {
    stopScan();
    _scanSubscription?.cancel();
    _phaseTimer?.cancel();
    _overallStopTimer?.cancel();
    _staleDeviceTimer?.cancel();
    _devicesController.close();
  }

  bool _hasRadiusServiceUuid(AdvertisementData data) {
    final target = BleConstants.radiusServiceUuid.toLowerCase();

    // serviceUuids may be Guid or String depending on platform/plugin.
    for (final u in data.serviceUuids) {
      final s = u.toString().toLowerCase();
      if (s.contains(target)) return true;
    }

    // Some stacks expose the UUID via serviceData keys.
    for (final k in data.serviceData.keys) {
      final s = k.toString().toLowerCase();
      if (s.contains(target)) return true;
    }

    return false;
  }
}

class _DecodedRadius {
  final String anonymousId;
  final bool isRadiusDevice;

  const _DecodedRadius({
    required this.anonymousId,
    required this.isRadiusDevice,
  });
}
