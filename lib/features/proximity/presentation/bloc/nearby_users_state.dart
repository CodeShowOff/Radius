part of 'nearby_users_bloc.dart';

/// Status of nearby users screen.
enum NearbyUsersStatus {
  idle,
  loading,
  discovering,
  empty,
  error,
}

/// Filter options for nearby users.
enum NearbyUsersFilter {
  all,
  close,
  nearby,
}

/// State for nearby users.
class NearbyUsersState extends Equatable {
  final NearbyUsersStatus status;
  final List<NearbyUser> users;
  final List<NearbyUser> filteredUsers;
  final NearbyUsersFilter filter;
  final bool isDiscovering;
  final String? errorMessage;

  const NearbyUsersState({
    this.status = NearbyUsersStatus.idle,
    this.users = const [],
    this.filteredUsers = const [],
    this.filter = NearbyUsersFilter.all,
    this.isDiscovering = false,
    this.errorMessage,
  });

  NearbyUsersState copyWith({
    NearbyUsersStatus? status,
    List<NearbyUser>? users,
    List<NearbyUser>? filteredUsers,
    NearbyUsersFilter? filter,
    bool? isDiscovering,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return NearbyUsersState(
      status: status ?? this.status,
      users: users ?? this.users,
      filteredUsers: filteredUsers ?? this.filteredUsers,
      filter: filter ?? this.filter,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        users,
        filteredUsers,
        filter,
        isDiscovering,
        errorMessage,
      ];
}
