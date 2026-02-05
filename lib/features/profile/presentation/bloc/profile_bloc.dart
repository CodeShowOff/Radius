import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/profile.dart';
import '../../domain/repositories/i_profile_repository.dart';

part 'profile_event.dart';
part 'profile_state.dart';

/// BLoC for managing profile state.
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final IProfileRepository _profileRepository;
  StreamSubscription<Profile?>? _profileSubscription;

  ProfileBloc({required IProfileRepository profileRepository})
      : _profileRepository = profileRepository,
        super(ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
    on<ProfileUpdateRequested>(_onUpdateRequested);
    on<ProfileVisibilityToggled>(_onVisibilityToggled);
    on<ProfilePhotoUpdated>(_onPhotoUpdated);
    on<ProfilePrivacySettingsUpdated>(_onPrivacySettingsUpdated);
    on<ProfileNotificationSettingsUpdated>(_onNotificationSettingsUpdated);
    on<ProfileStreamUpdated>(_onStreamUpdated);
  }

  Future<void> _onLoadRequested(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());

    // Cancel existing subscription
    await _profileSubscription?.cancel();

    // Start listening to profile stream
    _profileSubscription = _profileRepository
        .profileStream(event.userId)
        .listen((profile) {
          if (!isClosed) {
            add(ProfileStreamUpdated(profile));
          }
        });

    // Also do an immediate fetch
    final result = await _profileRepository.getProfile(event.userId);
    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (profile) {
        if (profile != null) {
          emit(ProfileLoaded(profile));
        } else {
          // Create empty profile for new users
          emit(ProfileLoaded(Profile.empty(event.userId)));
        }
      },
    );
  }

  void _onStreamUpdated(
    ProfileStreamUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (event.profile != null) {
      emit(ProfileLoaded(event.profile!));
    }
  }

  Future<void> _onUpdateRequested(
    ProfileUpdateRequested event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    emit(ProfileSaving(currentState.profile));

    final result = await _profileRepository.saveProfile(event.profile);
    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (_) {
        emit(ProfileSaved(event.profile));
        emit(ProfileLoaded(event.profile));
      },
    );
  }

  Future<void> _onVisibilityToggled(
    ProfileVisibilityToggled event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    final updatedProfile = currentState.profile.copyWith(
      isVisible: event.isVisible,
      updatedAt: DateTime.now(),
    );

    emit(ProfileSaving(updatedProfile));

    final result = await _profileRepository.updateVisibility(
      currentState.profile.userId,
      event.isVisible,
    );

    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (_) => emit(ProfileLoaded(updatedProfile)),
    );
  }

  Future<void> _onPhotoUpdated(
    ProfilePhotoUpdated event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    final updatedProfile = currentState.profile.copyWith(
      photoUrl: event.photoUrl,
      updatedAt: DateTime.now(),
    );

    emit(ProfileSaving(updatedProfile));

    final result = await _profileRepository.updateProfile(
      userId: currentState.profile.userId,
      photoUrl: event.photoUrl,
    );

    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (_) => emit(ProfileLoaded(updatedProfile)),
    );
  }

  Future<void> _onPrivacySettingsUpdated(
    ProfilePrivacySettingsUpdated event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    final updatedProfile = currentState.profile.copyWith(
      showOnlineStatus:
          event.showOnlineStatus ?? currentState.profile.showOnlineStatus,
      allowConnectionRequests: event.allowConnectionRequests ??
          currentState.profile.allowConnectionRequests,
      showLastSeen: event.showLastSeen ?? currentState.profile.showLastSeen,
      updatedAt: DateTime.now(),
    );

    emit(ProfileSaving(updatedProfile));

    final result = await _profileRepository.saveProfile(updatedProfile);

    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (_) => emit(ProfileLoaded(updatedProfile)),
    );
  }

  Future<void> _onNotificationSettingsUpdated(
    ProfileNotificationSettingsUpdated event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileLoaded) return;

    final updatedProfile = currentState.profile.copyWith(
      notifyDirectMessages:
          event.notifyDirectMessages ?? currentState.profile.notifyDirectMessages,
      notifyLocationGroups:
          event.notifyLocationGroups ?? currentState.profile.notifyLocationGroups,
      notifyNearbyGroups:
          event.notifyNearbyGroups ?? currentState.profile.notifyNearbyGroups,
      notifyRandomGroups:
          event.notifyRandomGroups ?? currentState.profile.notifyRandomGroups,
      updatedAt: DateTime.now(),
    );

    emit(ProfileSaving(updatedProfile));

    final result = await _profileRepository.saveProfile(updatedProfile);

    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (_) => emit(ProfileLoaded(updatedProfile)),
    );
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    return super.close();
  }
}
