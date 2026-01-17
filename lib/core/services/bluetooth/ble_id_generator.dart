import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'ble_constants.dart';

/// Generates and manages rotating anonymous BLE IDs for privacy.
class BleIdGenerator {
  static const List<int> _radiusMagic = <int>[0x52, 0x44, 0x01];

  final Uuid _uuid = const Uuid();

  String _currentAnonymousId = '';
  DateTime _lastRotation = DateTime.now();
  Timer? _rotationTimer;

  /// Stream controller for ID rotation events.
  final _idRotationController = StreamController<String>.broadcast();

  /// Stream of anonymous ID changes.
  Stream<String> get idRotationStream => _idRotationController.stream;

  /// The current anonymous ID being broadcast.
  String get currentAnonymousId => _currentAnonymousId;

  /// Initializes the ID generator and starts rotation.
  void initialize() {
    _rotateId();
    _startRotationTimer();
  }

  /// Generates a new anonymous ID.
  /// The ID is a truncated UUID combined with random bytes for uniqueness.
  String _generateAnonymousId() {
    // Generate a UUID v4 and strip dashes.
    // This yields exactly 32 hex characters (16 bytes when packed) which is:
    // - stable length
    // - safe for manufacturer data transport
    // - easy to represent as uppercase hex in-app
    final uuid = _uuid.v4().replaceAll('-', '');
    return uuid.toUpperCase();
  }

  /// Rotates to a new anonymous ID.
  void _rotateId() {
    _currentAnonymousId = _generateAnonymousId();
    _lastRotation = DateTime.now();
    _idRotationController.add(_currentAnonymousId);
  }

  /// Starts the automatic rotation timer.
  void _startRotationTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(
      const Duration(minutes: BleConstants.idRotationMinutes),
      (_) => _rotateId(),
    );
  }

  /// Forces an immediate ID rotation.
  void forceRotation() {
    _rotateId();
  }

  /// Gets time until next rotation.
  Duration get timeUntilNextRotation {
    final elapsed = DateTime.now().difference(_lastRotation);
    const rotationDuration = Duration(minutes: BleConstants.idRotationMinutes);
    final remaining = rotationDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Converts the current ID to bytes for BLE advertising.
  Uint8List get currentIdAsBytes {
    // Kept for backward compatibility only; the active advertising format uses
    // packed bytes (see [currentIdAsPackedBytes]).
    return Uint8List.fromList(utf8.encode(_currentAnonymousId));
  }

  /// Converts the current anonymous ID (hex string) into compact bytes.
  ///
  /// Our anonymous IDs are uppercase hex; packing them prevents advertising
  /// payload overflow (Android legacy ADV payload is limited to 31 bytes).
  Uint8List get currentIdAsPackedBytes {
    return _hexToBytes(_currentAnonymousId);
  }

  /// Creates manufacturer data for BLE advertising.
  /// Note: For Android native advertising, we only return the anonymous ID bytes.
  /// The company ID is set separately in the native code via addManufacturerData().
  Uint8List createManufacturerData() {
    // Return compact bytes; the company ID is handled by native code.
    return currentIdAsPackedBytes;
  }

  /// Parses an anonymous ID from manufacturer data value.
  /// Note: In flutter_blue_plus, the manufacturerData map key is the company ID,
  /// so the value (data parameter) contains ONLY the anonymous ID bytes.
  /// Returns null if data is invalid or malformed.
  static String? parseAnonymousIdFromManufacturerData(Uint8List data) {
    if (data.isEmpty) return null;

    // 1) Back-compat: some builds advertised ASCII hex directly.
    if (data.length <= BleConstants.maxAnonymousIdLength) {
      try {
        final decoded = utf8.decode(data);
        final upper = decoded.toUpperCase();
        if (RegExp(r'^[A-F0-9]{8,40}$').hasMatch(upper)) {
          return upper;
        }
      } catch (_) {
        // Fall through to packed-bytes decoding.
      }
    }

    // New format: magic header + packed anonymous id bytes.
    //
    // On Android scan records, manufacturerData[companyId] usually returns only
    // the manufacturer-specific bytes (company ID already stripped).
    // On iOS/CoreBluetooth, some stacks expose manufacturer data including the
    // 2-byte company ID prefix. We only strip that prefix when it's followed by
    // the Radius magic header to avoid corrupting random payloads.
    // IMPORTANT: require the Radius magic header for packed payloads.
    // Without a signature we would accidentally treat unrelated devices as Radius.
    if (!_hasRadiusMagic(data)) return null;

    final Uint8List normalized =
        _stripRadiusMagicIfPresent(_stripCompanyIdPrefixIfPresent(data));

    // 2) Preferred: packed bytes -> hex string.
    // e.g. 8 bytes -> 16 hex chars.
    final hex = _bytesToHex(normalized);
    if (!RegExp(r'^[A-F0-9]{8,40}$').hasMatch(hex)) return null;

    // Keep within our max ID size.
    if (hex.length > BleConstants.maxAnonymousIdLength) {
      return null;
    }
    return hex;
  }

  static bool _hasRadiusMagic(Uint8List data) {
    // Either:
    // - starts with magic directly (common on Android scan manufacturerData value)
    // - starts with 2-byte companyId prefix then magic (some iOS/CoreBluetooth exposures)
    if (_startsWithRadiusMagic(data, startIndex: 0)) return true;
    return _startsWithRadiusMagic(data, startIndex: 2);
  }

  static bool _startsWithRadiusMagic(Uint8List data,
      {required int startIndex}) {
    if (data.length < startIndex + _radiusMagic.length) return false;
    for (int i = 0; i < _radiusMagic.length; i++) {
      if (data[startIndex + i] != _radiusMagic[i]) return false;
    }
    return true;
  }

  static Uint8List _stripRadiusMagicIfPresent(Uint8List data) {
    if (data.length < _radiusMagic.length) return data;
    for (int i = 0; i < _radiusMagic.length; i++) {
      if (data[i] != _radiusMagic[i]) return data;
    }
    return Uint8List.fromList(data.sublist(_radiusMagic.length));
  }

  static Uint8List _stripCompanyIdPrefixIfPresent(Uint8List data) {
    // Strip any 2-byte companyId prefix if immediately followed by the Radius magic header.
    // This keeps parsing stable when the app switches from the testing ID (0xFFFF)
    // to a real Bluetooth SIG company identifier.
    if (data.length < 2 + _radiusMagic.length) return data;

    for (int i = 0; i < _radiusMagic.length; i++) {
      if (data[2 + i] != _radiusMagic[i]) return data;
    }

    return Uint8List.fromList(data.sublist(2));
  }

  static Uint8List _hexToBytes(String hex) {
    final normalized = hex.trim();
    if (normalized.length.isOdd) {
      throw const FormatException('Hex string must have even length');
    }
    final out = Uint8List(normalized.length ~/ 2);
    for (var i = 0; i < normalized.length; i += 2) {
      out[i ~/ 2] = int.parse(normalized.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().toUpperCase();
  }

  /// Disposes resources.
  void dispose() {
    _rotationTimer?.cancel();
    _idRotationController.close();
  }
}
