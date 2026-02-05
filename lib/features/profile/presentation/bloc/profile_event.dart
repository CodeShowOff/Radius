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

/// Event to update privacy settings.
class ProfilePrivacySettingsUpdated extends ProfileEvent {
  final bool? showOnlineStatus;
  final bool? allowConnectionRequests;
  final bool? showLastSeen;

  const ProfilePrivacySettingsUpdated({
    this.showOnlineStatus,
    this.allowConnectionRequests,
    this.showLastSeen,
  });

  @override
  List<Object?> get props =>
      [showOnlineStatus, allowConnectionRequests, showLastSeen];
}

/// Event to update notification settings.
class ProfileNotificationSettingsUpdated extends ProfileEvent {
  final bool? notifyDirectMessages;
  final bool? notifyLocationGroups;
  final bool? notifyNearbyGroups;
  final bool? notifyRandomGroups;

  const ProfileNotificationSettingsUpdated({
    this.notifyDirectMessages,
    this.notifyLocationGroups,
    this.notifyNearbyGroups,
    this.notifyRandomGroups,
  });

  @override
  List<Object?> get props => [
        notifyDirectMessages,
        notifyLocationGroups,
        notifyNearbyGroups,
        notifyRandomGroups,
      ];
}

/// Internal event for stream updates.
class ProfileStreamUpdated extends ProfileEvent {
  final Profile? profile;

  const ProfileStreamUpdated(this.profile);

  @override
  List<Object?> get props => [profile];
}
