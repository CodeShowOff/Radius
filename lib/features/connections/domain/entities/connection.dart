import 'package:equatable/equatable.dart';

/// Status of a connection between two users.
enum ConnectionStatus {
  /// Connection is active and mutual.
  connected,

  /// Connection was blocked by one party.
  blocked,

  /// Connection was removed/unfriended.
  disconnected,
}

/// Entity representing a mutual connection between two users.
/// 
/// A connection is only created after both users consent.
/// The connection document is stored with a canonical ID (sorted user IDs)
/// to ensure only one connection document exists between two users.
class Connection extends Equatable {
  /// Unique connection ID (canonical format: `{userId1}_{userId2}` where userId1 < userId2).
  final String id;

  /// First user ID (alphabetically smaller).
  final String userId1;

  /// Second user ID (alphabetically larger).
  final String userId2;

  /// Current status of the connection.
  final ConnectionStatus status;

  /// When the connection was established.
  final DateTime connectedAt;

  /// When the connection was last updated.
  final DateTime updatedAt;

  /// User ID who initiated the original request.
  final String initiatedBy;

  /// Optional: User ID who blocked (if status is blocked).
  final String? blockedBy;

  /// Whether this connection allows messaging.
  final bool canMessage;

  /// Whether this connection allows location sharing.
  final bool shareLocation;

  const Connection({
    required this.id,
    required this.userId1,
    required this.userId2,
    required this.status,
    required this.connectedAt,
    required this.updatedAt,
    required this.initiatedBy,
    this.blockedBy,
    this.canMessage = true,
    this.shareLocation = false,
  });

  /// Gets the other user's ID given the current user's ID.
  String getOtherUserId(String currentUserId) {
    return currentUserId == userId1 ? userId2 : userId1;
  }

  /// Creates canonical connection ID from two user IDs.
  /// Always sorts IDs to ensure consistency.
  static String createConnectionId(String userA, String userB) {
    final sorted = [userA, userB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Checks if a user is part of this connection.
  bool hasUser(String userId) => userId1 == userId || userId2 == userId;

  Connection copyWith({
    String? id,
    String? userId1,
    String? userId2,
    ConnectionStatus? status,
    DateTime? connectedAt,
    DateTime? updatedAt,
    String? initiatedBy,
    String? blockedBy,
    bool? canMessage,
    bool? shareLocation,
  }) {
    return Connection(
      id: id ?? this.id,
      userId1: userId1 ?? this.userId1,
      userId2: userId2 ?? this.userId2,
      status: status ?? this.status,
      connectedAt: connectedAt ?? this.connectedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      initiatedBy: initiatedBy ?? this.initiatedBy,
      blockedBy: blockedBy ?? this.blockedBy,
      canMessage: canMessage ?? this.canMessage,
      shareLocation: shareLocation ?? this.shareLocation,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId1,
        userId2,
        status,
        connectedAt,
        updatedAt,
        initiatedBy,
        blockedBy,
        canMessage,
        shareLocation,
      ];
}
