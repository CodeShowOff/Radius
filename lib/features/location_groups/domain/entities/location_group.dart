import 'package:equatable/equatable.dart';

/// Visibility types for location groups.
enum GroupVisibility {
  /// Anyone can join without approval
  public,

  /// Admin must approve join requests
  requestToJoin,
}

/// Status of a location group.
enum GroupStatus {
  /// Group is active and discoverable
  active,

  /// Group is archived and not discoverable
  archived,
}

/// Entity representing a location-scoped group.
///
/// Groups are anchored to a specific Country + City combination
/// and are discoverable through location-based browsing.
class LocationGroup extends Equatable {
  /// Unique identifier for the group
  final String id;

  /// Display name of the group
  final String name;

  /// Optional description
  final String? description;

  /// Country display name (also used as query key)
  final String countryName;

  /// City display name (also used as query key)
  final String cityName;

  /// User ID of the group creator
  final String createdByUserId;

  /// Creator's display name (denormalized)
  final String? createdByUserName;

  /// Group visibility setting
  final GroupVisibility visibility;

  /// Group status
  final GroupStatus status;

  /// Number of members in the group
  final int memberCount;

  /// When the group was created
  final DateTime createdAt;

  /// When the group was last active (last message)
  final DateTime? lastActivityAt;

  /// Preview of last message in group chat
  final String? lastMessagePreview;

  /// Group avatar/icon URL (optional)
  final String? avatarUrl;

  const LocationGroup({
    required this.id,
    required this.name,
    this.description,
    required this.countryName,
    required this.cityName,
    required this.createdByUserId,
    this.createdByUserName,
    required this.visibility,
    required this.status,
    required this.memberCount,
    required this.createdAt,
    this.lastActivityAt,
    this.lastMessagePreview,
    this.avatarUrl,
  });

  /// Helper to check if group is public
  bool get isPublic => visibility == GroupVisibility.public;

  /// Helper to check if group requires approval
  bool get requiresApproval => visibility == GroupVisibility.requestToJoin;

  /// Helper to check if group is active
  bool get isActive => status == GroupStatus.active;

  /// Generate a search-friendly location string
  String get locationString => '$cityName, $countryName';

  /// Check if recently created (within last 7 days)
  bool get isNew {
    final now = DateTime.now();
    return now.difference(createdAt).inDays < 7;
  }

  LocationGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? countryName,
    String? cityName,
    String? createdByUserId,
    String? createdByUserName,
    GroupVisibility? visibility,
    GroupStatus? status,
    int? memberCount,
    DateTime? createdAt,
    DateTime? lastActivityAt,
    String? lastMessagePreview,
    String? avatarUrl,
  }) {
    return LocationGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      countryName: countryName ?? this.countryName,
      cityName: cityName ?? this.cityName,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByUserName: createdByUserName ?? this.createdByUserName,
      visibility: visibility ?? this.visibility,
      status: status ?? this.status,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        countryName,
        cityName,
        createdByUserId,
        createdByUserName,
        visibility,
        status,
        memberCount,
        createdAt,
        lastActivityAt,
        lastMessagePreview,
        avatarUrl,
      ];
}
