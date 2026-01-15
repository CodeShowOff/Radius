import 'package:equatable/equatable.dart';

/// Entity representing a proximity detection event.
class ProximityEvent extends Equatable {
  final String id;
  final String observerUserId;
  final String detectedUserId;
  final double distance;
  final int rssi;
  final DateTime timestamp;
  final Duration? duration;

  const ProximityEvent({
    required this.id,
    required this.observerUserId,
    required this.detectedUserId,
    required this.distance,
    required this.rssi,
    required this.timestamp,
    this.duration,
  });

  @override
  List<Object?> get props => [
        id,
        observerUserId,
        detectedUserId,
        distance,
        rssi,
        timestamp,
        duration,
      ];
}
