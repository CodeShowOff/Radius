import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/bluetooth/ble_device.dart';
import '../../domain/entities/nearby_user.dart';
import '../../proximity_service.dart';

part 'nearby_users_event.dart';
part 'nearby_users_state.dart';

/// BLoC for managing nearby users state.
class NearbyUsersBloc extends Bloc<NearbyUsersEvent, NearbyUsersState> {
  final ProximityService _proximityService;

  /// Duration to wait before showing "no one nearby" message.
  static const Duration _initialSearchTimeout = Duration(seconds: 10);

  StreamSubscription<List<NearbyUser>>? _nearbyUsersSubscription;
  StreamSubscription<ProximityServiceState>? _serviceStateSubscription;
  Timer? _initialSearchTimer;
  bool _hasFoundUsers = false;

  NearbyUsersBloc({required ProximityService proximityService})
      : _proximityService = proximityService,
        super(const NearbyUsersState()) {
    on<NearbyUsersStartDiscovery>(_onStartDiscovery);
    on<NearbyUsersStopDiscovery>(_onStopDiscovery);
    on<NearbyUsersUpdated>(_onUsersUpdated);
    on<NearbyUsersServiceStateChanged>(_onServiceStateChanged);
    on<NearbyUsersFilterChanged>(_onFilterChanged);
    on<NearbyUsersRefresh>(_onRefresh);
    on<NearbyUsersInitialSearchTimeout>(_onInitialSearchTimeout);
  }

  Future<void> _onStartDiscovery(
    NearbyUsersStartDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
    emit(state.copyWith(status: NearbyUsersStatus.loading, errorMessage: null));

    // Check current service state
    final currentServiceState = _proximityService.state;
    final isInErrorState = currentServiceState == ProximityServiceState.error;
    final needsInit =
        currentServiceState == ProximityServiceState.idle || isInErrorState;

    // Reset service if in error state to allow fresh initialization
    if (isInErrorState) {
      _proximityService.reset();
    }

    // Initialize proximity service if needed
    if (needsInit) {
      final initialized = await _proximityService.initialize(
        event.userId,
        forceReinit: isInErrorState,
      );
      if (!initialized) {
        // Get the actual error from the service's lastError property
        final errorMessage = _proximityService.lastError ??
            'Failed to initialize proximity service';

        emit(state.copyWith(
          status: NearbyUsersStatus.error,
          errorMessage: errorMessage,
        ));
        return;
      }
    }

    // Subscribe to nearby users stream
    _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = _proximityService.nearbyUsersStream.listen(
      (users) => add(NearbyUsersUpdated(users)),
    );

    // Subscribe to service state
    _serviceStateSubscription?.cancel();
    _serviceStateSubscription = _proximityService.stateStream.listen(
      (serviceState) => add(NearbyUsersServiceStateChanged(serviceState)),
    );

    // Start discovery
    final started = await _proximityService.startDiscovery();
    if (!started) {
      // Get the actual error from the service's lastError property
      final errorMessage = _proximityService.lastError ??
          'Failed to start discovery. Check Bluetooth and location permissions.';

      emit(state.copyWith(
        status: NearbyUsersStatus.error,
        errorMessage: errorMessage,
      ));
      return;
    }

    // Reset tracking flags and start the initial search timer
    _hasFoundUsers = false;
    _initialSearchTimer?.cancel();
    _initialSearchTimer = Timer(_initialSearchTimeout, () {
      if (!_hasFoundUsers) {
        add(const NearbyUsersInitialSearchTimeout());
      }
    });

    emit(state.copyWith(
      status: NearbyUsersStatus.discovering,
      isDiscovering: true,
    ));
  }

  Future<void> _onStopDiscovery(
    NearbyUsersStopDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
    _initialSearchTimer?.cancel();
    await _proximityService.stopDiscovery();
    emit(state.copyWith(
      status: NearbyUsersStatus.idle,
      isDiscovering: false,
    ));
  }

  void _onUsersUpdated(
    NearbyUsersUpdated event,
    Emitter<NearbyUsersState> emit,
  ) {
    final filteredUsers = _applyFilter(event.users, state.filter);

    // Track if we've found any users - cancel the timeout timer
    if (event.users.isNotEmpty) {
      _hasFoundUsers = true;
      _initialSearchTimer?.cancel();
    }

    emit(state.copyWith(
      status: filteredUsers.isEmpty && state.isDiscovering
          ? NearbyUsersStatus.empty
          : NearbyUsersStatus.discovering,
      users: event.users,
      filteredUsers: filteredUsers,
    ));
  }

  void _onInitialSearchTimeout(
    NearbyUsersInitialSearchTimeout event,
    Emitter<NearbyUsersState> emit,
  ) {
    // Only change state if still discovering and no users found
    if (state.isDiscovering && state.users.isEmpty) {
      emit(state.copyWith(
        status: NearbyUsersStatus.empty,
        isDiscovering: false, // Stop showing "searching" animation
      ));
    }
  }

  void _onServiceStateChanged(
    NearbyUsersServiceStateChanged event,
    Emitter<NearbyUsersState> emit,
  ) {
    switch (event.serviceState) {
      case ProximityServiceState.idle:
        emit(state.copyWith(
          status: NearbyUsersStatus.idle,
          isDiscovering: false,
        ));
        break;
      case ProximityServiceState.discovering:
        emit(state.copyWith(
          status: state.users.isEmpty
              ? NearbyUsersStatus.empty
              : NearbyUsersStatus.discovering,
          isDiscovering: true,
        ));
        break;
      case ProximityServiceState.error:
        emit(state.copyWith(
          status: NearbyUsersStatus.error,
          errorMessage: 'Proximity service error',
        ));
        break;
      default:
        break;
    }
  }

  void _onFilterChanged(
    NearbyUsersFilterChanged event,
    Emitter<NearbyUsersState> emit,
  ) {
    final filteredUsers = _applyFilter(state.users, event.filter);
    emit(state.copyWith(
      filter: event.filter,
      filteredUsers: filteredUsers,
    ));
  }

  Future<void> _onRefresh(
    NearbyUsersRefresh event,
    Emitter<NearbyUsersState> emit,
  ) async {
    // Reset search state
    _hasFoundUsers = false;
    _initialSearchTimer?.cancel();

    emit(state.copyWith(
      status: NearbyUsersStatus.discovering,
      isDiscovering: true,
    ));

    // Clear and restart discovery
    await _proximityService.stopDiscovery();
    await Future.delayed(const Duration(milliseconds: 500));

    final started = await _proximityService.startDiscovery();
    if (!started) {
      final errorMessage = _proximityService.lastError ??
          'Failed to restart discovery. Check Bluetooth and permissions.';
      emit(state.copyWith(
        status: NearbyUsersStatus.error,
        errorMessage: errorMessage,
        isDiscovering: false,
      ));
      return;
    }

    // Start new timeout timer
    _initialSearchTimer = Timer(_initialSearchTimeout, () {
      if (!_hasFoundUsers) {
        add(const NearbyUsersInitialSearchTimeout());
      }
    });
  }

  List<NearbyUser> _applyFilter(
    List<NearbyUser> users,
    NearbyUsersFilter filter,
  ) {
    switch (filter) {
      case NearbyUsersFilter.all:
        return users;
      case NearbyUsersFilter.close:
        return users
            .where((u) => u.proximity == BleProximity.immediate)
            .toList();
      case NearbyUsersFilter.nearby:
        return users
            .where((u) =>
                u.proximity == BleProximity.immediate ||
                u.proximity == BleProximity.near)
            .toList();
    }
  }

  @override
  Future<void> close() {
    _nearbyUsersSubscription?.cancel();
    _serviceStateSubscription?.cancel();
    _initialSearchTimer?.cancel();
    return super.close();
  }
}
