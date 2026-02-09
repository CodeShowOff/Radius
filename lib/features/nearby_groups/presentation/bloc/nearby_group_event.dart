part of 'nearby_group_bloc.dart';

/// Events for NearbyGroupBloc.
sealed class NearbyGroupEvent extends Equatable {
  const NearbyGroupEvent();

  @override
  List<Object?> get props => [];
}

/// Start watching all active nearby groups for discovery.
class WatchActiveNearbyGroups extends NearbyGroupEvent {
  const WatchActiveNearbyGroups();
}

/// Start watching groups the user is a member of.
class WatchUserNearbyGroups extends NearbyGroupEvent {
  final String userId;

  const WatchUserNearbyGroups(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Create a new nearby group.
class CreateNearbyGroup extends NearbyGroupEvent {
  final String name;
  final String? description;
  final String creatorId;
  final String creatorUsername;
  final String? creatorDisplayName;
  final String? creatorPhotoUrl;

  const CreateNearbyGroup({
    required this.name,
    this.description,
    required this.creatorId,
    required this.creatorUsername,
    this.creatorDisplayName,
    this.creatorPhotoUrl,
  });

  @override
  List<Object?> get props => [
        name,
        description,
        creatorId,
        creatorUsername,
        creatorDisplayName,
        creatorPhotoUrl,
      ];
}

/// Close (deactivate) a nearby group.
class CloseNearbyGroup extends NearbyGroupEvent {
  final String groupId;
  final String userId;

  const CloseNearbyGroup({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

/// Start Bluetooth scanning and member updates for a group.
/// Only the creator should call this.
class StartGroupScanning extends NearbyGroupEvent {
  final String groupId;
  final String creatorId;
  final String creatorUsername;

  const StartGroupScanning({
    required this.groupId,
    required this.creatorId,
    required this.creatorUsername,
  });

  @override
  List<Object?> get props => [groupId, creatorId, creatorUsername];
}

/// Stop Bluetooth scanning for a group.
class StopGroupScanning extends NearbyGroupEvent {
  const StopGroupScanning();
}

/// Load details for a specific group.
class LoadNearbyGroupDetails extends NearbyGroupEvent {
  final String groupId;

  const LoadNearbyGroupDetails(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

/// Load user's own active group (if any).
/// Used to restore state after app restart.
class LoadUserActiveGroup extends NearbyGroupEvent {
  final String userId;

  const LoadUserActiveGroup(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Internal event: active groups received from stream.
class _ActiveGroupsReceived extends NearbyGroupEvent {
  final List<NearbyGroup> groups;

  const _ActiveGroupsReceived(this.groups);

  @override
  List<Object?> get props => [groups];
}

/// Internal event: user's groups received from stream.
class _UserGroupsReceived extends NearbyGroupEvent {
  final List<NearbyGroup> groups;

  const _UserGroupsReceived(this.groups);

  @override
  List<Object?> get props => [groups];
}

/// Internal event: group members received from stream.
class _GroupMembersReceived extends NearbyGroupEvent {
  final List<NearbyGroupMember> members;

  const _GroupMembersReceived(this.members);

  @override
  List<Object?> get props => [members];
}

/// Internal event: nearby users detected during scanning.
class _NearbyUsersDetected extends NearbyGroupEvent {
  final List<NearbyUser> users;

  const _NearbyUsersDetected(this.users);

  @override
  List<Object?> get props => [users];
}

/// Internal event: stream error.
class _NearbyGroupStreamError extends NearbyGroupEvent {
  final String error;

  const _NearbyGroupStreamError(this.error);

  @override
  List<Object?> get props => [error];
}

/// Internal event: scan cycle (10s) completed.
class _ScanCycleComplete extends NearbyGroupEvent {
  const _ScanCycleComplete();
}

/// Reset the BLoC state and cancel all subscriptions.
/// This should be called when switching accounts to prevent stale data.
class ResetNearbyGroupState extends NearbyGroupEvent {
  const ResetNearbyGroupState();
}
