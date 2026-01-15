part of 'nearby_users_bloc.dart';

/// Base class for nearby users events.
abstract class NearbyUsersEvent extends Equatable {
  const NearbyUsersEvent();

  @override
  List<Object?> get props => [];
}

/// Event to start discovering nearby users.
class NearbyUsersStartDiscovery extends NearbyUsersEvent {
  final String userId;

  const NearbyUsersStartDiscovery(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Event to stop discovery.
class NearbyUsersStopDiscovery extends NearbyUsersEvent {
  const NearbyUsersStopDiscovery();
}

/// Event when nearby users list is updated.
class NearbyUsersUpdated extends NearbyUsersEvent {
  final List<NearbyUser> users;

  const NearbyUsersUpdated(this.users);

  @override
  List<Object?> get props => [users];
}

/// Event when proximity service state changes.
class NearbyUsersServiceStateChanged extends NearbyUsersEvent {
  final ProximityServiceState serviceState;

  const NearbyUsersServiceStateChanged(this.serviceState);

  @override
  List<Object?> get props => [serviceState];
}

/// Event to change filter.
class NearbyUsersFilterChanged extends NearbyUsersEvent {
  final NearbyUsersFilter filter;

  const NearbyUsersFilterChanged(this.filter);

  @override
  List<Object?> get props => [filter];
}

/// Event to refresh/restart discovery.
class NearbyUsersRefresh extends NearbyUsersEvent {
  const NearbyUsersRefresh();
}

/// Event when initial search timeout occurs.
class NearbyUsersInitialSearchTimeout extends NearbyUsersEvent {
  const NearbyUsersInitialSearchTimeout();
}
