import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/nearby_user.dart';
import '../../proximity_service.dart';

part 'nearby_users_event.dart';
part 'nearby_users_state.dart';

/// BLoC for managing nearby users discovery.
///
/// Real-time discovery flow:
/// 1. User clicks "Start Scan" → status becomes "scanning"
/// 2. As soon as first user is discovered → switches to "results" and shows them immediately
/// 3. More users keep appearing in the list as they're discovered (live updates)
/// 4. After 10 seconds, scan stops automatically but results remain visible
/// 
/// Advertising runs continuously while app is open.
class NearbyUsersBloc extends Bloc<NearbyUsersEvent, NearbyUsersState> {
  final ProximityService _proximityService;

  StreamSubscription<List<NearbyUser>>? _nearbyUsersSubscription;
  StreamSubscription<ProximityServiceState>? _serviceStateSubscription;
  String? _currentUserId;
  String? _currentUsername;
  bool _isInitialized = false;

  NearbyUsersBloc({required ProximityService proximityService})
      : _proximityService = proximityService,
        super(const NearbyUsersState()) {
    on<NearbyUsersInitialize>(_onInitialize);
    on<NearbyUsersStartScan>(_onStartScan);
    on<NearbyUsersStopScan>(_onStopScan);
    on<NearbyUsersUpdated>(_onUsersUpdated);
    on<NearbyUsersServiceStateChanged>(_onServiceStateChanged);
    on<NearbyUsersClearResults>(_onClearResults);
    on<NearbyUsersAppBackgrounded>(_onAppBackgrounded);
    on<NearbyUsersAppResumed>(_onAppResumed);
    // Legacy events for compatibility
    on<NearbyUsersStartDiscovery>(_onStartDiscoveryLegacy);
    on<NearbyUsersStopDiscovery>(_onStopDiscoveryLegacy);
    on<NearbyUsersRefresh>(_onRefresh);
    on<NearbyUsersFilterChanged>(_onFilterChanged);
    on<NearbyUsersInitialSearchTimeout>(_onInitialSearchTimeout);
  }

  /// Initialize the service (starts advertising).
  Future<void> _onInitialize(
    NearbyUsersInitialize event,
    Emitter<NearbyUsersState> emit,
  ) async {
    if (_isInitialized) return;

    _currentUserId = event.userId;
    _currentUsername = event.username;

    emit(state.copyWith(status: NearbyUsersStatus.loading));

    // Initialize proximity service (starts advertising)
    final initialized = await _proximityService.initialize(
      event.userId,
      event.username,
    );

    if (!initialized) {
      emit(state.copyWith(
        status: NearbyUsersStatus.error,
        errorMessage:
            _proximityService.lastError ?? 'Failed to initialize proximity',
      ));
      return;
    }

    _isInitialized = true;

    // Subscribe to nearby users stream
    _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = _proximityService.nearbyUsersStream.listen(
      (users) {
        if (!isClosed) {
          add(NearbyUsersUpdated(users));
        }
      },
    );

    // Subscribe to service state
    _serviceStateSubscription?.cancel();
    _serviceStateSubscription = _proximityService.stateStream.listen(
      (serviceState) {
        if (!isClosed) {
          add(NearbyUsersServiceStateChanged(serviceState));
        }
      },
    );

    emit(state.copyWith(
      status: NearbyUsersStatus.idle,
      isAdvertising: true,
      clearErrorMessage: true,
    ));
  }

  /// Start a scan for nearby users.
  /// [duration] can be specified for custom scan lengths.
  Future<void> _onStartScan(
    NearbyUsersStartScan event,
    Emitter<NearbyUsersState> emit,
  ) async {
    if (!_isInitialized && _currentUserId != null && _currentUsername != null) {
      // Initialize first if needed
      await _onInitialize(
        NearbyUsersInitialize(
          userId: _currentUserId!,
          username: _currentUsername!,
        ),
        emit,
      );
    }

    emit(state.copyWith(
      status: NearbyUsersStatus.scanning,
      isScanning: true,
      clearErrorMessage: true,
    ));

    final started = await _proximityService.startScan(duration: event.duration);
    if (!started) {
      emit(state.copyWith(
        status: NearbyUsersStatus.error,
        isScanning: false,
        errorMessage: _proximityService.lastError ?? 'Failed to start scan',
      ));
    }
  }

  /// Stop scanning manually.
  Future<void> _onStopScan(
    NearbyUsersStopScan event,
    Emitter<NearbyUsersState> emit,
  ) async {
    await _proximityService.stopScan();
    // State will be updated via service state subscription
  }

  /// Handle nearby users updates - shows results immediately as they're discovered.
  void _onUsersUpdated(
    NearbyUsersUpdated event,
    Emitter<NearbyUsersState> emit,
  ) {
    // If we're scanning and found users, switch to results status to show them immediately
    // This provides real-time discovery UX instead of waiting for scan to complete
    NearbyUsersStatus newStatus = state.status;
    if (state.isScanning && event.users.isNotEmpty) {
      newStatus = NearbyUsersStatus.results;
    } else if (state.isScanning && event.users.isEmpty) {
      // Still scanning but no users yet - keep scanning status
      newStatus = NearbyUsersStatus.scanning;
    }
    
    emit(state.copyWith(
      users: event.users,
      status: newStatus,
    ));
  }

  /// Handle service state changes.
  void _onServiceStateChanged(
    NearbyUsersServiceStateChanged event,
    Emitter<NearbyUsersState> emit,
  ) {
    switch (event.serviceState) {
      case ProximityServiceState.idle:
        emit(state.copyWith(
          status: NearbyUsersStatus.idle,
          isScanning: false,
        ));
        break;
      case ProximityServiceState.scanning:
        emit(state.copyWith(
          status: NearbyUsersStatus.scanning,
          isScanning: true,
        ));
        break;
      case ProximityServiceState.scanComplete:
        emit(state.copyWith(
          status: state.users.isEmpty
              ? NearbyUsersStatus.empty
              : NearbyUsersStatus.results,
          isScanning: false,
        ));
        break;
      case ProximityServiceState.error:
        emit(state.copyWith(
          status: NearbyUsersStatus.error,
          isScanning: false,
          errorMessage: _proximityService.lastError ?? 'An error occurred',
        ));
        break;
    }
  }

  /// Clear scan results.
  void _onClearResults(
    NearbyUsersClearResults event,
    Emitter<NearbyUsersState> emit,
  ) {
    _proximityService.clearNearbyUsers();
    emit(state.copyWith(
      status: NearbyUsersStatus.idle,
      users: [],
    ));
  }

  /// Handle app going to background - stop scanning.
  Future<void> _onAppBackgrounded(
    NearbyUsersAppBackgrounded event,
    Emitter<NearbyUsersState> emit,
  ) async {
    // Stop scanning when app goes to background
    if (state.isScanning) {
      await _proximityService.stopScan();
    }
    // Note: Advertising continues for receiving requests
  }

  /// Handle app resuming.
  Future<void> _onAppResumed(
    NearbyUsersAppResumed event,
    Emitter<NearbyUsersState> emit,
  ) async {
    // Restart advertising if needed
    await _proximityService.restartAdvertising();
    emit(state.copyWith(isAdvertising: _proximityService.isAdvertising));
  }

  // ============== Legacy Event Handlers ==============

  Future<void> _onStartDiscoveryLegacy(
    NearbyUsersStartDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
    _currentUserId = event.userId;
    _currentUsername = event.username;

    if (!_isInitialized) {
      await _onInitialize(
        NearbyUsersInitialize(
          userId: event.userId,
          username: event.username,
        ),
        emit,
      );
    }
    await _onStartScan(const NearbyUsersStartScan(), emit);
  }

  Future<void> _onStopDiscoveryLegacy(
    NearbyUsersStopDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
    await _onStopScan(const NearbyUsersStopScan(), emit);
  }

  Future<void> _onRefresh(
    NearbyUsersRefresh event,
    Emitter<NearbyUsersState> emit,
  ) async {
    _proximityService.clearProfileCache();
    _proximityService.clearNearbyUsers();
    await _onStartScan(const NearbyUsersStartScan(), emit);
  }

  void _onFilterChanged(
    NearbyUsersFilterChanged event,
    Emitter<NearbyUsersState> emit,
  ) {
    // Filters removed - kept for compatibility but no-op
  }

  void _onInitialSearchTimeout(
    NearbyUsersInitialSearchTimeout event,
    Emitter<NearbyUsersState> emit,
  ) {
    // No longer needed - scan auto-stops after 15s
  }

  @override
  Future<void> close() {
    _nearbyUsersSubscription?.cancel();
    _serviceStateSubscription?.cancel();
    return super.close();
  }
}
