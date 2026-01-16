import 'package:equatable/equatable.dart';

import 'connection.dart';

/// Entity representing a connected user with their profile information.
///
/// This combines connection data with user profile data for display purposes.
class ConnectedUser extends Equatable {
  /// The user's ID.
  final String id;

  /// The user's display name.
  final String displayName;

  /// The user's avatar URL.
  final String? avatarUrl;

  /// The user's bio/status.
  final String? bio;

  /// Whether the user is currently online.
  final bool isOnline;

  /// When the user was last seen.
  final DateTime? lastSeen;

  /// The connection entity.
  final Connection connection;

  /// When the connection was established.
  DateTime get connectedAt => connection.connectedAt;

  const ConnectedUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.isOnline = false,
    this.lastSeen,
    required this.connection,
  });

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  ConnectedUser copyWith({
    String? id,
    String? displayName,
    Object? avatarUrl = _sentinel,
    Object? bio = _sentinel,
    bool? isOnline,
    Object? lastSeen = _sentinel,
    Connection? connection,
  }) {
    return ConnectedUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl == _sentinel ? this.avatarUrl : avatarUrl as String?,
      bio: bio == _sentinel ? this.bio : bio as String?,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen == _sentinel ? this.lastSeen : lastSeen as DateTime?,
      connection: connection ?? this.connection,
    );
  }

  @override
  List<Object?> get props => [
        id,
        displayName,
        avatarUrl,
        bio,
        isOnline,
        lastSeen,
        connection,
      ];
}
