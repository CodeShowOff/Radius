import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'ble_constants.dart';

/// Generates and manages rotating anonymous BLE IDs for privacy.
class BleIdGenerator {
  final Uuid _uuid = const Uuid();
  final Random _random = Random.secure();

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
    // Generate a UUID v4
    final uuid = _uuid.v4();

    // Add some random bytes for additional entropy
    final randomBytes = List<int>.generate(4, (_) => _random.nextInt(256));
    final randomHex =
        randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Combine and truncate to create a compact ID
    // Format: first 8 chars of UUID + 8 random hex chars = 16 chars
    return '${uuid.substring(0, 8)}$randomHex'.toUpperCase();
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
    return Uint8List.fromList(utf8.encode(_currentAnonymousId));
  }

  /// Creates manufacturer data for BLE advertising.
  /// Note: For Android native advertising, we only return the anonymous ID bytes.
  /// The company ID is set separately in the native code via addManufacturerData().
  Uint8List createManufacturerData() {
    // Just return the anonymous ID bytes - the company ID is handled by native code
    return currentIdAsBytes;
  }

  /// Parses an anonymous ID from manufacturer data value.
  /// Note: In flutter_blue_plus, the manufacturerData map key is the company ID,
  /// so the value (data parameter) contains ONLY the anonymous ID bytes.
  /// Returns null if data is invalid or malformed.
  static String? parseAnonymousIdFromManufacturerData(Uint8List data) {
    // The data should contain just the anonymous ID (no company ID prefix)
    // Our IDs are 16 characters (8 UUID + 8 random hex)
    if (data.isEmpty || data.length < 8) return null;

    // Validate length
    if (data.length > BleConstants.maxAnonymousIdLength) {
      return null;
    }

    try {
      final decoded = utf8.decode(data);

      // Validate the ID format: should be uppercase alphanumeric
      if (!RegExp(r'^[A-F0-9]{8,20}$').hasMatch(decoded)) {
        return null;
      }

      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Disposes resources.
  void dispose() {
    _rotationTimer?.cancel();
    _idRotationController.close();
  }
}
