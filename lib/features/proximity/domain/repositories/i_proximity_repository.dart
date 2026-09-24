import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/nearby_user.dart';

/// Repository interface for proximity/BLE operations.
abstract class IProximityRepository {
  /// Stream of nearby users detected via BLE scanning.
  Stream<List<NearbyUser>> get nearbyUsersStream;
  
  /// Current Bluetooth state.
  Stream<BluetoothState> get bluetoothStateStream;
  
  /// Start scanning for nearby devices.
  Future<Either<Failure, void>> startScanning();
  
  /// Stop scanning for nearby devices.
  Future<Either<Failure, void>> stopScanning();
  
  /// Start advertising this device to be discoverable.
  Future<Either<Failure, void>> startAdvertising();
  
  /// Stop advertising.
  Future<Either<Failure, void>> stopAdvertising();
  
  /// Request Bluetooth permissions.
  Future<Either<Failure, bool>> requestPermissions();
  
  /// Check if Bluetooth is available and enabled.
  Future<Either<Failure, bool>> isBluetoothAvailable();
}

/// Bluetooth adapter states.
enum BluetoothState {
  unknown,
  unavailable,
  unauthorized,
  turningOn,
  on,
  turningOff,
  off,
}
