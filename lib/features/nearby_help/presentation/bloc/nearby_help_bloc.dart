import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/nearby_help_service.dart';
import '../../data/user_location_service.dart';
import '../../domain/entities/help_radius.dart';
import '../../domain/entities/help_request.dart';
import '../../domain/entities/user_location.dart';

part 'nearby_help_event.dart';
part 'nearby_help_state.dart';

/// BLoC for managing the Nearby Help feature.
///
/// Handles:
/// - User location management (home/work)
/// - Help request creation and management
/// - Helper acceptance flow
/// - Real-time status updates
/// - Incoming help requests from others
class NearbyHelpBloc extends Bloc<NearbyHelpEvent, NearbyHelpState> {
  final NearbyHelpService _helpService;
  final UserLocationService _locationService;
  final Logger _logger = Logger();

  StreamSubscription<List<UserLocation>>? _locationsSubscription;
  StreamSubscription<NearbyHelpSettings>? _settingsSubscription;
  StreamSubscription<List<HelpRequest>>? _seekerRequestsSubscription;
  StreamSubscription<List<HelpRequest>>? _helperRequestsSubscription;
  StreamSubscription<HelpRequest?>? _viewedRequestSubscription;
  StreamSubscription<List<HelpRequest>>? _incomingRequestsSubscription;
  
  /// Track the currently initialized user to prevent duplicate initialization
  String? _initializedUserId;

  NearbyHelpBloc({
    required NearbyHelpService helpService,
    required UserLocationService locationService,
  })  : _helpService = helpService,
        _locationService = locationService,
        super(const NearbyHelpState()) {
    on<NearbyHelpInitialize>(_onInitialize);
    on<NearbyHelpLoadLocations>(_onLoadLocations);
    on<NearbyHelpSaveLocation>(_onSaveLocation);
    on<NearbyHelpDeleteLocation>(_onDeleteLocation);
    on<NearbyHelpToggleLocation>(_onToggleLocation);
    on<NearbyHelpUpdateSettings>(_onUpdateSettings);
    on<NearbyHelpCreateRequest>(_onCreateRequest);
    on<NearbyHelpCancelRequest>(_onCancelRequest);
    on<NearbyHelpAcceptRequest>(_onAcceptRequest);
    on<NearbyHelpMarkOnTheWay>(_onMarkOnTheWay);
    on<NearbyHelpMarkCompleted>(_onMarkCompleted);
    on<NearbyHelpLoadRequest>(_onLoadRequest);
    on<NearbyHelpSubscribeToRequest>(_onSubscribeToRequest);
    on<NearbyHelpUnsubscribeFromRequest>(_onUnsubscribeFromRequest);
    on<NearbyHelpClearMessages>(_onClearMessages);
    on<NearbyHelpWatchIncomingRequests>(_onWatchIncomingRequests);
    on<NearbyHelpStopWatchingIncomingRequests>(_onStopWatchingIncomingRequests);
    on<_LocationsUpdated>(_onLocationsUpdated);
    on<_SettingsUpdated>(_onSettingsUpdated);
    on<_ActiveRequestUpdated>(_onActiveRequestUpdated);
    on<_ViewedRequestUpdated>(_onViewedRequestUpdated);
    on<_HelperRequestsUpdated>(_onHelperRequestsUpdated);
    on<_IncomingRequestsUpdated>(_onIncomingRequestsUpdated);
  }

  Future<void> _onInitialize(
    NearbyHelpInitialize event,
    Emitter<NearbyHelpState> emit,
  ) async {
    // Skip if already initialized for the same user
    if (_initializedUserId == event.userId && state.status != NearbyHelpStatus.initial) {
      return;
    }
    
    _initializedUserId = event.userId;
    
    emit(state.copyWith(
      status: NearbyHelpStatus.loading,
      userId: event.userId,
      userName: event.userName,
      userPhotoUrl: event.userPhotoUrl,
    ));

    // Cancel existing subscriptions
    await _cancelSubscriptions();

    // Subscribe to locations
    _locationsSubscription = _locationService
        .streamLocations(event.userId)
        .listen((locations) {
      if (!isClosed) add(_LocationsUpdated(locations));
    });

    // Subscribe to settings
    _settingsSubscription = _locationService
        .streamHelpSettings(event.userId)
        .listen((settings) {
      if (!isClosed) add(_SettingsUpdated(settings));
    });

    // Subscribe to seeker requests
    _seekerRequestsSubscription = _helpService
        .streamSeekerRequests(event.userId)
        .listen((requests) {
      if (!isClosed) {
        add(_ActiveRequestUpdated(requests.isNotEmpty ? requests.first : null));
      }
    });

    // Subscribe to helper requests
    _helperRequestsSubscription = _helpService
        .streamHelperRequests(event.userId)
        .listen((requests) {
      if (!isClosed) {
        add(_HelperRequestsUpdated(requests));
      }
    });

    emit(state.copyWith(status: NearbyHelpStatus.loaded));
  }

  Future<void> _onLoadLocations(
    NearbyHelpLoadLocations event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.loading));

    try {
      final locations = await _locationService.getLocations(state.userId!);
      emit(state.copyWith(
        status: NearbyHelpStatus.loaded,
        savedLocations: locations,
      ));
    } catch (e) {
      _logger.e('Error loading locations', error: e);
      emit(state.copyWith(
        status: NearbyHelpStatus.error,
        errorMessage: 'Failed to load locations',
      ));
    }
  }

  Future<void> _onSaveLocation(
    NearbyHelpSaveLocation event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.updating));

    try {
      await _locationService.saveLocation(
        userId: state.userId!,
        type: event.type,
        latitude: event.latitude,
        longitude: event.longitude,
        address: event.address,
      );

      emit(state.copyWith(
        status: NearbyHelpStatus.loaded,
        successMessage: '${event.type.displayName} location saved',
        clearError: true,
      ));
    } catch (e) {
      _logger.e('Error saving location', error: e);
      emit(state.copyWith(
        status: NearbyHelpStatus.error,
        errorMessage: 'Failed to save location',
      ));
    }
  }

  Future<void> _onDeleteLocation(
    NearbyHelpDeleteLocation event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.updating));

    try {
      await _locationService.deleteLocation(state.userId!, event.type);

      emit(state.copyWith(
        status: NearbyHelpStatus.loaded,
        successMessage: '${event.type.displayName} location removed',
        clearError: true,
      ));
    } catch (e) {
      _logger.e('Error deleting location', error: e);
      emit(state.copyWith(
        status: NearbyHelpStatus.error,
        errorMessage: 'Failed to remove location',
      ));
    }
  }

  Future<void> _onToggleLocation(
    NearbyHelpToggleLocation event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    try {
      await _locationService.toggleLocationActive(
        state.userId!,
        event.type,
        event.isActive,
      );
    } catch (e) {
      _logger.e('Error toggling location', error: e);
      emit(state.copyWith(
        errorMessage: 'Failed to update location',
      ));
    }
  }

  Future<void> _onUpdateSettings(
    NearbyHelpUpdateSettings event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    try {
      await _locationService.updateHelpSettings(
        userId: state.userId!,
        receiveHelpAlerts: event.receiveHelpAlerts,
      );

      emit(state.copyWith(
        successMessage: event.receiveHelpAlerts
            ? 'Help alerts enabled'
            : 'Help alerts disabled',
        clearError: true,
      ));
    } catch (e) {
      _logger.e('Error updating settings', error: e);
      emit(state.copyWith(
        errorMessage: 'Failed to update settings',
      ));
    }
  }

  Future<void> _onCreateRequest(
    NearbyHelpCreateRequest event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null || state.userName == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.creating, clearError: true));

    final result = await _helpService.createHelpRequest(
      seekerUserId: state.userId!,
      seekerName: state.userName!,
      seekerPhotoUrl: state.userPhotoUrl,
      latitude: event.latitude,
      longitude: event.longitude,
      radius: event.radius,
      topic: event.topic,
    );

    switch (result) {
      case NearbyHelpSuccess<HelpRequest>():
        emit(state.copyWith(
          status: NearbyHelpStatus.loaded,
          activeRequest: result.data,
          successMessage: 'Help request created! Notifying nearby users...',
        ));
      case NearbyHelpFailure<HelpRequest>():
        emit(state.copyWith(
          status: NearbyHelpStatus.error,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onCancelRequest(
    NearbyHelpCancelRequest event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.updating));

    final result = await _helpService.cancelRequest(
      event.requestId,
      state.userId!,
    );

    switch (result) {
      case NearbyHelpSuccess():
        emit(state.copyWith(
          status: NearbyHelpStatus.loaded,
          clearActiveRequest: true,
          successMessage: 'Help request cancelled',
        ));
      case NearbyHelpFailure():
        emit(state.copyWith(
          status: NearbyHelpStatus.error,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onAcceptRequest(
    NearbyHelpAcceptRequest event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null || state.userName == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.accepting, clearError: true));

    final result = await _helpService.acceptHelpRequest(
      requestId: event.requestId,
      helperUserId: state.userId!,
      helperName: state.userName!,
      helperPhotoUrl: state.userPhotoUrl,
    );

    switch (result) {
      case NearbyHelpSuccess<HelpRequest>():
        emit(state.copyWith(
          status: NearbyHelpStatus.loaded,
          viewedRequest: result.data,
          successMessage: 'You are now assigned to help!',
        ));
      case NearbyHelpFailure<HelpRequest>():
        emit(state.copyWith(
          status: NearbyHelpStatus.error,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onMarkOnTheWay(
    NearbyHelpMarkOnTheWay event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    final result = await _helpService.markOnTheWay(
      event.requestId,
      state.userId!,
    );

    switch (result) {
      case NearbyHelpSuccess():
        emit(state.copyWith(
          successMessage: 'Marked as on the way',
        ));
      case NearbyHelpFailure():
        emit(state.copyWith(
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onMarkCompleted(
    NearbyHelpMarkCompleted event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    emit(state.copyWith(status: NearbyHelpStatus.updating));

    final result = await _helpService.markCompleted(
      event.requestId,
      state.userId!,
    );

    switch (result) {
      case NearbyHelpSuccess():
        emit(state.copyWith(
          status: NearbyHelpStatus.loaded,
          clearActiveRequest: true,
          clearViewedRequest: true,
          successMessage: 'Help completed! Thank you!',
        ));
      case NearbyHelpFailure():
        emit(state.copyWith(
          status: NearbyHelpStatus.error,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onLoadRequest(
    NearbyHelpLoadRequest event,
    Emitter<NearbyHelpState> emit,
  ) async {
    emit(state.copyWith(status: NearbyHelpStatus.loading, clearError: true));

    final request = await _helpService.getHelpRequest(event.requestId);

    if (request != null) {
      emit(state.copyWith(
        status: NearbyHelpStatus.loaded,
        viewedRequest: request,
      ));
    } else {
      emit(state.copyWith(
        status: NearbyHelpStatus.error,
        errorMessage: 'Help request not found',
      ));
    }
  }

  Future<void> _onSubscribeToRequest(
    NearbyHelpSubscribeToRequest event,
    Emitter<NearbyHelpState> emit,
  ) async {
    await _viewedRequestSubscription?.cancel();

    _viewedRequestSubscription = _helpService
        .streamHelpRequest(event.requestId)
        .listen((request) {
      if (!isClosed) add(_ViewedRequestUpdated(request));
    });
  }

  Future<void> _onUnsubscribeFromRequest(
    NearbyHelpUnsubscribeFromRequest event,
    Emitter<NearbyHelpState> emit,
  ) async {
    await _viewedRequestSubscription?.cancel();
    _viewedRequestSubscription = null;

    emit(state.copyWith(clearViewedRequest: true));
  }

  void _onClearMessages(
    NearbyHelpClearMessages event,
    Emitter<NearbyHelpState> emit,
  ) {
    emit(state.copyWith(clearError: true, clearSuccess: true));
  }

  void _onLocationsUpdated(
    _LocationsUpdated event,
    Emitter<NearbyHelpState> emit,
  ) {
    emit(state.copyWith(savedLocations: event.locations));
  }

  void _onSettingsUpdated(
    _SettingsUpdated event,
    Emitter<NearbyHelpState> emit,
  ) {
    emit(state.copyWith(settings: event.settings));
  }

  void _onActiveRequestUpdated(
    _ActiveRequestUpdated event,
    Emitter<NearbyHelpState> emit,
  ) {
    if (event.request == null) {
      emit(state.copyWith(clearActiveRequest: true));
    } else {
      emit(state.copyWith(activeRequest: event.request));
    }
  }

  void _onViewedRequestUpdated(
    _ViewedRequestUpdated event,
    Emitter<NearbyHelpState> emit,
  ) {
    if (event.request == null) {
      emit(state.copyWith(clearViewedRequest: true));
    } else {
      emit(state.copyWith(viewedRequest: event.request));
    }
  }

  void _onHelperRequestsUpdated(
    _HelperRequestsUpdated event,
    Emitter<NearbyHelpState> emit,
  ) {
    emit(state.copyWith(helperRequests: event.requests));
  }

  void _onIncomingRequestsUpdated(
    _IncomingRequestsUpdated event,
    Emitter<NearbyHelpState> emit,
  ) {
    emit(state.copyWith(incomingRequests: event.requests));
  }

  Future<void> _onWatchIncomingRequests(
    NearbyHelpWatchIncomingRequests event,
    Emitter<NearbyHelpState> emit,
  ) async {
    if (state.userId == null) return;

    await _incomingRequestsSubscription?.cancel();

    _incomingRequestsSubscription = _helpService
        .streamOpenHelpRequests(state.userId!)
        .listen((requests) {
      if (!isClosed) {
        add(_IncomingRequestsUpdated(requests));
      }
    });
  }

  Future<void> _onStopWatchingIncomingRequests(
    NearbyHelpStopWatchingIncomingRequests event,
    Emitter<NearbyHelpState> emit,
  ) async {
    await _incomingRequestsSubscription?.cancel();
    _incomingRequestsSubscription = null;
    emit(state.copyWith(incomingRequests: []));
  }

  Future<void> _cancelSubscriptions() async {
    await _locationsSubscription?.cancel();
    await _settingsSubscription?.cancel();
    await _seekerRequestsSubscription?.cancel();
    await _helperRequestsSubscription?.cancel();
    await _viewedRequestSubscription?.cancel();
    await _incomingRequestsSubscription?.cancel();
    _locationsSubscription = null;
    _settingsSubscription = null;
    _seekerRequestsSubscription = null;
    _helperRequestsSubscription = null;
    _viewedRequestSubscription = null;
    _incomingRequestsSubscription = null;
  }

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    return super.close();
  }
}
