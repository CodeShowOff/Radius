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
    on<WatchUserCreatedRandomGroups>(_onWatchUserCreatedRandomGroups);
    on<CreateRandomGroup>(_onCreateRandomGroup);
    on<LoadRandomGroupDetails>(_onLoadRandomGroupDetails);
    on<RequestToJoinRandomGroup>(_onRequestToJoinRandomGroup);
    on<WatchPendingRequests>(_onWatchPendingRequests);
    on<ApproveJoinRequest>(_onApproveJoinRequest);
    on<RejectJoinRequest>(_onRejectJoinRequest);
    on<RemoveRandomGroupMember>(_onRemoveRandomGroupMember);
    on<PromoteToAdmin>(_onPromoteToAdmin);
    on<LeaveRandomGroup>(_onLeaveRandomGroup);
    on<DeleteRandomGroup>(_onDeleteRandomGroup);
    on<UpdateRandomGroup>(_onUpdateRandomGroup);
    on<WatchRandomGroupMembers>(_onWatchRandomGroupMembers);
    on<CheckMembershipStatus>(_onCheckMembershipStatus);
    on<_ActiveGroupsReceived>(_onActiveGroupsReceived);
    on<_UserGroupsReceived>(_onUserGroupsReceived);
    on<_UserCreatedGroupsReceived>(_onUserCreatedGroupsReceived);
    on<_GroupDetailsReceived>(_onGroupDetailsReceived);
    on<_PendingRequestsReceived>(_onPendingRequestsReceived);
    on<_MembersReceived>(_onMembersReceived);
    on<_RandomGroupStreamError>(_onRandomGroupStreamError);
  }

  Future<void> _onWatchActiveRandomGroups(
    WatchActiveRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Starting to watch active random groups');

    await _activeGroupsSubscription?.cancel();

    emit(state.copyWith(status: RandomGroupBlocStatus.loading, clearError: true));

    _activeGroupsSubscription = _groupService.watchActiveGroups().listen(
      (groups) => add(_ActiveGroupsReceived(groups)),
      onError: (error) => add(_RandomGroupStreamError(error.toString())),
    );
  }

  Future<void> _onWatchUserRandomGroups(
    WatchUserRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Starting to watch user random groups for: ${event.userId}');

    await _userGroupsSubscription?.cancel();

    _userGroupsSubscription =
        _groupService.watchUserMemberships(event.userId).listen(
      (groups) => add(_UserGroupsReceived(groups)),
      onError: (error) => add(_RandomGroupStreamError(error.toString())),
    );
  }

  Future<void> _onWatchUserCreatedRandomGroups(
    WatchUserCreatedRandomGroups event,
    Emitter<RandomGroupState> emit,
  ) async {
    _logger.d('Starting to watch user created groups for: ${event.userId}');

    await _userCreatedGroupsSubscription?.cancel();

    _userCreatedGroupsSubscription =
        _groupService.watchUserCreatedGroups(event.userId).listen(
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

    emit(state.copyWith(status: RandomGroupBlocStatus.loading, clearError: true));

    _groupDetailsSubscription =
        _groupService.watchGroup(event.groupId).listen(
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

    _pendingRequestsSubscription =
        _groupService.watchPendingRequests(event.groupId).listen(
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
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
          membershipStatus: UserMembershipStatus.notMember,
          clearSelectedGroup: true,
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
        emit(state.copyWith(
          status: RandomGroupBlocStatus.loaded,
          clearSelectedGroup: true,
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
    final isMember =
        await _groupService.isMember(event.groupId, event.userId);

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

  @override
  Future<void> close() async {
    await _activeGroupsSubscription?.cancel();
    await _userGroupsSubscription?.cancel();
    await _userCreatedGroupsSubscription?.cancel();
    await _groupDetailsSubscription?.cancel();
    await _pendingRequestsSubscription?.cancel();
    await _membersSubscription?.cancel();
    return super.close();
  }
}
