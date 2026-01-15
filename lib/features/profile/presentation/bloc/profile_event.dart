part of 'profile_bloc.dart';

/// Base class for all profile events.
abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load a profile.
class ProfileLoadRequested extends ProfileEvent {
  final String userId;

  const ProfileLoadRequested(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Event to update profile data.
class ProfileUpdateRequested extends ProfileEvent {
  final Profile profile;

  const ProfileUpdateRequested(this.profile);

  @override
  List<Object?> get props => [profile];
}

/// Event to toggle visibility.
class ProfileVisibilityToggled extends ProfileEvent {
  final bool isVisible;

  const ProfileVisibilityToggled(this.isVisible);

  @override
  List<Object?> get props => [isVisible];
}

/// Event to update profile photo.
class ProfilePhotoUpdated extends ProfileEvent {
  final String photoUrl;

  const ProfilePhotoUpdated(this.photoUrl);

  @override
  List<Object?> get props => [photoUrl];
}

/// Internal event for stream updates.
class ProfileStreamUpdated extends ProfileEvent {
  final Profile? profile;

  const ProfileStreamUpdated(this.profile);

  @override
  List<Object?> get props => [profile];
}
