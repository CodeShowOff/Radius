part of 'location_group_bloc.dart';

/// Events for the LocationGroupBloc.
abstract class LocationGroupEvent extends Equatable {
  const LocationGroupEvent();

  @override
  List<Object?> get props => [];
}

/// Load groups for a specific location.
class LoadGroupsForLocation extends LocationGroupEvent {
  final String countryCode;
  final String stateCode;
  final GroupSortOption sortBy;

  const LoadGroupsForLocation({
    required this.countryCode,
    required this.stateCode,
    this.sortBy = GroupSortOption.mostActive,
  });

  @override
  List<Object?> get props => [countryCode, stateCode, sortBy];
}

/// Load user's joined groups.
class LoadUserGroups extends LocationGroupEvent {
  final String userId;

  const LoadUserGroups({required this.userId});

  @override
  List<Object?> get props => [userId];
}

/// Create a new group.
class CreateGroup extends LocationGroupEvent {
  final String name;
  final String? description;
  final String countryCode;
  final String stateCode;
  final String countryName;
  final String stateName;
  final String creatorUserId;
  final String? creatorUserName;
  final String? creatorUserPhotoUrl;
  final GroupVisibility visibility;

  const CreateGroup({
    required this.name,
    this.description,
    required this.countryCode,
    required this.stateCode,
    required this.countryName,
    required this.stateName,
    required this.creatorUserId,
    this.creatorUserName,
    this.creatorUserPhotoUrl,
    required this.visibility,
  });

  @override
  List<Object?> get props => [
        name,
        description,
        countryCode,
        stateCode,
        countryName,
        stateName,
        creatorUserId,
        creatorUserName,
        visibility,
      ];
}

/// Join a public group.
class JoinPublicGroup extends LocationGroupEvent {
  final String groupId;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;

  const JoinPublicGroup({
    required this.groupId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
  });

  @override
  List<Object?> get props => [groupId, userId, userName];
}

/// Request to join a request-to-join group.
class RequestToJoinGroup extends LocationGroupEvent {
  final String groupId;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;
  final String? message;

  const RequestToJoinGroup({
    required this.groupId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    this.message,
  });

  @override
  List<Object?> get props => [groupId, userId, userName, message];
}

/// Leave a group.
class LeaveGroup extends LocationGroupEvent {
  final String groupId;
  final String userId;

  const LeaveGroup({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

/// Load a single group's details.
class LoadGroupDetails extends LocationGroupEvent {
  final String groupId;
  final String? currentUserId;

  const LoadGroupDetails({
    required this.groupId,
    this.currentUserId,
  });

  @override
  List<Object?> get props => [groupId, currentUserId];
}

/// Load pending join requests for a group (admin).
class LoadJoinRequests extends LocationGroupEvent {
  final String groupId;

  const LoadJoinRequests({required this.groupId});

  @override
  List<Object?> get props => [groupId];
}

/// Approve a join request (admin).
class ApproveJoinRequest extends LocationGroupEvent {
  final String groupId;
  final String requestUserId;
  final String adminUserId;

  const ApproveJoinRequest({
    required this.groupId,
    required this.requestUserId,
    required this.adminUserId,
  });

  @override
  List<Object?> get props => [groupId, requestUserId, adminUserId];
}

/// Reject a join request (admin).
class RejectJoinRequest extends LocationGroupEvent {
  final String groupId;
  final String requestUserId;
  final String adminUserId;

  const RejectJoinRequest({
    required this.groupId,
    required this.requestUserId,
    required this.adminUserId,
  });

  @override
  List<Object?> get props => [groupId, requestUserId, adminUserId];
}

/// Remove a member from group (admin).
class RemoveMember extends LocationGroupEvent {
  final String groupId;
  final String targetUserId;
  final String adminUserId;
  final bool ban;

  const RemoveMember({
    required this.groupId,
    required this.targetUserId,
    required this.adminUserId,
    this.ban = false,
  });

  @override
  List<Object?> get props => [groupId, targetUserId, adminUserId, ban];
}

/// Promote a member to admin.
class PromoteToAdmin extends LocationGroupEvent {
  final String groupId;
  final String targetUserId;
  final String adminUserId;

  const PromoteToAdmin({
    required this.groupId,
    required this.targetUserId,
    required this.adminUserId,
  });

  @override
  List<Object?> get props => [groupId, targetUserId, adminUserId];
}

/// Update group settings (admin).
class UpdateGroupSettings extends LocationGroupEvent {
  final String groupId;
  final String adminUserId;
  final String? name;
  final String? description;
  final GroupVisibility? visibility;

  const UpdateGroupSettings({
    required this.groupId,
    required this.adminUserId,
    this.name,
    this.description,
    this.visibility,
  });

  @override
  List<Object?> get props => [groupId, adminUserId, name, description, visibility];
}

/// Clear any error state.
class ClearGroupError extends LocationGroupEvent {
  const ClearGroupError();
}

/// Reset the bloc state.
class ResetGroupState extends LocationGroupEvent {
  const ResetGroupState();
}

/// Change sort option for group list.
class ChangeSortOption extends LocationGroupEvent {
  final GroupSortOption sortBy;

  const ChangeSortOption({required this.sortBy});

  @override
  List<Object?> get props => [sortBy];
}
