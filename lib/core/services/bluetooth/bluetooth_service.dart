import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive/hive.dart';

import 'ble_advertiser.dart';
import 'ble_constants.dart';
import 'ble_diagnostics.dart';
import 'ble_device.dart';
import 'ble_id_generator.dart';
import 'ble_permission_handler.dart';
import 'ble_range_mode.dart';
import 'ble_scanner.dart';
import 'android_background_scan_bridge.dart';
import 'ble_scanner_tuning.dart';
import 'ble_scanner_tuning_remote_config.dart';
import 'ble_safe_logging.dart';
import '../logging/device_log.dart';

/// BLE service state.
enum BluetoothServiceState {
  /// Service is not initialized.
  uninitialized,

  /// Service is initializing.
  initializing,

  /// Service is ready but not active.
  ready,

  /// Service is actively scanning/advertising.
  active,

  /// Service encountered an error.
  error,

  /// Bluetooth is turned off.
  bluetoothOff,

  /// Required permissions not granted.
  permissionDenied,
}

/// Main Bluetooth service coordinating scanning and advertising.
class BluetoothService {
  final BlePermissionHandler _permissionHandler;
  final BleIdGenerator _idGenerator;
  final BleScanner _scanner;
  late final BleAdvertiser _advertiser;

  final _stateController = StreamController<BluetoothServiceState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  BluetoothServiceState _state = BluetoothServiceState.uninitialized;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _scanIntervalTimer;
  String? _lastError;

  // Diagnostics counters requested for production-safe visibility.
  int _scanStartFailures = 0;
  int _advertiseStartFailures = 0;
  final Map<String, int> _permissionDeniedCounts = <String, int>{};
  DateTime? _lastAdvertiseStartedAt;
  DateTime? _lastAdvertiseStoppedAt;
  DateTime? _lastPermissionDeniedAt;

  bool _appInForeground = true;
  bool _prefsLoaded = false;
  bool _keepDiscoveringInBackground = false;
  bool _useForegroundServiceForBackgroundDiscovery = false;

  bool _pendingIntentScanActive = false;
  bool _fgsDiscoveryActive = false;

  // Track the most recent scan parameters so we can resume after background.
  bool _lastScanContinuous = false;
  bool _lastScanInterval = false;
  BleRangeMode _lastScanRangeMode = BleRangeMode.large;
  Duration? _lastScanDuration;

  static const String _prefsBoxName = 'radius_prefs';
  static const String _prefsKeyKeepDiscoveringInBackground =
      'keep_discovering_in_background';
  static const String _prefsKeyUseFgs =
      'background_discovery_use_foreground_service';

  BluetoothService({
    BlePermissionHandler? permissionHandler,
    BleIdGenerator? idGenerator,
    BleScanner? scanner,
  })  : _permissionHandler = permissionHandler ?? BlePermissionHandler(),
        _idGenerator = idGenerator ?? BleIdGenerator(),
        _scanner = scanner ?? BleScanner() {
    _advertiser = BleAdvertiser(idGenerator: _idGenerator);
  }

  // ============== Getters ==============

  /// Current service state.
  BluetoothServiceState get state => _state;

  /// Stream of state changes.
  Stream<BluetoothServiceState> get stateStream => _stateController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Stream of discovered devices.
  Stream<List<BleDevice>> get devicesStream => _scanner.devicesStream;

  /// Currently discovered devices.
  List<BleDevice> get discoveredDevices => _scanner.discoveredDevices;

  /// Whether scanning is active.
  bool get isScanning => _scanner.isScanning;

  /// Whether advertising is active.
  bool get isAdvertising => _advertiser.isAdvertising;

  /// The current anonymous ID being used.
  String get currentAnonymousId => _idGenerator.currentAnonymousId;

  /// Last error message.
  String? get lastError => _lastError;

  /// Stream of anonymous ID rotations.
  ///
  /// Useful for updating the user's current BLE identifier in Firestore.
  Stream<String> get idRotationStream => _idGenerator.idRotationStream;

  /// Best-effort diagnostics snapshot for debugging discovery.
  BleDiagnosticsSnapshot get diagnostics => BleDiagnosticsSnapshot(
        isScanning: _scanner.isScanning,
        isAdvertising: _advertiser.isAdvertising,
        platformDiscoveryNote: _iosBackgroundDiscoveryNote(),
        lastError: _lastError,
        scanBatchCount: _scanner.scanBatchCount,
        rawScanResultCount: _scanner.rawScanResultCount,
        msdMatchedCount: _scanner.msdMatchedCount,
        serviceUuidMatchedCount: _scanner.serviceUuidMatchedCount,
        parsedRadiusCount: _scanner.parsedRadiusCount,
        filteredByRssiCount: _scanner.filteredByRssiCount,
        filteredInvalidPayloadCount: _scanner.filteredInvalidPayloadCount,
        scanStartFailures: _scanStartFailures,
        advertiseStartFailures: _advertiseStartFailures,
        permissionDeniedCounts: Map<String, int>.unmodifiable(
          _permissionDeniedCounts,
        ),
        lastScanStartedAt: _scanner.lastScanStartedAt,
        lastScanStoppedAt: _scanner.lastScanStoppedAt,
        lastAdvertiseStartedAt: _lastAdvertiseStartedAt,
        lastAdvertiseStoppedAt: _lastAdvertiseStoppedAt,
        lastPermissionDeniedAt: _lastPermissionDeniedAt,
      );

  String? _iosBackgroundDiscoveryNote() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    if (_appInForeground) return null;
    return 'iOS background BLE discovery is limited; fewer scan results may be delivered. Keep the app in the foreground for the most reliable discovery.';
  }

  void _recordPermissionDenied(String operation, BlePermissionStatus status) {
    final key = '$operation:${status.name}';
    _permissionDeniedCounts[key] = (_permissionDeniedCounts[key] ?? 0) + 1;
    _lastPermissionDeniedAt = DateTime.now();
  }

  /// Current scanner tuning (defaults + Remote Config + optional overrides).
  BleScannerTuning get scannerTuning => _scanner.tuning;

  /// Runtime tuning override hook (intended for debug screens).
  ///
  /// This does not require UI changes now; callers can invoke it from debug
  /// tooling later.
  void setScannerTuningOverride(BleScannerTuning? override) {
    BleScannerTuningOverrides.set(override);
    // Re-apply to restart stale timers and clear smoothing state.
    _scanner.setTuning(_scanner.tuning);
  }

  bool get keepDiscoveringInBackground => _keepDiscoveringInBackground;
  bool get useForegroundServiceForBackgroundDiscovery =>
      _useForegroundServiceForBackgroundDiscovery;

  Future<void> refreshBackgroundDiscoveryPreferences() async {
    await _ensurePrefsLoaded();
  }

  /// Called by app-wide lifecycle observers.
  void onAppForegroundChanged(bool isForeground) {
    if (_appInForeground == isForeground) return;
    _appInForeground = isForeground;

    if (!isForeground) {
      unawaited(_switchToBackgroundScanIfNeeded());
    } else {
      unawaited(_switchToForegroundScanIfNeeded());
    }
  }

  Future<void> setBackgroundDiscoveryPreference({
    required bool enabled,
    required bool useForegroundService,
  }) async {
    _keepDiscoveringInBackground = enabled;
    _useForegroundServiceForBackgroundDiscovery = useForegroundService;

    try {
      final box = await Hive.openBox(_prefsBoxName);
      await box.put(_prefsKeyKeepDiscoveringInBackground, enabled);
      await box.put(_prefsKeyUseFgs, useForegroundService);
    } catch (e) {
      DeviceLog.instance.warning('ble', 'Failed to persist prefs',
          data: {'error': e.toString()});
    }

    // If the user disables background discovery, clean up any native scanners.
    if (!enabled) {
      await _stopNativeBackgroundScanning();
    }
  }

  Future<void> _ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;

    try {
      final box = await Hive.openBox(_prefsBoxName);
      _keepDiscoveringInBackground =
          (box.get(_prefsKeyKeepDiscoveringInBackground) as bool?) ?? false;
      _useForegroundServiceForBackgroundDiscovery =
          (box.get(_prefsKeyUseFgs) as bool?) ?? false;
    } catch (e) {
      DeviceLog.instance.warning('ble', 'Failed to load prefs',
          data: {'error': e.toString()});
    }
  }

  /// Number of nearby devices.
  int get nearbyDeviceCount => _scanner.nearbyDeviceCount;

  // ============== Initialization ==============

  /// Initializes the Bluetooth service.
  /// Set [forceReinit] to true to reset and reinitialize even if already initialized.
  Future<bool> initialize({bool forceReinit = false}) async {
    // Allow reinitialization if in error/bluetoothOff state or if forced
    if (!forceReinit && _state != BluetoothServiceState.uninitialized) {
      // If already ready or active, return true
      if (_state == BluetoothServiceState.ready ||
          _state == BluetoothServiceState.active) {
        return true;
      }
      // If in error or bluetoothOff state, allow re-initialization
      if (_state != BluetoothServiceState.error &&
          _state != BluetoothServiceState.bluetoothOff &&
          _state != BluetoothServiceState.permissionDenied) {
        return false;
      }
    }

    _setState(BluetoothServiceState.initializing);

    DeviceLog.instance.info('ble', 'initialize()', data: {
      'forceReinit': forceReinit,
      'prevState': _state.name,
    });

    try {
      // Enable verbose logging in debug mode
      if (kDebugMode) {
        FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);
        debugPrint('[BLE] Initializing Bluetooth service...');
      }

      // Check if Bluetooth is supported
      if (!await FlutterBluePlus.isSupported) {
        _setError('Bluetooth is not supported on this device');
        _setState(BluetoothServiceState.error);
        DeviceLog.instance.error('ble', 'Bluetooth not supported');
        return false;
      }

      // Initialization should not force SCAN permission.
      // Operation-specific permissions are requested in startScanning/startAdvertising.
      final permissionStatus =
          await _permissionHandler.checkAndRequestPermissions(
        needsScan: false,
        needsConnect: true,
        needsAdvertise: false,
      );

      DeviceLog.instance.info('ble', 'initialize permission result', data: {
        'status': permissionStatus.name,
      });

      if (permissionStatus == BlePermissionStatus.bluetoothOff) {
        // Bluetooth is off, try to turn it on (shows system dialog on Android)
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));
        _setState(BluetoothServiceState.bluetoothOff);

        // Request user to turn on Bluetooth
        final turnedOn = await _permissionHandler.requestBluetoothOn();
        DeviceLog.instance.info('ble', 'requestBluetoothOn() from initialize',
            data: {'turnedOn': turnedOn});
        if (!turnedOn) {
          return false;
        }

        // Wait a moment for Bluetooth to fully initialize
        await Future.delayed(const Duration(milliseconds: 500));

        // Re-check Bluetooth state
        final isOn = await _permissionHandler.isBluetoothOn();
        if (!isOn) {
          return false;
        }

        // Bluetooth is now on, continue initialization
      } else if (permissionStatus != BlePermissionStatus.granted) {
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));
        _setState(BluetoothServiceState.permissionDenied);
        DeviceLog.instance
            .warning('ble', 'initialize permission denied', data: {
          'status': permissionStatus.name,
          'message': _lastError,
        });
        return false;
      }

      // Initialize ID generator
      _idGenerator.initialize();

      await _ensurePrefsLoaded();

      // Best-effort: load scan stabilization parameters from Remote Config.
      // If Remote Config is unavailable, defaults remain.
      final tuning = await BleScannerTuningRemoteConfig.fetchAndActivate();
      _scanner.setTuning(tuning);

      // Best-effort diagnostics: advertising support varies by device.
      // We don't hard-fail initialization if advertising isn't supported,
      // because scanning can still work and the user can still discover others.
      final caps = await _advertiser.getCapabilities();
      final advertisingSupported = caps['isAdvertisingSupported'];
      if (advertisingSupported is bool && advertisingSupported == false) {
        if (kDebugMode) {
          debugPrint('[BLE] Advertising not supported on this device');
        }
        DeviceLog.instance.warning('ble', 'Advertising not supported');
      }

      // Listen for Bluetooth adapter state changes
      _adapterStateSubscription = _permissionHandler.adapterStateStream.listen(
        _handleAdapterStateChange,
      );

      _setState(BluetoothServiceState.ready);
      DeviceLog.instance.info('ble', 'initialize() OK');
      return true;
    } catch (e) {
      _setError('Failed to initialize Bluetooth: $e');
      _setState(BluetoothServiceState.error);
      DeviceLog.instance.error('ble', 'initialize() failed',
          error: e, stackTrace: StackTrace.current);
      return false;
    }
  }

  // ============== Scanning ==============

  /// Starts scanning for nearby devices.
  Future<bool> startScanning({
    bool continuous = false,
    BleRangeMode rangeMode = BleRangeMode.large,
    Duration? duration,
    bool intervalScan = false,
  }) async {
    await _ensurePrefsLoaded();

    _lastScanContinuous = continuous;
    _lastScanInterval = intervalScan;
    _lastScanRangeMode = rangeMode;
    _lastScanDuration = duration;

    if (_state != BluetoothServiceState.ready &&
        _state != BluetoothServiceState.active) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      DeviceLog.instance.info('ble', 'startScanning()', data: {
        'continuous': continuous,
        'rangeMode': rangeMode.name,
        'durationMs': duration?.inMilliseconds,
        'intervalScan': intervalScan,
      });

      // Scanning requires SCAN permission (Android 12+).
      var permissionStatus =
          await _permissionHandler.checkAndRequestPermissions(
        needsScan: true,
        needsConnect: true,
        needsAdvertise: false,
      );

      DeviceLog.instance.info('ble', 'startScanning permission result', data: {
        'status': permissionStatus.name,
      });

      if (permissionStatus == BlePermissionStatus.bluetoothOff) {
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));
        _setState(BluetoothServiceState.bluetoothOff);

        final turnedOn = await _permissionHandler.requestBluetoothOn();
        DeviceLog.instance.info(
            'ble', 'requestBluetoothOn() from startScanning',
            data: {'turnedOn': turnedOn});
        if (!turnedOn) return false;

        await Future.delayed(const Duration(milliseconds: 500));
        permissionStatus = await _permissionHandler.checkAndRequestPermissions(
          needsScan: true,
          needsConnect: true,
          needsAdvertise: false,
        );
      }

      if (permissionStatus != BlePermissionStatus.granted) {
        _scanStartFailures++;
        _recordPermissionDenied('startScanning', permissionStatus);
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));
        _setState(BluetoothServiceState.permissionDenied);
        DeviceLog.instance.warning('ble', 'startScanning permission denied',
            data: {'status': permissionStatus.name, 'message': _lastError});
        return false;
      }

      await _scanner.startScan(
        duration: duration,
        continuous: continuous,
        androidScanMode:
            continuous ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
        minRssiThreshold: rangeMode.minRssiThreshold,
      );
      _setState(BluetoothServiceState.active);
      DeviceLog.instance.info('ble', 'startScanning() OK');

      // If the user opted into foreground-service mode for background discovery,
      // start the discovery FGS while we're still in the foreground.
      if (defaultTargetPlatform == TargetPlatform.android &&
          _keepDiscoveringInBackground &&
          _useForegroundServiceForBackgroundDiscovery &&
          continuous) {
        final started = await _startDiscoveryForegroundService();
        _fgsDiscoveryActive = started;
      }

      if (!continuous && intervalScan) {
        // Optional interval scanning for battery optimization.
        _startIntervalScanning(rangeMode);
      }

      return true;
    } catch (e) {
      _scanStartFailures++;
      _setError(_scanner.lastError ?? 'Failed to start scanning: $e');
      DeviceLog.instance.error('ble', 'startScanning() failed',
          error: e,
          stackTrace: StackTrace.current,
          data: {'lastError': _lastError});

      // Helpful but safe: no identifiers.
      logDebug('startScanning failed', {
        'error': e.toString(),
        'lastError': _lastError,
      });
      return false;
    }
  }

  /// Stops scanning for nearby devices.
  Future<void> stopScanning() async {
    _scanIntervalTimer?.cancel();
    await _scanner.stopScan();

    await _stopNativeBackgroundScanning();

    DeviceLog.instance.info('ble', 'stopScanning()', data: {
      'isAdvertising': _advertiser.isAdvertising,
    });

    if (!_advertiser.isAdvertising) {
      _setState(BluetoothServiceState.ready);
    }
  }

  Future<void> _stopNativeBackgroundScanning() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    if (_pendingIntentScanActive) {
      _pendingIntentScanActive = false;
      await AndroidBackgroundScanBridge.stopPendingIntentScan();
    }

    if (_fgsDiscoveryActive) {
      _fgsDiscoveryActive = false;
      await AndroidBackgroundScanBridge.stopDiscoveryForegroundService();
    }
  }

  Future<bool> _startPendingIntentBackgroundScan() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    if (_pendingIntentScanActive) return true;

    final ok = await AndroidBackgroundScanBridge.startPendingIntentScan(
      serviceUuids: <String>[BleConstants.radiusServiceUuid],
      manufacturerId: BleConstants.manufacturerId,
      manufacturerData: Uint8List.fromList(const [0x52, 0x44, 0x01]),
      manufacturerMask: Uint8List.fromList(const [0xFF, 0xFF, 0xFF]),
      scanMode: 'low_power',
      reportDelayMs: 0,
    );

    _pendingIntentScanActive = ok;
    return ok;
  }

  Future<bool> _startDiscoveryForegroundService() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final ok =
        await AndroidBackgroundScanBridge.startDiscoveryForegroundService(
      serviceUuids: <String>[BleConstants.radiusServiceUuid],
      manufacturerId: BleConstants.manufacturerId,
      manufacturerData: Uint8List.fromList(const [0x52, 0x44, 0x01]),
      manufacturerMask: Uint8List.fromList(const [0xFF, 0xFF, 0xFF]),
      scanMode: 'balanced',
    );
    return ok;
  }

  Future<void> _switchToBackgroundScanIfNeeded() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS background scanning is much more strict than foreground.
      // Prefer service-UUID filtering only, because iOS may omit manufacturer data
      // and/or drop scan-response fields when the app is backgrounded.
      if (!_scanner.isScanning || !_lastScanContinuous) return;

      try {
        await _scanner.stopScan();
        await _scanner.startScan(
          duration: _lastScanDuration,
          continuous: true,
          // androidScanMode is ignored on iOS.
          androidScanMode: AndroidScanMode.lowPower,
          minRssiThreshold: _lastScanRangeMode.minRssiThreshold,
          mode: BleScanMode.backgroundLowPower,
          allowUnfilteredFallback: false,
        );
        logDebug('iOS background scan mode enabled', {
          'mode': 'backgroundLowPower',
          'filter': 'serviceUuidOnly',
        });
      } catch (e) {
        // Best-effort.
        logDebug('Failed to switch to iOS background scan mode', {
          'error': e.toString(),
        });
      }

      // Note: iOS advertising may be throttled or stopped when the app is suspended
      // or force-quit. We intentionally do not rely on continuous advertising while
      // backgrounded.
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _ensurePrefsLoaded();

    // Only switch if we are actively doing continuous discovery.
    if (!_scanner.isScanning || !_lastScanContinuous) return;
    if (!_keepDiscoveringInBackground) {
      // Legacy behavior: stop scanning when backgrounded.
      await stopScanning();
      return;
    }

    // Stop FlutterBluePlus scanning. Background scanning is handled natively.
    await _scanner.stopScan();

    // Prefer opt-in foreground service mode if enabled (already started while
    // foreground in startScanning()). If it isn't active, fall back to PendingIntent.
    if (_useForegroundServiceForBackgroundDiscovery && _fgsDiscoveryActive) {
      return;
    }

    final started = await _startPendingIntentBackgroundScan();
    if (!started) {
      DeviceLog.instance.warning(
          'ble', 'PendingIntent scan failed; falling back',
          data: {'useFgs': _useForegroundServiceForBackgroundDiscovery});
      if (_useForegroundServiceForBackgroundDiscovery && !_fgsDiscoveryActive) {
        _fgsDiscoveryActive = await _startDiscoveryForegroundService();
      }
    }
  }

  Future<void> _switchToForegroundScanIfNeeded() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Restore the more permissive foreground scan behavior (OR logic between
      // manufacturer matching and service-UUID matching).
      if (_lastScanContinuous) {
        try {
          await _scanner.stopScan();
          await _scanner.startScan(
            duration: _lastScanDuration,
            continuous: true,
            androidScanMode: AndroidScanMode.lowLatency,
            minRssiThreshold: _lastScanRangeMode.minRssiThreshold,
            mode: BleScanMode.foreground,
            allowUnfilteredFallback: false,
          );
          logDebug('iOS foreground scan mode restored', {
            'mode': 'foreground',
          });
        } catch (e) {
          logDebug('Failed to restore iOS foreground scan mode', {
            'error': e.toString(),
          });
        }
      }
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) return;

    // Stop native background scanning and ingest any buffered results.
    final buffered =
        await AndroidBackgroundScanBridge.consumePendingIntentScanResults();
    if (buffered.isNotEmpty) {
      _ingestNativeScanResults(buffered);
    }
    await _stopNativeBackgroundScanning();

    // Resume Flutter scanning if it was active before background.
    if (_lastScanContinuous) {
      // Best-effort restart. Any permission issues will be handled by startScanning().
      await startScanning(
        continuous: true,
        rangeMode: _lastScanRangeMode,
        duration: _lastScanDuration,
        intervalScan: _lastScanInterval,
      );
    }
  }

  void _ingestNativeScanResults(List<Map<String, dynamic>> results) {
    for (final r in results) {
      final address = (r['address'] as String?) ?? '';
      final rssi = (r['rssi'] as int?) ?? -127;
      final deviceName = (r['deviceName'] as String?)?.trim();

      final uuidsDynamic = r['serviceUuids'];
      final serviceUuids = <String>[];
      if (uuidsDynamic is List) {
        for (final u in uuidsDynamic) {
          if (u is String && u.isNotEmpty) serviceUuids.add(u);
        }
      }

      final manufacturerData = <int, List<int>>{};
      final md = r['manufacturerData'];
      if (md is Map) {
        for (final entry in md.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is int && value is Uint8List) {
            manufacturerData[key] = value.toList(growable: false);
          } else if (key is int && value is List) {
            manufacturerData[key] =
                value.whereType<int>().toList(growable: false);
          }
        }
      }

      if (address.isEmpty || manufacturerData.isEmpty) continue;

      _scanner.ingestAdvertisement(
        deviceId: address,
        rssi: rssi,
        manufacturerData: manufacturerData,
        serviceUuids: serviceUuids,
        deviceName: deviceName,
        observedAt: DateTime.now(),
      );
    }
  }

  /// Starts interval-based scanning for battery optimization.
  void _startIntervalScanning(BleRangeMode rangeMode) {
    _scanIntervalTimer?.cancel();
    _scanIntervalTimer = Timer.periodic(
      const Duration(seconds: BleConstants.scanIntervalSeconds),
      (_) async {
        if (_state == BluetoothServiceState.active) {
          await _scanner.startScan(
            duration: const Duration(
                seconds: BleConstants.intervalScanDurationSeconds),
            androidScanMode: AndroidScanMode.lowPower,
            minRssiThreshold: rangeMode.minRssiThreshold,
          );
        }
      },
    );
  }

  // ============== Advertising ==============

  /// Starts advertising presence to nearby devices.
  Future<bool> startAdvertising({
    BleRangeMode rangeMode = BleRangeMode.large,
  }) async {
    if (_state != BluetoothServiceState.ready &&
        _state != BluetoothServiceState.active) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    // Advertising on Android 12+ requires a separate runtime permission.
    var permissionStatus = await _permissionHandler.checkAndRequestPermissions(
      needsScan: false,
      needsConnect: true,
      needsAdvertise: true,
    );

    DeviceLog.instance.info('ble', 'startAdvertising permission result', data: {
      'status': permissionStatus.name,
    });

    if (permissionStatus == BlePermissionStatus.bluetoothOff) {
      _setError(_permissionHandler.getPermissionMessage(permissionStatus));
      _setState(BluetoothServiceState.bluetoothOff);

      final turnedOn = await _permissionHandler.requestBluetoothOn();
      DeviceLog.instance.info(
          'ble', 'requestBluetoothOn() from startAdvertising',
          data: {'turnedOn': turnedOn});
      if (!turnedOn) return false;

      await Future.delayed(const Duration(milliseconds: 500));
      permissionStatus = await _permissionHandler.checkAndRequestPermissions(
        needsScan: false,
        needsConnect: true,
        needsAdvertise: true,
      );
    }

    if (permissionStatus != BlePermissionStatus.granted) {
      _advertiseStartFailures++;
      _recordPermissionDenied('startAdvertising', permissionStatus);
      _setError(_permissionHandler.getPermissionMessage(permissionStatus));
      // Advertising permission denial should not block scan-only usage.
      // Keep the service ready so user-triggered scanning can still work.
      _setState(BluetoothServiceState.ready);
      DeviceLog.instance.warning('ble', 'startAdvertising permission denied',
          data: {'status': permissionStatus.name, 'message': _lastError});
      return false;
    }

    try {
      final started = await _advertiser.startAdvertising(rangeMode: rangeMode);
      if (started) {
        _lastAdvertiseStartedAt = DateTime.now();
        _setState(BluetoothServiceState.active);
        DeviceLog.instance.info('ble', 'startAdvertising() OK');
      } else {
        _advertiseStartFailures++;
        _setError(_advertiser.lastError ?? 'Failed to start advertising');
        DeviceLog.instance.warning('ble', 'startAdvertising() returned false',
            data: {'lastError': _advertiser.lastError});
      }
      return started;
    } catch (e) {
      _advertiseStartFailures++;
      _setError('Failed to start advertising: $e');
      DeviceLog.instance.error('ble', 'startAdvertising() failed',
          error: e, stackTrace: StackTrace.current);

      // Helpful but safe: no identifiers.
      logDebug('startAdvertising failed', {
        'error': e.toString(),
        'lastError': _lastError,
      });
      return false;
    }
  }

  /// Stops advertising presence.
  Future<void> stopAdvertising() async {
    await _advertiser.stopAdvertising();

    _lastAdvertiseStoppedAt = DateTime.now();

    DeviceLog.instance.info('ble', 'stopAdvertising()', data: {
      'isScanning': _scanner.isScanning,
    });

    if (!_scanner.isScanning) {
      _setState(BluetoothServiceState.ready);
    }
  }

  // ============== Combined Operations ==============

  /// Starts both scanning and advertising.
  Future<bool> startDiscovery({
    BleRangeMode rangeMode = BleRangeMode.large,
    bool continuousScan = false,
  }) async {
    final scanResult = await startScanning(
      rangeMode: rangeMode,
      continuous: continuousScan,
    );
    if (!scanResult) {
      _setError(_lastError ?? 'Failed to start scanning');
      return false;
    }

    final advertiseResult = await startAdvertising(rangeMode: rangeMode);
    if (!advertiseResult) {
      final message = _lastError ?? 'Failed to start advertising';

      // Some devices support BLE scanning but not peripheral advertising.
      // In that case, keep scanning active so the user can still *find others*.
      if (_isNonFatalAdvertisingError(message)) {
        // startAdvertising() may have set permissionDenied even though scanning is active.
        // Ensure our service state reflects the actual active operation.
        if (_scanner.isScanning) {
          _setState(BluetoothServiceState.active);
        } else {
          _setState(BluetoothServiceState.ready);
        }
        _setError('Advertising disabled: $message');
        return true;
      }

      _setError(message);
      return false;
    }

    return true;
  }

  bool _isNonFatalAdvertisingError(String message) {
    final m = message.toLowerCase();
    return m.contains('advertising not supported') ||
        m.contains('feature unsupported') ||
        m.contains('ble_unavailable') ||
        m.contains('ble unavailable') ||
        // Common case: user grants scan, denies advertise.
        m.contains('permission');
  }

  /// Stops both scanning and advertising.
  Future<void> stopDiscovery() async {
    await stopScanning();
    await stopAdvertising();
  }

  /// Forces rotation of the anonymous ID.
  void rotateAnonymousId() {
    _idGenerator.forceRotation();
  }

  // ============== Device Access ==============

  /// Gets devices filtered by proximity.
  List<BleDevice> getDevicesByProximity(BleProximity proximity) {
    return _scanner.getDevicesByProximity(proximity);
  }

  /// Gets the nearest device.
  BleDevice? getNearestDevice() {
    final devices = discoveredDevices;
    if (devices.isEmpty) return null;
    return devices.reduce((a, b) => a.rssi > b.rssi ? a : b);
  }

  /// Clears all discovered devices.
  void clearDiscoveredDevices() {
    _scanner.clearDevices();
  }

  // ============== State Management ==============

  void _setState(BluetoothServiceState newState) {
    if (_state != newState) {
      final from = _state;
      _state = newState;
      _stateController.add(newState);

      DeviceLog.instance.info('ble', 'state', data: {
        'from': from.name,
        'to': newState.name,
      });
    }
  }

  void _setError(String error) {
    _lastError = error;
    _errorController.add(error);
    DeviceLog.instance.warning('ble', 'error', data: {'message': error});
  }

  void _handleAdapterStateChange(BluetoothAdapterState adapterState) {
    DeviceLog.instance
        .info('ble', 'adapterState', data: {'state': adapterState.name});
    if (adapterState == BluetoothAdapterState.on) {
      if (_state == BluetoothServiceState.bluetoothOff) {
        _setState(BluetoothServiceState.ready);
      }
    } else if (adapterState == BluetoothAdapterState.off) {
      _scanner.stopScan();
      _advertiser.stopAdvertising();
      _setState(BluetoothServiceState.bluetoothOff);
    }
  }

  // ============== Permissions ==============

  /// Re-checks permissions (useful after returning from settings).
  Future<BlePermissionStatus> recheckPermissions() async {
    final status = await _permissionHandler.checkAndRequestPermissions(
      needsScan: true,
      needsConnect: true,
      needsAdvertise: false,
    );

    if (status == BlePermissionStatus.granted &&
        _state == BluetoothServiceState.permissionDenied) {
      _setState(BluetoothServiceState.ready);
    }

    return status;
  }

  /// Resets the service state to allow reinitialization.
  /// Use this when retrying after an error.
  void reset() {
    _scanIntervalTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
    _scanner.stopScan();
    _advertiser.stopAdvertising();
    _state = BluetoothServiceState.uninitialized;
    _lastError = null;
  }

  /// Checks if Bluetooth is currently enabled.
  Future<bool> isBluetoothEnabled() async {
    return await _permissionHandler.isBluetoothOn();
  }

  /// Opens app settings for permission management.
  Future<bool> openSettings() async {
    return await _permissionHandler.openSettings();
  }

  /// Requests to turn on Bluetooth.
  Future<void> requestBluetoothOn() async {
    await _permissionHandler.requestBluetoothOn();
  }

  // ============== Cleanup ==============

  /// Disposes all resources.
  void dispose() {
    _scanIntervalTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _scanner.dispose();
    _advertiser.dispose();
    _idGenerator.dispose();
    _stateController.close();
    _errorController.close();
  }
}
