import 'package:equatable/equatable.dart';

/// Represents an approved member of a random group.
class RandomGroupMember extends Equatable {
  /// User ID
  final String id;

  /// Username
  final String username;

  /// Display name
  final String? displayName;

  /// Profile photo URL
  final String? photoUrl;

  /// When the user joined the group (was approved)
  final DateTime joinedAt;

  /// Whether the user is an admin
  final bool isAdmin;

  const RandomGroupMember({
    required this.id,
    required this.username,
    this.displayName,
    this.photoUrl,
    required this.joinedAt,
    this.isAdmin = false,
  });

  /// Creates a copy with updated fields
  RandomGroupMember copyWith({
    String? id,
    String? username,
    String? displayName,
    String? photoUrl,
    DateTime? joinedAt,
    bool? isAdmin,
  }) {
    return RandomGroupMember(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      joinedAt: joinedAt ?? this.joinedAt,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  @override
  List<Object?> get props => [
        id,
        username,
        displayName,
        photoUrl,
        joinedAt,
        isAdmin,
      ];
}
