import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../proximity/domain/entities/nearby_user.dart';
import '../../../proximity/proximity_service.dart';
import '../../data/nearby_group_service.dart';
import '../../domain/entities/nearby_group.dart';
import '../../domain/entities/nearby_group_member.dart';

part 'nearby_group_event.dart';
part 'nearby_group_state.dart';

/// BLoC for managing nearby groups.
///
/// Handles:
/// - Discovering active nearby groups
/// - Creating and closing groups
/// - Bluetooth scanning for group creators (10s scan, 10s cooldown)
/// - Member presence updates
class NearbyGroupBloc extends Bloc<NearbyGroupEvent, NearbyGroupState> {
  final NearbyGroupService _groupService;
  final ProximityService _proximityService;
  final BluetoothService _bluetoothService;
  final Logger _logger;

  StreamSubscription<List<NearbyGroup>>? _activeGroupsSubscription;
  StreamSubscription<List<NearbyGroup>>? _userGroupsSubscription;
  StreamSubscription<List<NearbyGroupMember>>? _membersSubscription;
  StreamSubscription<List<NearbyUser>>? _nearbyUsersSubscription;
  StreamSubscription<ProximityServiceState>? _proximityStateSubscription;
  
  Timer? _heartbeatTimer;
  Timer? _scanCycleTimer;
  
  String? _currentGroupId;
  String? _currentCreatorId;
  bool _isScanningPhase = false;

  /// Interval for sending heartbeat updates (keep group alive)
  static const Duration heartbeatInterval = Duration(seconds: 5);

  /// Duration for scanning phase
  static const Duration scanDuration = Duration(seconds: 10);

  /// Duration for cooldown phase between scans
  static const Duration scanCooldown = Duration(seconds: 10);

  NearbyGroupBloc({
    required NearbyGroupService groupService,
    required ProximityService proximityService,
    required BluetoothService bluetoothService,
    Logger? logger,
  })  : _groupService = groupService,
        _proximityService = proximityService,
        _bluetoothService = bluetoothService,
        _logger = logger ?? Logger(),
        super(const NearbyGroupState()) {
    on<WatchActiveNearbyGroups>(_onWatchActiveNearbyGroups);
    on<WatchUserNearbyGroups>(_onWatchUserNearbyGroups);
    on<ForceRefreshNearbyGroups>(_onForceRefreshNearbyGroups);
    on<CreateNearbyGroup>(_onCreateNearbyGroup);
    on<CloseNearbyGroup>(_onCloseNearbyGroup);
    on<StartGroupScanning>(_onStartGroupScanning);
    on<StopGroupScanning>(_onStopGroupScanning);
    on<LoadNearbyGroupDetails>(_onLoadNearbyGroupDetails);
    on<LoadUserActiveGroup>(_onLoadUserActiveGroup);
    on<ResetNearbyGroupState>(_onResetNearbyGroupState);
    on<_ActiveGroupsReceived>(_onActiveGroupsReceived);
    on<_UserGroupsReceived>(_onUserGroupsReceived);
    on<_GroupMembersReceived>(_onGroupMembersReceived);
    on<_NearbyUsersDetected>(_onNearbyUsersDetected);
    on<_NearbyGroupStreamError>(_onNearbyGroupStreamError);
    on<_ScanCycleComplete>(_onScanCycleComplete);
  }

  Future<void> _onWatchActiveNearbyGroups(
    WatchActiveNearbyGroups event,
    Emitter<NearbyGroupState> emit,
  ) async {
    // If we already have an active subscription, skip re-subscribing.
    // The existing stream keeps the data fresh in real-time.
    if (_activeGroupsSubscription != null) {
      _logger.d('Already watching active nearby groups, skipping');
      return;
    }

    _logger.d('Starting to watch active nearby groups');

    emit(state.copyWith(status: NearbyGroupBlocStatus.loading, clearError: true));

    try {
      _activeGroupsSubscription = _groupService.watchActiveGroups().listen(
        (groups) => add(_ActiveGroupsReceived(groups)),
        onError: (error) {
          _logger.e('Active groups stream error: $error');
          add(_NearbyGroupStreamError(error.toString()));
        },
      );
    } catch (e) {
      _logger.e('Failed to start watching active groups: $e');
      emit(state.copyWith(
        status: NearbyGroupBlocStatus.error,
        errorMessage: 'Failed to load groups. Please try again.',
      ));
    }
  }

  Future<void> _onWatchUserNearbyGroups(
    WatchUserNearbyGroups event,
    Emitter<NearbyGroupState> emit,
  ) async {
    // If we're already watching the same user's groups, skip re-subscribing.
    // The existing stream keeps the data fresh in real-time.
    if (_userGroupsSubscription != null &&
        state.userGroupsUserId == event.userId) {
      _logger.d(
          'Already watching user nearby groups for ${event.userId}, skipping');
      return;
    }

    _logger.d('Starting to watch user nearby groups for: ${event.userId}');

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
          ? NearbyGroupBlocStatus.loading
          : state.status,
      clearError: true,
    ));

    try {
      _userGroupsSubscription =
          _groupService.watchUserMemberships(event.userId).listen(
        (groups) => add(_UserGroupsReceived(groups)),
        onError: (error) {
          _logger.e('User groups stream error: $error');
          add(_NearbyGroupStreamError(error.toString()));
        },
      );
    } catch (e) {
      _logger.e('Failed to start watching user groups: $e');
      emit(state.copyWith(
        status: NearbyGroupBlocStatus.error,
        errorMessage: 'Failed to load your groups. Please try again.',
      ));
    }
  }

  Future<void> _onCreateNearbyGroup(
    CreateNearbyGroup event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Creating nearby group: ${event.name}');

    emit(state.copyWith(status: NearbyGroupBlocStatus.creating, clearError: true));

    try {
      // Check if Bluetooth is enabled with timeout
      final isBluetoothEnabled = await _bluetoothService.isBluetoothEnabled()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isBluetoothEnabled) {
        _logger.w('Bluetooth is not enabled');
        emit(state.copyWith(
          status: NearbyGroupBlocStatus.error,
          errorMessage: 'Please turn on Bluetooth to create a group',
        ));
        return;
      }

      // Initialize Bluetooth service if needed (with timeout)
      final bluetoothInitialized = await _bluetoothService.initialize()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!bluetoothInitialized) {
        _logger.w('Failed to initialize Bluetooth service');
        // Don't return - try to create group anyway, scanning can start later
      }

      // Initialize ProximityService for advertising (with timeout)
      await _proximityService.initialize(
        event.creatorId,
        event.creatorUsername,
      ).timeout(const Duration(seconds: 5), onTimeout: () => false);

      // Create the group in Firestore - this is the critical operation
      final result = await _groupService.createGroup(
        name: event.name,
        description: event.description,
        creatorId: event.creatorId,
        creatorUsername: event.creatorUsername,
        creatorDisplayName: event.creatorDisplayName,
        creatorPhotoUrl: event.creatorPhotoUrl,
      );

      switch (result) {
        case NearbyGroupSuccess(data: final group):
          _logger.i('Created nearby group: ${group.id}');
          
          // Set the group first, then schedule scanning to start after navigation
          emit(state.copyWith(
            status: NearbyGroupBlocStatus.created,
            myActiveGroup: group,
            selectedGroup: group,
          ));
          
          // Use a slight delay before starting scanning to allow navigation
          Future.delayed(const Duration(milliseconds: 500), () {
            add(StartGroupScanning(
              groupId: group.id,
              creatorId: event.creatorId,
              creatorUsername: event.creatorUsername,
            ));
          });
          
        case NearbyGroupFailure(message: final msg, type: final type):
          _logger.w('Failed to create nearby group: $msg ($type)');
          emit(state.copyWith(
            status: NearbyGroupBlocStatus.error,
            errorMessage: msg,
          ));
      }
    } catch (e) {
      _logger.e('Exception during group creation', error: e);
      emit(state.copyWith(
        status: NearbyGroupBlocStatus.error,
        errorMessage: 'Failed to create group: $e',
      ));
    }
  }

  Future<void> _onCloseNearbyGroup(
    CloseNearbyGroup event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Closing and deleting nearby group: ${event.groupId}');

    // Stop scanning first using shared cleanup
    await _cleanupScanning();

    try {
      // Delete the group entirely (not just mark inactive)
      await _groupService.deleteGroup(
        groupId: event.groupId,
        userId: event.userId,
      );

      emit(state.copyWith(
        status: NearbyGroupBlocStatus.loaded,
        clearMyActiveGroup: true,
        clearSelectedGroup: true,
        groupMembers: const [],
        isScanning: false,
      ));

      _logger.i('Deleted nearby group: ${event.groupId}');
    } catch (e) {
      _logger.e('Failed to delete group', error: e);
      emit(state.copyWith(
        status: NearbyGroupBlocStatus.error,
        errorMessage: 'Failed to delete group: $e',
        isScanning: false,
      ));
    }
  }

  /// Shared cleanup method for stopping scanning and subscriptions.
  Future<void> _cleanupScanning() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;
    _isScanningPhase = false;

    await _proximityService.stopScan();
    await _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = null;
    await _proximityStateSubscription?.cancel();
    _proximityStateSubscription = null;
    await _membersSubscription?.cancel();
    _membersSubscription = null;

    _currentGroupId = null;
    _currentCreatorId = null;
  }

  Future<void> _onStartGroupScanning(
    StartGroupScanning event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Starting group scanning for: ${event.groupId}');

    _currentGroupId = event.groupId;
    _currentCreatorId = event.creatorId;

    // Subscribe to group members
    await _membersSubscription?.cancel();
    _membersSubscription =
        _groupService.watchGroupMembers(event.groupId).listen(
      (members) => add(_GroupMembersReceived(members)),
      onError: (error) => add(_NearbyGroupStreamError(error.toString())),
    );

    // Subscribe to nearby users from Bluetooth
    await _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = _proximityService.nearbyUsersStream.listen(
      (users) => add(_NearbyUsersDetected(users)),
    );

    // Listen to scan completion for cycling
    await _proximityStateSubscription?.cancel();
    _proximityStateSubscription = _proximityService.stateStream.listen((proximityState) {
      if (proximityState == ProximityServiceState.scanComplete && _isScanningPhase) {
        add(const _ScanCycleComplete());
      }
    });

    // Start heartbeat timer
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_currentGroupId != null && _currentCreatorId != null) {
        _groupService.heartbeat(
          groupId: _currentGroupId!,
          creatorId: _currentCreatorId!,
        );
      }
    });

    emit(state.copyWith(
      status: NearbyGroupBlocStatus.scanning,
      isScanning: true,
    ));

    // Start the first scan cycle
    await _startScanCycle();
  }

  /// Starts a single 10-second scan cycle
  Future<void> _startScanCycle() async {
    if (_currentGroupId == null || _currentCreatorId == null) return;

    _logger.d('Starting 10-second scan cycle');
    _isScanningPhase = true;
    
    final started = await _proximityService.startScan(duration: scanDuration);
    if (!started) {
      _logger.w('Failed to start scan, will retry after cooldown');
      // Schedule retry after cooldown
      _scanCycleTimer?.cancel();
      _scanCycleTimer = Timer(scanCooldown, () {
        if (_currentGroupId != null) {
          _startScanCycle();
        }
      });
    }
  }

  /// Called when a scan cycle completes - schedules next cycle after cooldown
  Future<void> _onScanCycleComplete(
    _ScanCycleComplete event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Scan cycle complete, cooling down for ${scanCooldown.inSeconds}s');
    _isScanningPhase = false;

    // Schedule next scan after cooldown
    _scanCycleTimer?.cancel();
    _scanCycleTimer = Timer(scanCooldown, () {
      if (_currentGroupId != null && _currentCreatorId != null) {
        _startScanCycle();
      }
    });
  }

  Future<void> _onStopGroupScanning(
    StopGroupScanning event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Stopping group scanning');

    await _cleanupScanning();

    emit(state.copyWith(isScanning: false));
  }

  Future<void> _onLoadNearbyGroupDetails(
    LoadNearbyGroupDetails event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Loading nearby group details: ${event.groupId}');

    emit(state.copyWith(status: NearbyGroupBlocStatus.loading));

    try {
      final group = await _groupService.getGroup(event.groupId);
      if (group != null) {
        emit(state.copyWith(
          status: NearbyGroupBlocStatus.loaded,
          selectedGroup: group,
        ));

        // Start watching members
        await _membersSubscription?.cancel();
        _membersSubscription =
            _groupService.watchGroupMembers(event.groupId).listen(
          (members) => add(_GroupMembersReceived(members)),
          onError: (error) => add(_NearbyGroupStreamError(error.toString())),
        );
      } else {
        emit(state.copyWith(
          status: NearbyGroupBlocStatus.error,
          errorMessage: 'Group not found',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: NearbyGroupBlocStatus.error,
        errorMessage: 'Failed to load group: $e',
      ));
    }
  }

  Future<void> _onLoadUserActiveGroup(
    LoadUserActiveGroup event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Loading user active group for: ${event.userId}');

    try {
      final activeGroup = await _groupService.getUserActiveGroup(event.userId);
      if (activeGroup != null) {
        _logger.i('Found user active group: ${activeGroup.id}');
        emit(state.copyWith(
          myActiveGroup: activeGroup,
          status: NearbyGroupBlocStatus.loaded,
        ));
      } else {
        _logger.d('No active group found for user');
      }
    } catch (e) {
      _logger.e('Failed to load user active group', error: e);
      // Don't emit error state - this is a non-critical operation
    }
  }

  void _onActiveGroupsReceived(
    _ActiveGroupsReceived event,
    Emitter<NearbyGroupState> emit,
  ) {
    _logger.d('Received ${event.groups.length} active nearby groups');
    emit(state.copyWith(
      status: NearbyGroupBlocStatus.loaded,
      activeGroups: event.groups,
    ));
  }

  void _onUserGroupsReceived(
    _UserGroupsReceived event,
    Emitter<NearbyGroupState> emit,
  ) {
    _logger.d('Received ${event.groups.length} user nearby groups');
    emit(state.copyWith(
      userGroups: event.groups,
      status: NearbyGroupBlocStatus.loaded,
    ));
  }

  void _onGroupMembersReceived(
    _GroupMembersReceived event,
    Emitter<NearbyGroupState> emit,
  ) {
    _logger.d('Received ${event.members.length} group members');
    emit(state.copyWith(groupMembers: event.members));
  }

  Future<void> _onNearbyUsersDetected(
    _NearbyUsersDetected event,
    Emitter<NearbyGroupState> emit,
  ) async {
    if (_currentGroupId == null || _currentCreatorId == null) return;

    _logger.d('Detected ${event.users.length} nearby users for group');

    // Update members in the database
    await _groupService.updateNearbyMembers(
      groupId: _currentGroupId!,
      creatorId: _currentCreatorId!,
      nearbyUsers: event.users,
    );
  }

  void _onNearbyGroupStreamError(
    _NearbyGroupStreamError event,
    Emitter<NearbyGroupState> emit,
  ) {
    _logger.e('Nearby group stream error: ${event.error}');
    emit(state.copyWith(
      status: NearbyGroupBlocStatus.error,
      errorMessage: event.error,
    ));
  }

  /// Handler for resetting the BLoC state when switching accounts.
  /// Cancels all subscriptions and clears state to prevent permission errors.
  Future<void> _onResetNearbyGroupState(
    ResetNearbyGroupState event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Resetting nearby group state (account switch or cleanup)');

    // Cancel all active subscriptions
    await _cleanupAllSubscriptions();

    // Reset state to initial empty state
    emit(const NearbyGroupState());
  }

  Future<void> _onForceRefreshNearbyGroups(
    ForceRefreshNearbyGroups event,
    Emitter<NearbyGroupState> emit,
  ) async {
    _logger.d('Force refreshing nearby groups');

    // Cancel existing subscriptions to force re-subscribe
    await _activeGroupsSubscription?.cancel();
    _activeGroupsSubscription = null;

    if (event.userId != null) {
      await _userGroupsSubscription?.cancel();
      _userGroupsSubscription = null;
    }

    // Re-dispatch watch events which will now start fresh subscriptions
    add(const WatchActiveNearbyGroups());
    if (event.userId != null) {
      add(WatchUserNearbyGroups(event.userId!));
      add(LoadUserActiveGroup(event.userId!));
    }
  }

  /// Clean up all active subscriptions and timers.
  Future<void> _cleanupAllSubscriptions() async {
    // Cancel timers
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;

    // Cancel stream subscriptions
    await _activeGroupsSubscription?.cancel();
    _activeGroupsSubscription = null;
    
    await _userGroupsSubscription?.cancel();
    _userGroupsSubscription = null;
    
    await _membersSubscription?.cancel();
    _membersSubscription = null;
    
    await _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = null;
    
    await _proximityStateSubscription?.cancel();
    _proximityStateSubscription = null;

    // Clear scanning state
    _isScanningPhase = false;
    _currentGroupId = null;
    _currentCreatorId = null;
  }

  /// Directly cancels all Firestore stream subscriptions.
  ///
  /// Unlike [ResetNearbyGroupState] (which goes through the async event queue),
  /// this method cancels subscriptions immediately and can be awaited.
  /// Use this during sign-out to prevent PERMISSION_DENIED errors.
  Future<void> cancelSubscriptions() => _cleanupAllSubscriptions();

  @override
  Future<void> close() async {
    await _cleanupAllSubscriptions();
    return super.close();
  }
}
