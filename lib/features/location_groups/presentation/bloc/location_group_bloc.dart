import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/location_group_service.dart';
import '../../domain/entities/location_group.dart';
import '../../domain/entities/group_membership.dart';

part 'location_group_event.dart';
part 'location_group_state.dart';

/// BLoC for managing location groups.
class LocationGroupBloc extends Bloc<LocationGroupEvent, LocationGroupState> {
  final LocationGroupService _groupService;
  final Logger _logger = Logger();

  StreamSubscription<List<LocationGroup>>? _groupsSubscription;
  StreamSubscription<List<LocationGroup>>? _userGroupsSubscription;
  StreamSubscription<LocationGroup?>? _currentGroupSubscription;
  StreamSubscription<List<GroupMembership>>? _membersSubscription;
  StreamSubscription<List<GroupJoinRequest>>? _requestsSubscription;

  LocationGroupBloc({
    required LocationGroupService groupService,
  })  : _groupService = groupService,
        super(const LocationGroupState()) {
    // Public events
    on<LoadGroupsForLocation>(_onLoadGroupsForLocation);
    on<LoadUserGroups>(_onLoadUserGroups);
    on<CreateGroup>(_onCreateGroup);
    on<JoinPublicGroup>(_onJoinPublicGroup);
    on<RequestToJoinGroup>(_onRequestToJoinGroup);
    on<LeaveGroup>(_onLeaveGroup);
    on<LoadGroupDetails>(_onLoadGroupDetails);
    on<LoadJoinRequests>(_onLoadJoinRequests);
    on<ApproveJoinRequest>(_onApproveJoinRequest);
    on<RejectJoinRequest>(_onRejectJoinRequest);
    on<RemoveMember>(_onRemoveMember);
    on<PromoteToAdmin>(_onPromoteToAdmin);
    on<UpdateGroupSettings>(_onUpdateGroupSettings);
    on<ClearGroupError>(_onClearGroupError);
    on<ResetGroupState>(_onResetGroupState);
    on<ChangeSortOption>(_onChangeSortOption);

    // Private events for stream updates
    on<_GroupsUpdated>((event, emit) {
      emit(state.copyWith(
        status: GroupBlocStatus.loaded,
        locationGroups: event.groups,
      ));
    });

    on<_UserGroupsUpdated>((event, emit) {
      emit(state.copyWith(
        status: GroupBlocStatus.loaded,
        userGroups: event.groups,
      ));
    });

    on<_GroupDetailsUpdated>((event, emit) {
      emit(state.copyWith(
        status: GroupBlocStatus.loaded,
        currentGroup: event.group,
        currentMembership: event.membership,
        hasPendingRequest: event.hasPendingRequest,
      ));
    });

    on<_MembersUpdated>((event, emit) {
      emit(state.copyWith(groupMembers: event.members));
    });

    on<_JoinRequestsUpdated>((event, emit) {
      emit(state.copyWith(joinRequests: event.requests));
    });

    on<_GroupsError>((event, emit) {
      emit(state.copyWith(
        status: GroupBlocStatus.error,
        errorMessage: event.message,
      ));
    });
  }

  Future<void> _onLoadGroupsForLocation(
    LoadGroupsForLocation event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(
      status: GroupBlocStatus.loading,
      selectedCountryCode: event.countryCode,
      selectedStateCode: event.stateCode,
      sortBy: event.sortBy,
    ));

    await _groupsSubscription?.cancel();

    _groupsSubscription = _groupService
        .streamGroupsForLocation(
          countryCode: event.countryCode,
          stateCode: event.stateCode,
          sortBy: event.sortBy,
        )
        .listen(
          (groups) {
            add(_GroupsUpdated(groups));
          },
          onError: (error) {
            _logger.e('Error streaming groups', error: error);
            add(_GroupsError(error.toString()));
          },
        );
  }

  Future<void> _onLoadUserGroups(
    LoadUserGroups event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.loading));

    await _userGroupsSubscription?.cancel();

    _userGroupsSubscription = _groupService.streamUserGroups(event.userId).listen(
          (groups) {
            add(_UserGroupsUpdated(groups));
          },
          onError: (error) {
            _logger.e('Error streaming user groups', error: error);
          },
        );
  }

  Future<void> _onCreateGroup(
    CreateGroup event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.creating));

    final result = await _groupService.createGroup(
      name: event.name,
      description: event.description,
      countryCode: event.countryCode,
      stateCode: event.stateCode,
      countryName: event.countryName,
      stateName: event.stateName,
      creatorUserId: event.creatorUserId,
      creatorUserName: event.creatorUserName,
      creatorUserPhotoUrl: event.creatorUserPhotoUrl,
      visibility: event.visibility,
    );

    switch (result) {
      case GroupSuccess(:final data):
        _logger.i('Group created: ${data.id}');
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          createdGroup: data,
        ));
        break;
      case GroupFailure(:final message):
        _logger.e('Failed to create group: $message');
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  Future<void> _onJoinPublicGroup(
    JoinPublicGroup event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.joining));

    final result = await _groupService.joinPublicGroup(
      groupId: event.groupId,
      userId: event.userId,
      userName: event.userName,
      userPhotoUrl: event.userPhotoUrl,
    );

    switch (result) {
      case GroupSuccess(:final data):
        _logger.i('Joined group: ${event.groupId}');
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          currentMembership: data,
        ));
        break;
      case GroupFailure(:final message):
        _logger.e('Failed to join group: $message');
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  Future<void> _onRequestToJoinGroup(
    RequestToJoinGroup event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.joining));

    final result = await _groupService.requestToJoin(
      groupId: event.groupId,
      userId: event.userId,
      userName: event.userName,
      userPhotoUrl: event.userPhotoUrl,
      message: event.message,
    );

    switch (result) {
      case GroupSuccess():
        _logger.i('Request sent for group: ${event.groupId}');
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          hasPendingRequest: true,
        ));
        break;
      case GroupFailure(:final message):
        _logger.e('Failed to request join: $message');
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  Future<void> _onLeaveGroup(
    LeaveGroup event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.leaving));

    final result = await _groupService.leaveGroup(
      groupId: event.groupId,
      userId: event.userId,
    );

    switch (result) {
      case GroupSuccess():
        _logger.i('Left group: ${event.groupId}');
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          currentMembership: null,
        ));
        break;
      case GroupFailure(:final message):
        _logger.e('Failed to leave group: $message');
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  Future<void> _onLoadGroupDetails(
    LoadGroupDetails event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.loading));

    await _currentGroupSubscription?.cancel();
    await _membersSubscription?.cancel();

    _currentGroupSubscription = _groupService.streamGroup(event.groupId).listen(
          (group) async {
            if (group != null) {
              GroupMembership? membership;
              bool hasPendingRequest = false;

              if (event.currentUserId != null) {
                membership = await _groupService.getMembershipStatus(
                  event.groupId,
                  event.currentUserId!,
                );

                // Check for pending request if not a member
                if (membership == null || !membership.isActive) {
                  final requests = await _groupService.getJoinRequests(event.groupId);
                  hasPendingRequest = requests.any(
                    (r) => r.userId == event.currentUserId,
                  );
                }
              }

              add(_GroupDetailsUpdated(group, membership, hasPendingRequest));
            }
          },
          onError: (error) {
            _logger.e('Error streaming group', error: error);
          },
        );

    _membersSubscription = _groupService.streamGroupMembers(event.groupId).listen(
          (members) {
            add(_MembersUpdated(members));
          },
          onError: (error) {
            _logger.e('Error streaming members', error: error);
          },
        );
  }

  Future<void> _onLoadJoinRequests(
    LoadJoinRequests event,
    Emitter<LocationGroupState> emit,
  ) async {
    await _requestsSubscription?.cancel();

    _requestsSubscription = _groupService.streamJoinRequests(event.groupId).listen(
          (requests) {
            add(_JoinRequestsUpdated(requests));
          },
          onError: (error) {
            _logger.e('Error streaming join requests', error: error);
          },
        );
  }

  Future<void> _onApproveJoinRequest(
    ApproveJoinRequest event,
    Emitter<LocationGroupState> emit,
  ) async {
    final result = await _groupService.approveJoinRequest(
      groupId: event.groupId,
      requestUserId: event.requestUserId,
      adminUserId: event.adminUserId,
    );

    if (result is GroupFailure<GroupMembership>) {
      emit(state.copyWith(
        status: GroupBlocStatus.error,
        errorMessage: result.message,
      ));
    }
  }

  Future<void> _onRejectJoinRequest(
    RejectJoinRequest event,
    Emitter<LocationGroupState> emit,
  ) async {
    final result = await _groupService.rejectJoinRequest(
      groupId: event.groupId,
      requestUserId: event.requestUserId,
      adminUserId: event.adminUserId,
    );

    if (result is GroupFailure<void>) {
      emit(state.copyWith(
        status: GroupBlocStatus.error,
        errorMessage: result.message,
      ));
    }
  }

  Future<void> _onRemoveMember(
    RemoveMember event,
    Emitter<LocationGroupState> emit,
  ) async {
    final result = await _groupService.removeMember(
      groupId: event.groupId,
      targetUserId: event.targetUserId,
      adminUserId: event.adminUserId,
      ban: event.ban,
    );

    if (result is GroupFailure<void>) {
      emit(state.copyWith(
        status: GroupBlocStatus.error,
        errorMessage: result.message,
      ));
    }
  }

  Future<void> _onPromoteToAdmin(
    PromoteToAdmin event,
    Emitter<LocationGroupState> emit,
  ) async {
    final result = await _groupService.promoteToAdmin(
      groupId: event.groupId,
      targetUserId: event.targetUserId,
      adminUserId: event.adminUserId,
    );

    if (result is GroupFailure<void>) {
      emit(state.copyWith(
        status: GroupBlocStatus.error,
        errorMessage: result.message,
      ));
    }
  }

  Future<void> _onUpdateGroupSettings(
    UpdateGroupSettings event,
    Emitter<LocationGroupState> emit,
  ) async {
    final result = await _groupService.updateGroup(
      groupId: event.groupId,
      adminUserId: event.adminUserId,
      name: event.name,
      description: event.description,
      visibility: event.visibility,
    );

    switch (result) {
      case GroupSuccess(:final data):
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          currentGroup: data,
        ));
        break;
      case GroupFailure(:final message):
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  void _onClearGroupError(
    ClearGroupError event,
    Emitter<LocationGroupState> emit,
  ) {
    emit(state.copyWith(
      status: GroupBlocStatus.loaded,
      errorMessage: null,
    ));
  }

  void _onResetGroupState(
    ResetGroupState event,
    Emitter<LocationGroupState> emit,
  ) {
    _cancelSubscriptions();
    emit(const LocationGroupState());
  }

  void _onChangeSortOption(
    ChangeSortOption event,
    Emitter<LocationGroupState> emit,
  ) {
    if (state.selectedCountryCode != null && state.selectedStateCode != null) {
      add(LoadGroupsForLocation(
        countryCode: state.selectedCountryCode!,
        stateCode: state.selectedStateCode!,
        sortBy: event.sortBy,
      ));
    }
  }

  void _cancelSubscriptions() {
    _groupsSubscription?.cancel();
    _userGroupsSubscription?.cancel();
    _currentGroupSubscription?.cancel();
    _membersSubscription?.cancel();
    _requestsSubscription?.cancel();
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    return super.close();
  }
}

// Private events for stream updates
class _GroupsUpdated extends LocationGroupEvent {
  final List<LocationGroup> groups;
  const _GroupsUpdated(this.groups);
}

class _UserGroupsUpdated extends LocationGroupEvent {
  final List<LocationGroup> groups;
  const _UserGroupsUpdated(this.groups);
}

class _GroupDetailsUpdated extends LocationGroupEvent {
  final LocationGroup group;
  final GroupMembership? membership;
  final bool hasPendingRequest;
  const _GroupDetailsUpdated(this.group, this.membership, this.hasPendingRequest);
}

class _MembersUpdated extends LocationGroupEvent {
  final List<GroupMembership> members;
  const _MembersUpdated(this.members);
}

class _JoinRequestsUpdated extends LocationGroupEvent {
  final List<GroupJoinRequest> requests;
  const _JoinRequestsUpdated(this.requests);
}

class _GroupsError extends LocationGroupEvent {
  final String message;
  const _GroupsError(this.message);
}
