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

  StreamSubscription<List<NearbyUser>>? _nearbyUsersSubscription;
  StreamSubscription<ProximityServiceState>? _serviceStateSubscription;

  NearbyUsersBloc({required ProximityService proximityService})
      : _proximityService = proximityService,
        super(const NearbyUsersState()) {
    on<NearbyUsersStartDiscovery>(_onStartDiscovery);
    on<NearbyUsersStopDiscovery>(_onStopDiscovery);
    on<NearbyUsersUpdated>(_onUsersUpdated);
    on<NearbyUsersServiceStateChanged>(_onServiceStateChanged);
    on<NearbyUsersFilterChanged>(_onFilterChanged);
    on<NearbyUsersRefresh>(_onRefresh);
  }

  Future<void> _onStartDiscovery(
    NearbyUsersStartDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
    emit(state.copyWith(status: NearbyUsersStatus.loading));

    // Initialize proximity service if needed
    if (_proximityService.state == ProximityServiceState.idle) {
      final initialized = await _proximityService.initialize(event.userId);
      if (!initialized) {
        emit(state.copyWith(
          status: NearbyUsersStatus.error,
          errorMessage: 'Failed to initialize proximity service',
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
      emit(state.copyWith(
        status: NearbyUsersStatus.error,
        errorMessage: 'Failed to start discovery. Check Bluetooth permissions.',
      ));
      return;
    }

    emit(state.copyWith(
      status: NearbyUsersStatus.discovering,
      isDiscovering: true,
    ));
  }

  Future<void> _onStopDiscovery(
    NearbyUsersStopDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
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

    emit(state.copyWith(
      status: filteredUsers.isEmpty && state.isDiscovering
          ? NearbyUsersStatus.empty
          : NearbyUsersStatus.discovering,
      users: event.users,
      filteredUsers: filteredUsers,
    ));
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
    // Clear and restart discovery
    await _proximityService.stopDiscovery();
    await Future.delayed(const Duration(milliseconds: 500));
    await _proximityService.startDiscovery();
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
    return super.close();
  }
}
