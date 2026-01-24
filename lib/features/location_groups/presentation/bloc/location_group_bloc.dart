import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/location_group_service.dart';
import '../../domain/entities/location_group.dart';
import '../../domain/entities/group_membership.dart';

part 'location_group_event.dart';
part 'location_group_state.dart';

/// BLoC for managing location groups with role-based access control.
///
/// ## Security Model
///
/// This BLoC enforces **reactive role-based access control** for group admin features:
///
/// 1. **`isAdmin` is derived from `currentMembership`**: The getter in state
///    returns `currentMembership?.isAdmin ?? false`, defaulting to `false`
///    (safe) when membership is unknown.
///
/// 2. **Reactive membership updates**: When `groupMembers` stream updates,
///    `currentMembership` is automatically synced to reflect role changes.
///    This ensures that if an admin is demoted, the UI updates immediately.
///
/// 3. **Defense in depth**: Client-side admin checks are complemented by
///    Firestore security rules that enforce `isGroupAdmin()` for:
///    - Group settings updates
///    - Join request management
///    - Member removal/promotion
///
/// ## Admin State Transitions Handled
///
/// - User promoted to admin → `currentMembership.isAdmin` becomes true
/// - User demoted from admin → `currentMembership.isAdmin` becomes false
/// - User removed from group → `currentMembership` becomes null (not admin)
/// - User leaves group → `currentMembership` cleared explicitly
class LocationGroupBloc extends Bloc<LocationGroupEvent, LocationGroupState> {
  final LocationGroupService _groupService;
  final Logger _logger = Logger();

  StreamSubscription<List<LocationGroup>>? _groupsSubscription;
  StreamSubscription<List<LocationGroup>>? _userGroupsSubscription;
  StreamSubscription<List<GroupMembership>>? _userGroupMembershipsSubscription;
  StreamSubscription<LocationGroup?>? _currentGroupSubscription;
  StreamSubscription<List<GroupMembership>>? _membersSubscription;
  StreamSubscription<List<GroupJoinRequest>>? _requestsSubscription;
  StreamSubscription<List<GroupJoinRequest>>? _userPendingRequestSubscription;

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
    on<ClearGroupDeletionFlag>(_onClearGroupDeletionFlag);
    on<ResetGroupState>(_onResetGroupState);
    on<ChangeSortOption>(_onChangeSortOption);
    on<DeleteGroup>(_onDeleteGroup);
    on<ClearGroupChat>(_onClearGroupChat);

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

    on<_UserGroupMembershipsUpdated>((event, emit) {
      // Build map of groupId -> unreadCount from memberships
      final unreadMap = <String, int>{
        for (final membership in event.memberships)
          membership.groupId: membership.unreadCount,
      };
      
      emit(state.copyWith(userGroupUnreadCounts: unreadMap));
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
      // SECURITY: Reactively update currentMembership from the live members stream.
      // This ensures role changes (admin->member or member->banned) are reflected
      // immediately in the UI without requiring a page reload.
      GroupMembership? updatedMembership = state.currentMembership;
      bool shouldClearMembership = false;
      
      if (state.currentGroupUserId != null) {
        // Find the current user's membership in the updated members list
        final userMembership = event.members.cast<GroupMembership?>().firstWhere(
          (m) => m?.userId == state.currentGroupUserId,
          orElse: () => null,
        );
        
        if (userMembership != null) {
          // User is still a member - update with latest role/status
          updatedMembership = userMembership;
        } else if (state.currentMembership != null) {
          // User was a member but is no longer in the active members list
          // This means they were removed/banned - clear their membership
          shouldClearMembership = true;
          updatedMembership = null;
        }
      }
      
      emit(state.copyWith(
        groupMembers: event.members,
        currentMembership: updatedMembership,
        clearCurrentMembership: shouldClearMembership,
      ));
    });

    on<_JoinRequestsUpdated>((event, emit) {
      emit(state.copyWith(joinRequests: event.requests));
    });

    on<_PendingRequestUpdated>((event, emit) {
      emit(state.copyWith(hasPendingRequest: event.hasPending));
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
    // Only show loading if we have no cached data for this location
    if (state.locationGroups.isEmpty ||
        state.selectedCountryCode != event.countryCode ||
        state.selectedStateCode != event.stateCode) {
      emit(state.copyWith(
        status: GroupBlocStatus.loading,
        selectedCountryCode: event.countryCode,
        selectedStateCode: event.stateCode,
        sortBy: event.sortBy,
      ));
    } else {
      // Keep showing existing data while refreshing
      emit(state.copyWith(
        selectedCountryCode: event.countryCode,
        selectedStateCode: event.stateCode,
        sortBy: event.sortBy,
      ));
    }

    await _groupsSubscription?.cancel();

    _groupsSubscription = _groupService
        .streamGroupsForLocation(
          countryCode: event.countryCode,
          stateCode: event.stateCode,
          sortBy: event.sortBy,
        )
        .listen(
          (groups) {
            if (!isClosed) add(_GroupsUpdated(groups));
          },
          onError: (error) {
            _logger.e('Error loading groups for location', error: error);
            // On error, keep existing data and show error only if we have no data
            if (!isClosed) {
              if (state.locationGroups.isEmpty) {
                add(_GroupsError(error.toString()));
              } else {
                // Log but don't update state - preserve existing data
                _logger.w('Preserving cached data after stream error');
              }
            }
          },
        );
  }

  Future<void> _onLoadUserGroups(
    LoadUserGroups event,
    Emitter<LocationGroupState> emit,
  ) async {
    // Handle user switching - if different user, force reload
    final isDifferentUser = state.userGroupsUserId != null && 
        state.userGroupsUserId != event.userId;
    
    // If already loading or loaded for the same user, don't reload.
    // This prevents redundant loads when navigating between pages.
    // NOTE: The Firestore streams remain active and continue to emit
    // real-time updates - new groups/messages will appear automatically!
    if (!isDifferentUser &&
        state.userGroupsUserId == event.userId &&
        (state.status == GroupBlocStatus.loading ||
         state.status == GroupBlocStatus.loaded)) {
      _logger.i('User groups already loaded/loading for user ${event.userId}, skipping reload');
      _logger.i('Real-time streams remain active - new group updates will appear automatically');
      return;
    }

    // If switching users, cancel existing subscriptions first and clear old data
    if (isDifferentUser) {
      _logger.i('User changed from ${state.userGroupsUserId} to ${event.userId}, reloading');
      await _userGroupsSubscription?.cancel();
      await _userGroupMembershipsSubscription?.cancel();
      _userGroupsSubscription = null;
      _userGroupMembershipsSubscription = null;
      emit(state.copyWith(
        status: GroupBlocStatus.loading,
        userGroupsUserId: event.userId,
        userGroups: const [], // Clear old user's data
      ));
    } else if (state.userGroups.isEmpty) {
      // Only show loading state if we have no cached data
      // This provides instant UI for returning users
      emit(state.copyWith(
        status: GroupBlocStatus.loading,
        userGroupsUserId: event.userId,
      ));
    } else {
      // Keep showing existing data while refreshing in background
      emit(state.copyWith(
        userGroupsUserId: event.userId,
      ));
    }

    await _userGroupsSubscription?.cancel();
    await _userGroupMembershipsSubscription?.cancel();

    // Streams now handle errors internally and never emit error events
    // Empty results are a valid state (user has no groups)
    _userGroupsSubscription = _groupService.streamUserGroups(event.userId).listen(
          (groups) {
            if (!isClosed) add(_UserGroupsUpdated(groups));
          },
          onError: (error) {
            _logger.e('Error in user groups stream', error: error);
            // Don't emit error state - show empty list instead for better UX
          },
        );

    _userGroupMembershipsSubscription =
        _groupService.streamUserMemberships(event.userId).listen(
      (memberships) {
        if (!isClosed) add(_UserGroupMembershipsUpdated(memberships));
      },
      onError: (error) {
        _logger.e('Error in user memberships stream', error: error);
        // Don't emit error state - show empty counts instead for better UX
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
          errorMessage: null, // Clear any previous errors
        ));
        break;
      case GroupFailure(:final message):
        _logger.e('Failed to create group: $message');
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
          createdGroup: null, // Clear created group on error
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
        // Update state with new membership and clear pending request flag
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          currentMembership: data,
          hasPendingRequest: false,
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
          clearCurrentMembership: true, // SECURITY: Explicitly clear membership
          hasPendingRequest: false,
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
    // Set loading state and clear previous group data to prevent showing stale state
    // SECURITY: Store currentGroupUserId for reactive membership updates
    emit(state.copyWith(
      status: GroupBlocStatus.loading,
      currentGroup: null,
      clearCurrentMembership: true, // Explicitly clear membership
      hasPendingRequest: false,
      groupMembers: const [],
      currentGroupUserId: event.currentUserId,
    ));

    await _currentGroupSubscription?.cancel();
    await _membersSubscription?.cancel();
    await _userPendingRequestSubscription?.cancel();

    _currentGroupSubscription = _groupService.streamGroup(event.groupId).listen(
          (group) async {
            if (isClosed) return;
            if (group != null) {
              GroupMembership? membership;
              bool hasPendingRequest = false;

              if (event.currentUserId != null) {
                // CRITICAL: Keep loading state while checking membership
                // This prevents UI from showing wrong buttons during async check
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

              // NOW emit the loaded state with complete data
              if (!isClosed) add(_GroupDetailsUpdated(group, membership, hasPendingRequest));
            }
          },
          onError: (error) {
            _logger.e('Error streaming group', error: error);
            if (!isClosed) {
              add(_GroupsError('Failed to load group details'));
            }
          },
        );

    _membersSubscription = _groupService.streamGroupMembers(event.groupId).listen(
          (members) {
            if (!isClosed) add(_MembersUpdated(members));
          },
          onError: (error) {
            _logger.e('Error streaming members', error: error);
          },
        );

    // Stream pending request status for current user in real-time
    if (event.currentUserId != null) {
      _userPendingRequestSubscription = _groupService.streamJoinRequests(event.groupId).listen(
        (requests) {
          if (!isClosed) {
            final hasPending = requests.any((r) => r.userId == event.currentUserId);
            // Only update if membership is null or not active (to avoid overriding member state)
            if (state.currentMembership == null || !state.currentMembership!.isActive) {
              if (state.hasPendingRequest != hasPending) {
                add(_PendingRequestUpdated(hasPending));
              }
            }
          }
        },
        onError: (error) {
          _logger.e('Error streaming user pending request', error: error);
        },
      );
    }
  }

  Future<void> _onLoadJoinRequests(
    LoadJoinRequests event,
    Emitter<LocationGroupState> emit,
  ) async {
    await _requestsSubscription?.cancel();

    _requestsSubscription = _groupService.streamJoinRequests(event.groupId).listen(
          (requests) {
            if (!isClosed) add(_JoinRequestsUpdated(requests));
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
      avatarUrl: event.avatarUrl,
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

  void _onClearGroupDeletionFlag(
    ClearGroupDeletionFlag event,
    Emitter<LocationGroupState> emit,
  ) {
    emit(state.copyWith(groupDeleted: false));
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

  Future<void> _onDeleteGroup(
    DeleteGroup event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.loading));

    final result = await _groupService.deleteGroup(
      groupId: event.groupId,
      adminUserId: event.adminUserId,
    );

    switch (result) {
      case GroupSuccess():
        _logger.i('Group ${event.groupId} deleted successfully');
        emit(state.copyWith(
          status: GroupBlocStatus.loaded,
          currentGroup: null,
          groupDeleted: true,
          errorMessage: null,
        ));
        break;
      case GroupFailure(:final message):
        _logger.e('Failed to delete group: $message');
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  Future<void> _onClearGroupChat(
    ClearGroupChat event,
    Emitter<LocationGroupState> emit,
  ) async {
    emit(state.copyWith(status: GroupBlocStatus.loading));

    final result = await _groupService.clearGroupMessages(
      groupId: event.groupId,
      adminUserId: event.adminUserId,
    );

    switch (result) {
      case GroupSuccess():
        emit(state.copyWith(status: GroupBlocStatus.loaded));
        break;
      case GroupFailure(:final message):
        emit(state.copyWith(
          status: GroupBlocStatus.error,
          errorMessage: message,
        ));
        break;
    }
  }

  void _cancelSubscriptions() {
    _groupsSubscription?.cancel();
    _userGroupsSubscription?.cancel();
    _userGroupMembershipsSubscription?.cancel();
    _currentGroupSubscription?.cancel();
    _membersSubscription?.cancel();
    _requestsSubscription?.cancel();
    _userPendingRequestSubscription?.cancel();
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

class _UserGroupMembershipsUpdated extends LocationGroupEvent {
  final List<GroupMembership> memberships;
  const _UserGroupMembershipsUpdated(this.memberships);
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

class _PendingRequestUpdated extends LocationGroupEvent {
  final bool hasPending;
  const _PendingRequestUpdated(this.hasPending);
}

class _GroupsError extends LocationGroupEvent {
  final String message;
  const _GroupsError(this.message);
}
