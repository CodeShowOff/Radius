part of 'nearby_users_bloc.dart';

/// Base class for nearby users events.
abstract class NearbyUsersEvent extends Equatable {
  const NearbyUsersEvent();

  @override
  List<Object?> get props => [];
}

/// Event to initialize the service (starts advertising).
class NearbyUsersInitialize extends NearbyUsersEvent {
  final String userId;
  final String username;

  const NearbyUsersInitialize({
    required this.userId,
    required this.username,
  });

  @override
  List<Object?> get props => [userId, username];
}

/// Event to start a scan for nearby users.
/// [duration] - Optional custom scan duration. Defaults to 10 seconds if not specified.
class NearbyUsersStartScan extends NearbyUsersEvent {
  final Duration? duration;

  const NearbyUsersStartScan({this.duration});

  @override
  List<Object?> get props => [duration];
}

/// Event to stop scanning manually.
class NearbyUsersStopScan extends NearbyUsersEvent {
  const NearbyUsersStopScan();
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

/// Event to clear scan results.
class NearbyUsersClearResults extends NearbyUsersEvent {
  const NearbyUsersClearResults();
}

/// Event when app goes to background.
class NearbyUsersAppBackgrounded extends NearbyUsersEvent {
  const NearbyUsersAppBackgrounded();
}

/// Event when app resumes.
class NearbyUsersAppResumed extends NearbyUsersEvent {
  const NearbyUsersAppResumed();
}

// ============== Legacy Events (for compatibility) ==============

/// Event to start discovering nearby users.
/// @deprecated Use NearbyUsersInitialize + NearbyUsersStartScan instead.
class NearbyUsersStartDiscovery extends NearbyUsersEvent {
  final String userId;
  final String username;

  const NearbyUsersStartDiscovery({
    required this.userId,
    required this.username,
  });

  @override
  List<Object?> get props => [userId, username];
}

/// Event to stop discovery.
/// @deprecated Use NearbyUsersStopScan instead.
class NearbyUsersStopDiscovery extends NearbyUsersEvent {
  const NearbyUsersStopDiscovery();
}

/// Event to change filter.
/// @deprecated Filters have been removed.
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
/// @deprecated Scan auto-stops after 15 seconds.
class NearbyUsersInitialSearchTimeout extends NearbyUsersEvent {
  const NearbyUsersInitialSearchTimeout();
}
