import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/random_group_chat_service.dart';
import '../../data/random_group_service.dart';
import '../../domain/entities/join_request.dart';
import '../../domain/entities/random_group.dart';
import '../../domain/entities/random_group_member.dart';

part 'random_group_event.dart';
part 'random_group_state.dart';

/// BLoC for managing random groups.
///
/// Handles:
/// - Discovering active random groups
/// - Creating groups
/// - Join request flow
/// - Membership management
/// - Admin controls
class RandomGroupBloc extends Bloc<RandomGroupEvent, RandomGroupState> {
  final RandomGroupService _groupService;
  final RandomGroupChatService? _chatService;
  final Logger _logger;

  StreamSubscription<List<RandomGroup>>? _activeGroupsSubscription;
  StreamSubscription<List<RandomGroup>>? _userGroupsSubscription;
  StreamSubscription<List<RandomGroup>>? _userCreatedGroupsSubscription;
  StreamSubscription<RandomGroup?>? _groupDetailsSubscription;
  StreamSubscription<List<JoinRequest>>? _pendingRequestsSubscription;
  StreamSubscription<List<RandomGroupMember>>? _membersSubscription;
  StreamSubscription<Map<String, int>>? _unreadCountsSubscription;

  RandomGroupBloc({
    required RandomGroupService groupService,
    RandomGroupChatService? chatService,
    Logger? logger,
  })  : _groupService = groupService,
        _chatService = chatService,
        _logger = logger ?? Logger(),
        super(const RandomGroupState()) {
    on<WatchActiveRandomGroups>(_onWatchActiveRandomGroups);
    on<WatchUserRandomGroups>(_onWatchUserRandomGroups);
    on<ForceRefreshRandomGroups>(_onForceRefreshRandomGroups);
    on<WatchUserCreatedRandomGroups>(_onWatchUserCreatedRandomGroups);
    on<CreateRandomGroup>(_onCreateRandomGroup);
    on<LoadRandomGroupDetails>(_onLoadRandomGroupDetails);
    on<RequestToJoinRandomGroup>(_onRequestToJoinRandomGroup);
    on<WatchPendingRequests>(_onWatchPendingRequests);
    on<ApproveJoinRequest>(_onApproveJoinRequest);
    on<RejectJoinRequest>(_onRejectJoinRequest);
    on<ApproveAllJoinRequests>(_onApproveAllJoinRequests);
    on<RemoveRandomGroupMember>(_onRemoveRandomGroupMember);
    on<PromoteToAdmin>(_onPromoteToAdmin);
    on<DemoteFromAdmin>(_onDemoteFromAdmin);
    on<LeaveRandomGroup>(_onLeaveRandomGroup);
    on<DeleteRandomGroup>(_onDeleteRandomGroup);
    on<UpdateRandomGroup>(_onUpdateRandomGroup);
    on<WatchRandomGroupMembers>(_onWatchRandomGroupMembers);
    on<CheckMembershipStatus>(_onCheckMembershipStatus);
    on<ClearRandomGroupChat>(_onClearRandomGroupChat);
    on<ResetRandomGroupState>(_onResetRandomGroupState);
    on<_ActiveGroupsReceived>(_onActiveGroupsReceived);
    on<_UserGroupsReceived>(_onUserGroupsReceived);
    on<_UserCreatedGroupsReceived>(_onUserCreatedGroupsReceived);
    on<_GroupDetailsReceived>(_onGroupDetailsReceived);
    on<_PendingRequestsReceived>(_onPendingRequestsReceived);
    on<_MembersReceived>(_onMembersReceived);
    on<_RandomGroupStreamError>(_onRandomGroupStreamError);
    on<_UnreadCountsReceived>(_onUnreadCountsReceived);
  }

  Future<void> _onWatchActiveRandomGroups(
    WatchActiveRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    // If we already have an active subscription, skip re-subscribing.
    // The existing stream keeps the data fresh in real-time.
    if (_activeGroupsSubscription != null) {
      _logger.d('Already watching active random groups, skipping');
      return;
    }

    _logger.d('Starting to watch active random groups');

    emit(state.copyWith(
        status: RandomGroupBlocStatus.loading, clearError: true));

    try {
      _activeGroupsSubscription = _groupService.watchActiveGroups().listen(
            (groups) => add(_ActiveGroupsReceived(groups)),
            onError: (error) {
              _logger.e('Active groups stream error: $error');
              add(_RandomGroupStreamError(error.toString()));
            },
          );
    } catch (e) {
      _logger.e('Failed to start watching active groups: $e');
      emit(state.copyWith(
        status: RandomGroupBlocStatus.error,
        errorMessage: 'Failed to load groups. Please try again.',
      ));
    }
  }

  Future<void> _onWatchUserRandomGroups(
    WatchUserRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    // If we're already watching the same user's groups, skip re-subscribing.
    // The existing stream keeps the data fresh in real-time.
    if (_userGroupsSubscription != null &&
        state.userGroupsUserId == event.userId) {
      _logger.d(
          'Already watching user random groups for ${event.userId}, skipping');
      return;
    }

    _logger.d('Starting to watch user random groups for: ${event.userId}');

    // Cancel existing subscription (different user or first time)
    await _userGroupsSubscription?.cancel();
    _userGroupsSubscription = null;

    // Only clear groups if the user actually changed, to prevent flash of empty state
    final userChanged = state.userGroupsUserId != null &&
        state.userGroupsUserId != event.userId;

    emit(state.copyWith(
      userGroups: userChanged ? const [] : state.userGroups,
      userGroupsUserId: event.userId,
      status: state.userGroups.isEmpty || userChanged
          ? RandomGroupBlocStatus.loading
          : state.status,
      clearError: true,
    ));

    try {
      _userGroupsSubscription = _groupService
          .watchUserMemberships(event.userId)
          .listen(
            (groups) => add(_UserGroupsReceived(groups)),
            onError: (error) {
              _logger.e('User groups stream error: $error');
              add(_RandomGroupStreamError(error.toString()));
            },
          );

      // Also start watching unread counts
      await _unreadCountsSubscription?.cancel();
      _unreadCountsSubscription = _groupService
          .watchUserUnreadCounts(event.userId)
          .listen(
            (unreadCounts) => add(_UnreadCountsReceived(unreadCounts)),
            onError: (error) {
              _logger.w('Unread counts stream error: $error');
            },
          );
    } catch (e) {
      _logger.e('Failed to start watching user groups: $e');
      emit(state.copyWith(
        status: RandomGroupBlocStatus.error,
        errorMessage: 'Failed to load your groups. Please try again.',
      ));
    }
  }

  Future<void> _onWatchUserCreatedRandomGroups(
    WatchUserCreatedRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Starting to watch user created groups for: ${event.userId}');

    await _userCreatedGroupsSubscription?.cancel();

    _userCreatedGroupsSubscription = _groupService
        .watchUserCreatedGroups(event.userId)
        .listen(
          (groups) => add(_UserCreatedGroupsReceived(groups)),
          onError: (error) => add(_RandomGroupStreamError(error.toString())),
        );
  }

  Future<void> _onCreateRandomGroup(
    CreateRandomGroup event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Creating random group: ${event.name}');

    emit(state.copyWith(
        status: RandomGroupBlocStatus.creating, clearError: true));

    final result = await _groupService.createGroup(
      name: event.name,
      topic: event.topic,
      description: event.description,
      creatorId: event.creatorId,
      creatorUsername: event.creatorUsername,
      creatorDisplayName: event.creatorDisplayName,
      creatorPhotoUrl: event.creatorPhotoUrl,
    );

    switch (result) {
      case RandomGroupSuccess(data: final group):
        _logger.i('Created random group: ${group.id}');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.created,
          selectedGroup: group,
          membershipStatus: UserMembershipStatus.creator,
        ));

      case RandomGroupFailure(message: final msg, type: final type):
        _logger.w('Failed to create random group: $msg ($type)');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onLoadRandomGroupDetails(
    LoadRandomGroupDetails event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Loading random group details: ${event.groupId}');

    await _groupDetailsSubscription?.cancel();

    emit(state.copyWith(
        status: RandomGroupBlocStatus.loading, clearError: true));

    _groupDetailsSubscription = _groupService.watchGroup(event.groupId).listen(
          (group) => add(_GroupDetailsReceived(group)),
          onError: (error) => add(_RandomGroupStreamError(error.toString())),
        );
  }

  Future<void> _onRequestToJoinRandomGroup(
    RequestToJoinRandomGroup event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Requesting to join group: ${event.groupId}');

    emit(state.copyWith(
        status: RandomGroupBlocStatus.joining, clearError: true));

    final result = await _groupService.requestToJoin(
      groupId: event.groupId,
      requesterId: event.requesterId,
      requesterUsername: event.requesterUsername,
      requesterDisplayName: event.requesterDisplayName,
      requesterPhotoUrl: event.requesterPhotoUrl,
      message: event.message,
    );

    switch (result) {
      case RandomGroupSuccess(data: final request):
        _logger.i('Join request created: ${request.id}');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.joined,
          membershipStatus: UserMembershipStatus.pending,
          userJoinRequest: request,
        ));

      case RandomGroupFailure(message: final msg, type: final type):
        _logger.w('Failed to request join: $msg ($type)');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onWatchPendingRequests(
    WatchPendingRequests event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Watching pending requests for: ${event.groupId}');

    await _pendingRequestsSubscription?.cancel();

    _pendingRequestsSubscription = _groupService
        .watchPendingRequests(event.groupId)
        .listen(
          (requests) => add(_PendingRequestsReceived(requests)),
          onError: (error) => add(_RandomGroupStreamError(error.toString())),
        );
  }

  Future<void> _onApproveJoinRequest(
    ApproveJoinRequest event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Approving join request: ${event.requestId}');

    final result = await _groupService.approveRequest(
      groupId: event.groupId,
      requestId: event.requestId,
      adminId: event.adminId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Approved request: ${event.requestId}');
        // Send system message for join notification
        if (_chatService != null && event.requesterUsername != null) {
          _chatService.sendSystemMessage(
            groupId: event.groupId,
            text: '${event.requesterUsername} joined the group',
            delayBeforeSend: true,
          );
        }
      // State will update via stream

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to approve request: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onRejectJoinRequest(
    RejectJoinRequest event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Rejecting join request: ${event.requestId}');

    final result = await _groupService.rejectRequest(
      groupId: event.groupId,
      requestId: event.requestId,
      adminId: event.adminId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Rejected request: ${event.requestId}');
      // State will update via stream

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to reject request: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onApproveAllJoinRequests(
    ApproveAllJoinRequests event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Approving all pending requests for group: ${event.groupId}');

    final requests = List<JoinRequest>.from(state.pendingRequests);
    for (final request in requests) {
      final result = await _groupService.approveRequest(
        groupId: event.groupId,
        requestId: request.id,
        adminId: event.adminId,
      );

      switch (result) {
        case RandomGroupSuccess():
          _logger.i('Approved request: ${request.id}');
          // Send system message for join notification
          if (_chatService != null) {
            _chatService.sendSystemMessage(
              groupId: event.groupId,
              text:
                  '${request.requesterDisplayName ?? request.requesterUsername} joined the group',
              delayBeforeSend: true,
            );
          }

        case RandomGroupFailure(message: final msg):
          _logger.w('Failed to approve request ${request.id}: $msg');
      }
    }
    // State will update via stream
  }

  Future<void> _onRemoveRandomGroupMember(
    RemoveRandomGroupMember event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Removing member: ${event.memberId} from ${event.groupId}');

    final result = await _groupService.removeMember(
      groupId: event.groupId,
      memberId: event.memberId,
      adminId: event.adminId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Removed member: ${event.memberId}');
        // Send system message for removal notification
        if (_chatService != null && event.memberUsername != null) {
          _chatService.sendSystemMessage(
            groupId: event.groupId,
            text: '${event.memberUsername} was removed from the group',
          );
        }
      // State will update via stream

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to remove member: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onPromoteToAdmin(
    PromoteToAdmin event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Promoting member: ${event.memberId} to admin');

    final result = await _groupService.promoteToAdmin(
      groupId: event.groupId,
      memberId: event.memberId,
      adminId: event.adminId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Promoted member: ${event.memberId}');
      // State will update via stream

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to promote member: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onDemoteFromAdmin(
    DemoteFromAdmin event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Demoting admin: ${event.memberId} to regular member');

    final result = await _groupService.demoteFromAdmin(
      groupId: event.groupId,
      memberId: event.memberId,
      creatorId: event.creatorId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Demoted admin: ${event.memberId}');
      // State will update via stream

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to demote admin: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onLeaveRandomGroup(
    LeaveRandomGroup event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Leaving group: ${event.groupId}');

    // Send system message before leaving (while still a member)
    if (_chatService != null && event.username != null) {
      await _chatService.sendSystemMessage(
        groupId: event.groupId,
        text: '${event.username} left the group',
      );
    }

    final result = await _groupService.leaveGroup(
      groupId: event.groupId,
      userId: event.userId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Left group: ${event.groupId}');
        // Cancel detail streams to prevent stale state re-emission
        await _groupDetailsSubscription?.cancel();
        _groupDetailsSubscription = null;
        await _membersSubscription?.cancel();
        _membersSubscription = null;
        await _pendingRequestsSubscription?.cancel();
        _pendingRequestsSubscription = null;
        // Remove the left group from userGroups for immediate UI update
        final updatedGroupsAfterLeave = state.userGroups
            .where((g) => g.id != event.groupId)
            .toList();
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
          membershipStatus: UserMembershipStatus.notMember,
          clearSelectedGroup: true,
          userGroups: updatedGroupsAfterLeave,
        ));

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to leave group: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onDeleteRandomGroup(
    DeleteRandomGroup event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Deleting group: ${event.groupId}');

    final result = await _groupService.deleteGroup(
      groupId: event.groupId,
      userId: event.userId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Deleted group: ${event.groupId}');
        // Cancel detail streams to prevent stale state from deleted group
        await _groupDetailsSubscription?.cancel();
        _groupDetailsSubscription = null;
        await _membersSubscription?.cancel();
        _membersSubscription = null;
        await _pendingRequestsSubscription?.cancel();
        _pendingRequestsSubscription = null;
        // Remove the deleted group from userGroups for immediate UI update
        final updatedGroupsAfterDelete = state.userGroups
            .where((g) => g.id != event.groupId)
            .toList();
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
          membershipStatus: UserMembershipStatus.notMember,
          clearSelectedGroup: true,
          userGroups: updatedGroupsAfterDelete,
        ));

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to delete group: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onUpdateRandomGroup(
    UpdateRandomGroup event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Updating group: ${event.groupId}');

    emit(state.copyWith(
        status: RandomGroupBlocStatus.loading, clearError: true));

    final result = await _groupService.updateGroup(
      groupId: event.groupId,
      adminId: event.adminId,
      name: event.name,
      topic: event.topic,
      description: event.description,
      photoUrl: event.photoUrl,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Updated group: ${event.groupId}');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
        ));

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to update group: $msg');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.error,
          errorMessage: msg,
        ));
    }
  }

  Future<void> _onWatchRandomGroupMembers(
    WatchRandomGroupMembers event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Watching members for: ${event.groupId}');

    await _membersSubscription?.cancel();

    _membersSubscription = _groupService.watchMembers(event.groupId).listen(
          (members) => add(_MembersReceived(members)),
          onError: (error) => add(_RandomGroupStreamError(error.toString())),
        );
  }

  Future<void> _onCheckMembershipStatus(
    CheckMembershipStatus event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Checking membership status for: ${event.userId}');

    // Check if user is a member
    final isMember = await _groupService.isMember(event.groupId, event.userId);

    if (isMember) {
      // User is a member, start watching members now that we have permission
      add(WatchRandomGroupMembers(event.groupId));

      // Check if admin or creator
      final group = await _groupService.getGroup(event.groupId);
      if (group != null) {
        if (group.creatorId == event.userId) {
          emit(state.copyWith(
            membershipStatus: UserMembershipStatus.creator,
          ));
          // Start watching pending requests for creator
          add(WatchPendingRequests(event.groupId));
        } else if (group.adminIds.contains(event.userId)) {
          emit(state.copyWith(
            membershipStatus: UserMembershipStatus.admin,
          ));
          // Start watching pending requests for admin
          add(WatchPendingRequests(event.groupId));
        } else {
          emit(state.copyWith(
            membershipStatus: UserMembershipStatus.member,
          ));
        }
      }
      return;
    }

    // Check for pending request
    final request =
        await _groupService.getUserRequestStatus(event.groupId, event.userId);

    if (request != null && request.isPending) {
      emit(state.copyWith(
        membershipStatus: UserMembershipStatus.pending,
        userJoinRequest: request,
      ));
    } else {
      emit(state.copyWith(
        membershipStatus: UserMembershipStatus.notMember,
        clearUserJoinRequest: true,
      ));
    }
  }

  Future<void> _onClearRandomGroupChat(
    ClearRandomGroupChat event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Clearing chat for group: ${event.groupId}');

    // Don't set global status to loading — clear chat is a background operation
    // that shouldn't block the group list page with a loading/error state.

    final result = await _groupService.clearGroupMessages(
      groupId: event.groupId,
      adminUserId: event.adminUserId,
    );

    switch (result) {
      case RandomGroupSuccess():
        _logger.i('Cleared chat for group: ${event.groupId}');
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
          clearError: true,
        ));

      case RandomGroupFailure(message: final msg):
        _logger.w('Failed to clear chat: $msg');
        // Stay in loaded state — don't emit global error that breaks
        // other pages (like My Random Groups list showing error screen).
        // The error message is available for listeners to show a snackbar.
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
          errorMessage: msg,
        ));
    }
  }

  void _onActiveGroupsReceived(
    _ActiveGroupsReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    emit(state.copyWith(
      status: RandomGroupBlocStatus.loaded,
      activeGroups: event.groups,
    ));
  }

  void _onUserGroupsReceived(
    _UserGroupsReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    emit(state.copyWith(
      userGroups: event.groups,
      status: RandomGroupBlocStatus.loaded,
    ));
  }

  void _onUserCreatedGroupsReceived(
    _UserCreatedGroupsReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    emit(state.copyWith(
      userCreatedGroups: event.groups,
    ));
  }

  void _onGroupDetailsReceived(
    _GroupDetailsReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    if (event.group == null) {
      // Group document was deleted (hard-delete) or doesn't exist.
      // Clear the selected group so the detail page shows appropriate state.
      _logger.w('Group details stream emitted null (group deleted/not found)');
      emit(state.copyWith(
        status: RandomGroupBlocStatus.loaded,
        clearSelectedGroup: true,
        membershipStatus: UserMembershipStatus.notMember,
      ));
      return;
    }

    emit(state.copyWith(
      status: RandomGroupBlocStatus.loaded,
      selectedGroup: event.group,
    ));
  }

  void _onPendingRequestsReceived(
    _PendingRequestsReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    emit(state.copyWith(
      pendingRequests: event.requests,
    ));
  }

  void _onMembersReceived(
    _MembersReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    emit(state.copyWith(
      selectedGroupMembers: event.members,
    ));
  }

  void _onRandomGroupStreamError(
    _RandomGroupStreamError event,
    Emitter<RandomGroupState> emit,
  ) {
    _logger.e('Random group stream error: ${event.message}');
    emit(state.copyWith(
      status: RandomGroupBlocStatus.error,
      errorMessage: event.message,
    ));
  }

  void _onUnreadCountsReceived(
    _UnreadCountsReceived event,
    Emitter<RandomGroupState> emit,
  ) {
    emit(state.copyWith(userGroupUnreadCounts: event.unreadCounts));
  }

  /// Handler for resetting the BLoC state when switching accounts.
  /// Cancels all subscriptions and clears state to prevent permission errors.
  Future<void> _onResetRandomGroupState(
    ResetRandomGroupState event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Resetting random group state (account switch or cleanup)');

    // Cancel all active subscriptions
    await _cleanupAllSubscriptions();

    // Reset state to initial empty state
    emit(const RandomGroupState());
  }

  Future<void> _onForceRefreshRandomGroups(
    ForceRefreshRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Force refreshing random groups');

    // Cancel existing subscriptions to force re-subscribe
    await _activeGroupsSubscription?.cancel();
    _activeGroupsSubscription = null;

    if (event.userId != null) {
      await _userGroupsSubscription?.cancel();
      _userGroupsSubscription = null;
      await _unreadCountsSubscription?.cancel();
      _unreadCountsSubscription = null;
    }

    // Re-dispatch watch events which will now start fresh subscriptions
    add(const WatchActiveRandomGroups());
    if (event.userId != null) {
      add(WatchUserRandomGroups(event.userId!));
    }
  }

  /// Clean up all active subscriptions.
  Future<void> _cleanupAllSubscriptions() async {
    await _activeGroupsSubscription?.cancel();
    _activeGroupsSubscription = null;
    
    await _userGroupsSubscription?.cancel();
    _userGroupsSubscription = null;
    
    await _userCreatedGroupsSubscription?.cancel();
    _userCreatedGroupsSubscription = null;
    
    await _groupDetailsSubscription?.cancel();
    _groupDetailsSubscription = null;
    
    await _pendingRequestsSubscription?.cancel();
    _pendingRequestsSubscription = null;
    
    await _membersSubscription?.cancel();
    _membersSubscription = null;

    await _unreadCountsSubscription?.cancel();
    _unreadCountsSubscription = null;
  }

  /// Directly cancels all Firestore stream subscriptions.
  ///
  /// Unlike [ResetRandomGroupState] (which goes through the async event queue),
  /// this method cancels subscriptions immediately and can be awaited.
  /// Use this during sign-out to prevent PERMISSION_DENIED errors.
  Future<void> cancelSubscriptions() => _cleanupAllSubscriptions();

  @override
  Future<void> close() async {
    await _cleanupAllSubscriptions();
    return super.close();
  }
}
