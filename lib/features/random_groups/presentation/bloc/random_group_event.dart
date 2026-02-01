part of 'random_group_bloc.dart';

/// Events for the RandomGroupBloc.
sealed class RandomGroupEvent extends Equatable {
  const RandomGroupEvent();

  @override
  List<Object?> get props => [];
}

/// Watch all active random groups for discovery.
class WatchActiveRandomGroups extends RandomGroupEvent {
  const WatchActiveRandomGroups();
}

/// Watch groups the user is a member of.
class WatchUserRandomGroups extends RandomGroupEvent {
  final String userId;

  const WatchUserRandomGroups(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Watch groups created by the user.
class WatchUserCreatedRandomGroups extends RandomGroupEvent {
  final String userId;

  const WatchUserCreatedRandomGroups(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Create a new random group.
class CreateRandomGroup extends RandomGroupEvent {
  final String name;
  final String? topic;
  final String? description;
  final String creatorId;
  final String creatorUsername;
  final String? creatorDisplayName;
  final String? creatorPhotoUrl;

  const CreateRandomGroup({
    required this.name,
    this.topic,
    this.description,
    required this.creatorId,
    required this.creatorUsername,
    this.creatorDisplayName,
    this.creatorPhotoUrl,
  });

  @override
  List<Object?> get props => [
        name,
        topic,
        description,
        creatorId,
        creatorUsername,
        creatorDisplayName,
        creatorPhotoUrl,
      ];
}

/// Load details for a specific group.
class LoadRandomGroupDetails extends RandomGroupEvent {
  final String groupId;

  const LoadRandomGroupDetails(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

/// Request to join a group.
class RequestToJoinRandomGroup extends RandomGroupEvent {
  final String groupId;
  final String requesterId;
  final String requesterUsername;
  final String? requesterDisplayName;
  final String? requesterPhotoUrl;
  final String? message;

  const RequestToJoinRandomGroup({
    required this.groupId,
    required this.requesterId,
    required this.requesterUsername,
    this.requesterDisplayName,
    this.requesterPhotoUrl,
    this.message,
  });

  @override
  List<Object?> get props => [
        groupId,
        requesterId,
        requesterUsername,
        requesterDisplayName,
        requesterPhotoUrl,
        message,
      ];
}

/// Watch pending join requests for a group (admin only).
class WatchPendingRequests extends RandomGroupEvent {
  final String groupId;

  const WatchPendingRequests(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

/// Approve a join request (admin only).
class ApproveJoinRequest extends RandomGroupEvent {
  final String groupId;
  final String requestId;
  final String adminId;

  const ApproveJoinRequest({
    required this.groupId,
    required this.requestId,
    required this.adminId,
  });

  @override
  List<Object?> get props => [groupId, requestId, adminId];
}

/// Reject a join request (admin only).
class RejectJoinRequest extends RandomGroupEvent {
  final String groupId;
  final String requestId;
  final String adminId;

  const RejectJoinRequest({
    required this.groupId,
    required this.requestId,
    required this.adminId,
  });

  @override
  List<Object?> get props => [groupId, requestId, adminId];
}

/// Remove a member from a group (admin only).
class RemoveRandomGroupMember extends RandomGroupEvent {
  final String groupId;
  final String memberId;
  final String adminId;

  const RemoveRandomGroupMember({
    required this.groupId,
    required this.memberId,
    required this.adminId,
  });

  @override
  List<Object?> get props => [groupId, memberId, adminId];
}

/// Promote a member to admin.
class PromoteToAdmin extends RandomGroupEvent {
  final String groupId;
  final String memberId;
  final String adminId;

  const PromoteToAdmin({
    required this.groupId,
    required this.memberId,
    required this.adminId,
  });

  @override
  List<Object?> get props => [groupId, memberId, adminId];
}

/// Leave a group voluntarily.
class LeaveRandomGroup extends RandomGroupEvent {
  final String groupId;
  final String userId;

  const LeaveRandomGroup({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

/// Delete a group (creator only).
class DeleteRandomGroup extends RandomGroupEvent {
  final String groupId;
  final String userId;

  const DeleteRandomGroup({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

/// Watch members of a group.
class WatchRandomGroupMembers extends RandomGroupEvent {
  final String groupId;

  const WatchRandomGroupMembers(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

/// Check user's membership status for a group.
class CheckMembershipStatus extends RandomGroupEvent {
  final String groupId;
  final String userId;

  const CheckMembershipStatus({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

// Internal events for stream updates
class _ActiveGroupsReceived extends RandomGroupEvent {
  final List<RandomGroup> groups;

  const _ActiveGroupsReceived(this.groups);

  @override
  List<Object?> get props => [groups];
}

class _UserGroupsReceived extends RandomGroupEvent {
  final List<RandomGroup> groups;

  const _UserGroupsReceived(this.groups);

  @override
  List<Object?> get props => [groups];
}

class _UserCreatedGroupsReceived extends RandomGroupEvent {
  final List<RandomGroup> groups;

  const _UserCreatedGroupsReceived(this.groups);

  @override
  List<Object?> get props => [groups];
}

class _GroupDetailsReceived extends RandomGroupEvent {
  final RandomGroup? group;

  const _GroupDetailsReceived(this.group);

  @override
  List<Object?> get props => [group];
}

class _PendingRequestsReceived extends RandomGroupEvent {
  final List<JoinRequest> requests;

  const _PendingRequestsReceived(this.requests);

  @override
  List<Object?> get props => [requests];
}

class _MembersReceived extends RandomGroupEvent {
  final List<RandomGroupMember> members;

  const _MembersReceived(this.members);

  @override
  List<Object?> get props => [members];
}

class _RandomGroupStreamError extends RandomGroupEvent {
  final String message;

  const _RandomGroupStreamError(this.message);

  @override
  List<Object?> get props => [message];
}
