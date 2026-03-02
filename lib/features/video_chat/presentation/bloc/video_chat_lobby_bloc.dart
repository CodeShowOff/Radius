import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/video_chat_profile_service.dart';
import '../../data/video_chat_settings_service.dart';
import '../../domain/entities/video_chat_profile.dart';

part 'video_chat_lobby_event.dart';
part 'video_chat_lobby_state.dart';

/// BLoC managing the Video Chat lobby flow:
///
/// 1. Age gate (first time only)
/// 2. Headphones advisory (every time, unless dismissed permanently)
/// 3. Profile setup (first time) / Profile modify prompt (returning users)
/// 4. Ready → enter matching lobby
class VideoChatLobbyBloc
    extends Bloc<VideoChatLobbyEvent, VideoChatLobbyState> {
  final VideoChatProfileService _profileService;
  final VideoChatSettingsService _settingsService;
  final Logger _logger;

  String _userId = '';
  VideoChatProfile? _existingProfile;

  VideoChatLobbyBloc({
    required VideoChatProfileService profileService,
    required VideoChatSettingsService settingsService,
    Logger? logger,
  })  : _profileService = profileService,
        _settingsService = settingsService,
        _logger = logger ?? Logger(),
        super(const VideoChatLobbyInitial()) {
    on<VideoChatLobbyEntered>(_onEntered);
    on<VideoChatAgeVerified>(_onAgeVerified);
    on<VideoChatHeadphonesDismissed>(_onHeadphonesDismissed);
    on<VideoChatProfileSaved>(_onProfileSaved);
    on<VideoChatProfileSkipped>(_onProfileSkipped);
    on<VideoChatProfileModifyRequested>(_onProfileModifyRequested);
    on<VideoChatProfilePhotoRemoved>(_onProfilePhotoRemoved);
  }

  // ════════════════════════════════════════════════════════════════════
  //  Event Handlers
  // ════════════════════════════════════════════════════════════════════

  Future<void> _onEntered(
    VideoChatLobbyEntered event,
    Emitter<VideoChatLobbyState> emit,
  ) async {
    _userId = event.userId;
    emit(const VideoChatLobbyLoading());

    try {
      // Initialize settings (Hive box)
      await _settingsService.init();

      // Fetch existing profile from Firestore
      _existingProfile = await _profileService.getProfile(_userId);

      // Step 1: Age gate check
      if (!_settingsService.isAgeVerified) {
        emit(const VideoChatLobbyAgeGate());
        return;
      }

      // Proceed past age gate
      _emitNextAfterAgeGate(emit);
    } catch (e, st) {
      _logger.e('Error entering video chat lobby', error: e, stackTrace: st);
      emit(VideoChatLobbyError(message: 'Failed to load: $e'));
    }
  }

  Future<void> _onAgeVerified(
    VideoChatAgeVerified event,
    Emitter<VideoChatLobbyState> emit,
  ) async {
    await _settingsService.setAgeVerified();
    _emitNextAfterAgeGate(emit);
  }

  Future<void> _onHeadphonesDismissed(
    VideoChatHeadphonesDismissed event,
    Emitter<VideoChatLobbyState> emit,
  ) async {
    if (event.permanently) {
      await _settingsService.dismissHeadphonesAdvisory();
    }
    _emitNextAfterHeadphones(emit);
  }

  Future<void> _onProfileSaved(
    VideoChatProfileSaved event,
    Emitter<VideoChatLobbyState> emit,
  ) async {
    emit(const VideoChatLobbySavingProfile());

    try {
      String? photoUrl = _existingProfile?.photoUrl;

      // Upload new photo if provided
      if (event.photoFilePath != null) {
        photoUrl = await _profileService.uploadProfilePhoto(
          userId: _userId,
          filePath: event.photoFilePath!,
        );
      }

      final now = DateTime.now();
      final profile = VideoChatProfile(
        userId: _userId,
        displayName: event.displayName.trim(),
        photoUrl: photoUrl,
        createdAt: _existingProfile?.createdAt ?? now,
        updatedAt: now,
      );

      await _profileService.saveProfile(profile);
      _existingProfile = profile;

      _logger.d('Video chat profile saved: ${profile.displayName}');
      emit(VideoChatLobbyReady(profile: profile));
    } catch (e, st) {
      _logger.e('Failed to save profile', error: e, stackTrace: st);
      emit(VideoChatLobbyError(message: 'Failed to save profile: $e'));
    }
  }

  Future<void> _onProfileSkipped(
    VideoChatProfileSkipped event,
    Emitter<VideoChatLobbyState> emit,
  ) async {
    if (_existingProfile != null) {
      emit(VideoChatLobbyReady(profile: _existingProfile!));
    } else {
      // Should not happen — skip is only available for returning users
      emit(const VideoChatLobbyError(message: 'No profile found'));
    }
  }

  void _onProfileModifyRequested(
    VideoChatProfileModifyRequested event,
    Emitter<VideoChatLobbyState> emit,
  ) {
    emit(VideoChatLobbyProfileSetup(
      existingProfile: _existingProfile,
      isFirstTime: false,
    ));
  }

  Future<void> _onProfilePhotoRemoved(
    VideoChatProfilePhotoRemoved event,
    Emitter<VideoChatLobbyState> emit,
  ) async {
    if (_existingProfile != null) {
      await _profileService.deleteProfilePhoto(_userId);
      _existingProfile = _existingProfile!.copyWith(clearPhotoUrl: true);
      await _profileService.saveProfile(_existingProfile!);
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Flow Navigation Helpers
  // ════════════════════════════════════════════════════════════════════

  /// Determines the next step after the age gate is passed.
  void _emitNextAfterAgeGate(Emitter<VideoChatLobbyState> emit) {
    // Step 2: Headphones advisory
    if (!_settingsService.isHeadphonesAdvisoryDismissed) {
      emit(const VideoChatLobbyHeadphonesAdvisory());
      return;
    }

    _emitNextAfterHeadphones(emit);
  }

  /// Determines the next step after headphones advisory is passed.
  void _emitNextAfterHeadphones(Emitter<VideoChatLobbyState> emit) {
    // Step 3: Profile setup or modification prompt
    if (_existingProfile == null || !_existingProfile!.isComplete) {
      // First-time user — must set up profile
      emit(VideoChatLobbyProfileSetup(
        existingProfile: _existingProfile,
        isFirstTime: true,
      ));
    } else {
      // Returning user — ask if they want to modify
      emit(VideoChatLobbyProfilePrompt(existingProfile: _existingProfile!));
    }
  }
}
