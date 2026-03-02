/// Represents the lifecycle status of a video call.
enum CallStatus {
  /// Call has been created and is ringing on the receiver's end.
  ringing,

  /// Call was answered and a WebRTC connection is being established.
  connecting,

  /// Both peers are connected and media is flowing.
  connected,

  /// The call was ended normally by either party.
  ended,

  /// The receiver declined the call.
  declined,

  /// The call was not picked up within the timeout period.
  missed,
}

/// Extension to convert between Firestore string values and [CallStatus].
extension CallStatusX on CallStatus {
  String toFirestore() => name;

  static CallStatus fromFirestore(String value) {
    return CallStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CallStatus.ended,
    );
  }
}
