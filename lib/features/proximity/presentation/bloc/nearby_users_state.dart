part of 'nearby_users_bloc.dart';

/// Status of nearby users screen.
enum NearbyUsersStatus {
  /// Initial state, not scanning.
  idle,

  /// Loading/initializing.
  loading,

  /// Actively scanning (15 seconds).
  scanning,

  /// Scan complete with results.
  results,

  /// Scan complete but no users found.
  empty,

  /// Error occurred.
  error,
}

/// Filter options for nearby users.
/// @deprecated Filters have been removed - always shows all users.
enum NearbyUsersFilter {
  all,
  close,
  nearby,
}

/// State for nearby users.
class NearbyUsersState extends Equatable {
  final NearbyUsersStatus status;
  final List<NearbyUser> users;
  final bool isScanning;
  final bool isAdvertising;
  final String? errorMessage;

  // Legacy fields for compatibility
  final List<NearbyUser> filteredUsers;
  final NearbyUsersFilter filter;
  final bool isDiscovering;
  final bool searchTimedOut;

  const NearbyUsersState({
    this.status = NearbyUsersStatus.idle,
    this.users = const [],
    this.isScanning = false,
    this.isAdvertising = false,
    this.errorMessage,
    // Legacy
    this.filteredUsers = const [],
    this.filter = NearbyUsersFilter.all,
    this.isDiscovering = false,
    this.searchTimedOut = false,
  });

  NearbyUsersState copyWith({
    NearbyUsersStatus? status,
    List<NearbyUser>? users,
    bool? isScanning,
    bool? isAdvertising,
    String? errorMessage,
    bool clearErrorMessage = false,
    // Legacy
    List<NearbyUser>? filteredUsers,
    NearbyUsersFilter? filter,
    bool? isDiscovering,
    bool? searchTimedOut,
  }) {
    return NearbyUsersState(
      status: status ?? this.status,
      users: users ?? this.users,
      isScanning: isScanning ?? this.isScanning,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      // Legacy - keep in sync
      filteredUsers: users ?? this.users, // No filtering, same as users
      filter: filter ?? this.filter,
      isDiscovering: isScanning ?? this.isScanning, // Alias
      searchTimedOut: searchTimedOut ?? this.searchTimedOut,
    );
  }

  @override
  List<Object?> get props => [
        status,
        users,
        isScanning,
        isAdvertising,
        errorMessage,
        filteredUsers,
        filter,
        isDiscovering,
        searchTimedOut,
      ];
}
