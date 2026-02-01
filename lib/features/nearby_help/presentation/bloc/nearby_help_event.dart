part of 'nearby_help_bloc.dart';

/// Base class for all nearby help events.
abstract class NearbyHelpEvent extends Equatable {
  const NearbyHelpEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the bloc with user ID.
class NearbyHelpInitialize extends NearbyHelpEvent {
  final String userId;
  final String userName;
  final String? userPhotoUrl;

  const NearbyHelpInitialize({
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
  });

  @override
  List<Object?> get props => [userId, userName, userPhotoUrl];
}

/// Load user's saved locations.
class NearbyHelpLoadLocations extends NearbyHelpEvent {
  const NearbyHelpLoadLocations();
}

/// Save a user location (home/work).
class NearbyHelpSaveLocation extends NearbyHelpEvent {
  final LocationType type;
  final double latitude;
  final double longitude;
  final String? address;

  const NearbyHelpSaveLocation({
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  @override
  List<Object?> get props => [type, latitude, longitude, address];
}

/// Delete a saved location.
class NearbyHelpDeleteLocation extends NearbyHelpEvent {
  final LocationType type;

  const NearbyHelpDeleteLocation(this.type);

  @override
  List<Object?> get props => [type];
}

/// Toggle location active status.
class NearbyHelpToggleLocation extends NearbyHelpEvent {
  final LocationType type;
  final bool isActive;

  const NearbyHelpToggleLocation({
    required this.type,
    required this.isActive,
  });

  @override
  List<Object?> get props => [type, isActive];
}

/// Update help alert settings.
class NearbyHelpUpdateSettings extends NearbyHelpEvent {
  final bool receiveHelpAlerts;

  const NearbyHelpUpdateSettings({required this.receiveHelpAlerts});

  @override
  List<Object?> get props => [receiveHelpAlerts];
}

/// Create a new help request.
class NearbyHelpCreateRequest extends NearbyHelpEvent {
  final double latitude;
  final double longitude;
  final HelpRadius radius;
  final String? topic;

  const NearbyHelpCreateRequest({
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.topic,
  });

  @override
  List<Object?> get props => [latitude, longitude, radius, topic];
}

/// Cancel an active help request.
class NearbyHelpCancelRequest extends NearbyHelpEvent {
  final String requestId;

  const NearbyHelpCancelRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Accept a help request (as helper).
class NearbyHelpAcceptRequest extends NearbyHelpEvent {
  final String requestId;

  const NearbyHelpAcceptRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Mark helper as "on the way".
class NearbyHelpMarkOnTheWay extends NearbyHelpEvent {
  final String requestId;

  const NearbyHelpMarkOnTheWay(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Mark help as completed.
class NearbyHelpMarkCompleted extends NearbyHelpEvent {
  final String requestId;

  const NearbyHelpMarkCompleted(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Load a specific help request (e.g., from deep link).
class NearbyHelpLoadRequest extends NearbyHelpEvent {
  final String requestId;

  const NearbyHelpLoadRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Subscribe to a help request for real-time updates.
class NearbyHelpSubscribeToRequest extends NearbyHelpEvent {
  final String requestId;

  const NearbyHelpSubscribeToRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Unsubscribe from request updates.
class NearbyHelpUnsubscribeFromRequest extends NearbyHelpEvent {
  const NearbyHelpUnsubscribeFromRequest();
}

/// Internal event: locations updated from stream.
class _LocationsUpdated extends NearbyHelpEvent {
  final List<UserLocation> locations;

  const _LocationsUpdated(this.locations);

  @override
  List<Object?> get props => [locations];
}

/// Internal event: settings updated from stream.
class _SettingsUpdated extends NearbyHelpEvent {
  final NearbyHelpSettings settings;

  const _SettingsUpdated(this.settings);

  @override
  List<Object?> get props => [settings];
}

/// Internal event: active request updated from stream.
class _ActiveRequestUpdated extends NearbyHelpEvent {
  final HelpRequest? request;

  const _ActiveRequestUpdated(this.request);

  @override
  List<Object?> get props => [request];
}

/// Internal event: viewed request updated from stream.
class _ViewedRequestUpdated extends NearbyHelpEvent {
  final HelpRequest? request;

  const _ViewedRequestUpdated(this.request);

  @override
  List<Object?> get props => [request];
}

/// Internal event: helper requests updated from stream.
class _HelperRequestsUpdated extends NearbyHelpEvent {
  final List<HelpRequest> requests;

  const _HelperRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}
