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
    final randomHex = randomBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

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
      Duration(minutes: BleConstants.idRotationMinutes),
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
    final rotationDuration = Duration(minutes: BleConstants.idRotationMinutes);
    final remaining = rotationDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Converts the current ID to bytes for BLE advertising.
  Uint8List get currentIdAsBytes {
    return Uint8List.fromList(utf8.encode(_currentAnonymousId));
  }

  /// Creates manufacturer data for BLE advertising.
  /// Format: [Company ID (2 bytes)] + [Anonymous ID bytes]
  Uint8List createManufacturerData() {
    // Using a custom company ID (0xFFFF is reserved for testing)
    // In production, you'd use your registered Bluetooth SIG company ID
    const companyId = 0xFFFF;

    final idBytes = currentIdAsBytes;
    final data = Uint8List(2 + idBytes.length);

    // Company ID (little-endian)
    data[0] = companyId & 0xFF;
    data[1] = (companyId >> 8) & 0xFF;

    // Anonymous ID
    data.setRange(2, 2 + idBytes.length, idBytes);

    return data;
  }

  /// Parses an anonymous ID from manufacturer data.
  static String? parseAnonymousIdFromManufacturerData(Uint8List data) {
    if (data.length < 3) return null;

    // Skip the 2-byte company ID
    final idBytes = data.sublist(2);

    try {
      return utf8.decode(idBytes);
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
