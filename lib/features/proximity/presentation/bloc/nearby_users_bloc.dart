import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/bluetooth/ble_device.dart';
import '../../../../core/services/bluetooth/ble_range_mode.dart';
import '../../domain/entities/nearby_user.dart';
import '../../proximity_service.dart';

part 'nearby_users_event.dart';
part 'nearby_users_state.dart';

/// BLoC for managing nearby users state.
class NearbyUsersBloc extends Bloc<NearbyUsersEvent, NearbyUsersState> {
  final ProximityService _proximityService;

  /// Duration to wait before showing a "no one nearby yet" hint.
  /// Discovery continues in foreground; this only affects UI messaging.
  static const Duration _initialSearchTimeout = Duration(seconds: 15);

  StreamSubscription<List<NearbyUser>>? _nearbyUsersSubscription;
  StreamSubscription<ProximityServiceState>? _serviceStateSubscription;
  Timer? _initialSearchTimer;
  Timer? _bleDiagnosticsTimer;
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
    on<NearbyUsersBleDiagnosticsTick>(_onBleDiagnosticsTick);
    on<NearbyUsersScanOnceRequested>(_onScanOnceRequested);
    on<NearbyUsersScanOnceCompleted>(_onScanOnceCompleted);
  }

  void _startBleDiagnosticsTimer() {
    _bleDiagnosticsTimer?.cancel();
    _bleDiagnosticsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const NearbyUsersBleDiagnosticsTick()),
    );
  }

  void _stopBleDiagnosticsTimer() {
    _bleDiagnosticsTimer?.cancel();
    _bleDiagnosticsTimer = null;
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

    // Remember the last initialized user for subsequent explicit scan requests.
    // (Nearby no longer auto-scans.)
    _lastInitializedUserId = event.userId;

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

    // IMPORTANT: opening Nearby should not start scanning automatically.
    emit(state.copyWith(
      status: NearbyUsersStatus.idle,
      isDiscovering: false,
      searchTimedOut: false,
      clearErrorMessage: true,
    ));
  }

  Future<void> _onScanOnceRequested(
    NearbyUsersScanOnceRequested event,
    Emitter<NearbyUsersState> emit,
  ) async {
    _lastInitializedUserId = event.userId;

    // Ensure the service is initialized and streams are wired.
    final currentServiceState = _proximityService.state;
    final isInErrorState = currentServiceState == ProximityServiceState.error;
    final needsInit =
        currentServiceState == ProximityServiceState.idle || isInErrorState;

    if (isInErrorState) {
      _proximityService.reset();
    }

    if (needsInit) {
      final initialized = await _proximityService.initialize(
        event.userId,
        forceReinit: isInErrorState,
      );
      if (!initialized) {
        emit(state.copyWith(
          status: NearbyUsersStatus.error,
          errorMessage:
              _proximityService.lastError ?? 'Failed to initialize Bluetooth',
          isDiscovering: false,
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

    _hasFoundUsers = false;
    _initialSearchTimer?.cancel();
    _stopBleDiagnosticsTimer();

    emit(state.copyWith(
      status: NearbyUsersStatus.discovering,
      isDiscovering: true,
      searchTimedOut: false,
      rangeMode: event.rangeMode,
      clearErrorMessage: true,
    ));

    // UI hint if nothing is found partway through.
    _initialSearchTimer = Timer(_initialSearchTimeout, () {
      if (!_hasFoundUsers) {
        add(const NearbyUsersInitialSearchTimeout());
      }
    });

    _startBleDiagnosticsTimer();

    // IMPORTANT: do not await the whole scan duration here.
    // If we await, the bloc can't process NearbyUsersUpdated events during the scan,
    // making it appear like discovery "never finds" anything until the scan ends.
    // Run scanOnce asynchronously and update UI via NearbyUsersScanOnceCompleted.
    unawaited(
      _proximityService
          .scanOnce(
            event.userId,
            rangeMode: event.rangeMode,
            duration: const Duration(seconds: 15),
          )
          .then((ok) => add(NearbyUsersScanOnceCompleted(ok))),
    );
  }

  void _onScanOnceCompleted(
    NearbyUsersScanOnceCompleted event,
    Emitter<NearbyUsersState> emit,
  ) {
    _stopBleDiagnosticsTimer();
    _initialSearchTimer?.cancel();

    if (!event.ok) {
      emit(state.copyWith(
        status: NearbyUsersStatus.error,
        errorMessage: _proximityService.lastError ?? 'Scan failed',
        isDiscovering: false,
      ));
      return;
    }

    final hasUsers = state.users.isNotEmpty;
    emit(state.copyWith(
      status:
          hasUsers ? NearbyUsersStatus.discovering : NearbyUsersStatus.empty,
      isDiscovering: false,
      searchTimedOut: !hasUsers,
    ));
  }

  String? _lastInitializedUserId;

  Future<void> _onStopDiscovery(
    NearbyUsersStopDiscovery event,
    Emitter<NearbyUsersState> emit,
  ) async {
    _initialSearchTimer?.cancel();
    _stopBleDiagnosticsTimer();
    await _proximityService.stopDiscovery();

    emit(state.copyWith(
      // Keep last scan results; just stop the scanning indicator.
      status: state.users.isEmpty
          ? NearbyUsersStatus.idle
          : NearbyUsersStatus.discovering,
      isDiscovering: false,
      clearBleDebugInfo: true,
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
      searchTimedOut: state.searchTimedOut && event.users.isEmpty,
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
        // Keep discovery active; just switch messaging to "no one nearby yet".
        isDiscovering: true,
        searchTimedOut: true,
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
          status: state.users.isEmpty
              ? NearbyUsersStatus.idle
              : NearbyUsersStatus.discovering,
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
    // Refresh is now equivalent to an explicit scan request.
    final userId = _lastInitializedUserId;
    if (userId == null || userId.isEmpty) return;
    add(NearbyUsersScanOnceRequested(
      userId: userId,
      rangeMode: event.rangeMode ?? state.rangeMode,
    ));
  }

  void _onBleDiagnosticsTick(
    NearbyUsersBleDiagnosticsTick event,
    Emitter<NearbyUsersState> emit,
  ) {
    final d = _proximityService.bleDiagnostics;
    emit(state.copyWith(
      bleDebugInfo: BleDebugInfo(
        isScanning: d.isScanning,
        isAdvertising: d.isAdvertising,
        lastError: d.lastError,
        rawScanResults: d.rawScanResultCount,
        parsedRadiusDevices: d.parsedRadiusCount,
        filteredOut:
            (d.rawScanResultCount - d.parsedRadiusCount).clamp(0, 1 << 30),
      ),
    ));
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
    _stopBleDiagnosticsTimer();
    return super.close();
  }
}
