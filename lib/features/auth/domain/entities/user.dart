import 'package:equatable/equatable.dart';

/// User entity representing an authenticated user.
///
/// This is a domain entity - pure Dart with no framework dependencies.
class User extends Equatable {
  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String bleIdentifier;
  final DateTime createdAt;
  final bool isDiscoverable;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    required this.bleIdentifier,
    required this.createdAt,
    this.isDiscoverable = true,
  });

  /// Creates a copy of this user with the given fields replaced.
  ///
  /// To explicitly set [displayName] or [avatarUrl] to null, use the
  /// [clearDisplayName] or [clearAvatarUrl] parameters.
  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? bleIdentifier,
    DateTime? createdAt,
    bool? isDiscoverable,
    bool clearDisplayName = false,
    bool clearAvatarUrl = false,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      bleIdentifier: bleIdentifier ?? this.bleIdentifier,
      createdAt: createdAt ?? this.createdAt,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
    );
  }

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        avatarUrl,
        bleIdentifier,
        createdAt,
        isDiscoverable,
      ];
}
