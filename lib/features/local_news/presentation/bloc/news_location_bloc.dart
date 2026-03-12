import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/services/news_location_service.dart';
import '../../domain/entities/news_location.dart';

part 'news_location_event.dart';
part 'news_location_state.dart';

/// BLoC for managing the user's news location setup flow.
///
/// Handles:
/// - Checking for an existing saved location
/// - Manual location selection
/// - Saving the confirmed location to Firestore
class NewsLocationBloc extends Bloc<NewsLocationEvent, NewsLocationState> {
  final NewsLocationService _locationService;
  final Logger _logger;

  NewsLocationBloc({
    required NewsLocationService locationService,
    Logger? logger,
  })  : _locationService = locationService,
        _logger = logger ?? Logger(),
        super(const NewsLocationState()) {
    on<NewsLocationCheckRequested>(_onCheckRequested);
    on<NewsLocationManualSelected>(_onManualSelected);
    on<NewsLocationSaveRequested>(_onSaveRequested);
    on<NewsLocationChangeRequested>(_onChangeRequested);
  }

  /// Check if the user already has a saved news location.
  Future<void> _onCheckRequested(
    NewsLocationCheckRequested event,
    Emitter<NewsLocationState> emit,
  ) async {
    emit(state.copyWith(status: NewsLocationStatus.loading, clearError: true));

    try {
      final saved = await _locationService.getUserNewsLocation(event.userId);

      if (saved != null) {
        _logger.i('Found saved news location: ${saved.shortDisplayString}');
        emit(state.copyWith(
          status: NewsLocationStatus.ready,
          location: saved,
        ));
      } else {
        _logger.i('No saved news location — needs setup');
        emit(state.copyWith(status: NewsLocationStatus.needsSetup));
      }
    } catch (e, stack) {
      _logger.e('Error checking saved location', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: NewsLocationStatus.needsSetup,
      ));
    }
  }

  /// User selected a location manually from the country/city picker.
  Future<void> _onManualSelected(
    NewsLocationManualSelected event,
    Emitter<NewsLocationState> emit,
  ) async {
    final location = NewsLocation(
      latitude: 0.0,
      longitude: 0.0,
      district: '',
      city: event.city,
      locality: '',
      country: event.country,
      source: LocationSource.manual,
    );

    emit(state.copyWith(
      status: NewsLocationStatus.detected,
      location: location,
    ));
  }

  /// Save the confirmed location to Firestore.
  Future<void> _onSaveRequested(
    NewsLocationSaveRequested event,
    Emitter<NewsLocationState> emit,
  ) async {
    if (state.location == null) {
      emit(state.copyWith(
        status: NewsLocationStatus.error,
        errorMessage: 'No location to save.',
      ));
      return;
    }

    emit(state.copyWith(status: NewsLocationStatus.saving));

    try {
      await _locationService.saveUserNewsLocation(
        userId: event.userId,
        location: state.location!,
      );

      _logger.i('News location saved for user ${event.userId}');
      emit(state.copyWith(status: NewsLocationStatus.ready));
    } catch (e, stack) {
      _logger.e('Error saving news location', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: NewsLocationStatus.error,
        errorMessage: 'Failed to save location. Please try again.',
      ));
    }
  }

  /// Reset to setup state so user can change their location.
  void _onChangeRequested(
    NewsLocationChangeRequested event,
    Emitter<NewsLocationState> emit,
  ) {
    emit(state.copyWith(
      status: NewsLocationStatus.needsSetup,
      clearLocation: true,
      clearError: true,
    ));
  }
}
