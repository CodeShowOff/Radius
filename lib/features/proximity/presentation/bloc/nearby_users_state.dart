part of 'nearby_users_bloc.dart';

class BleDebugInfo extends Equatable {
  final bool isScanning;
  final bool isAdvertising;
  final String? lastError;

  final int rawScanResults;
  final int parsedRadiusDevices;
  final int filteredOut;

  const BleDebugInfo({
    required this.isScanning,
    required this.isAdvertising,
    required this.lastError,
    required this.rawScanResults,
    required this.parsedRadiusDevices,
    required this.filteredOut,
  });

  @override
  List<Object?> get props => [
        isScanning,
        isAdvertising,
        lastError,
        rawScanResults,
        parsedRadiusDevices,
        filteredOut,
      ];
}

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
  final BleRangeMode rangeMode;
  final bool isDiscovering;
  final bool searchTimedOut;
  final String? errorMessage;
  final BleDebugInfo? bleDebugInfo;

  const NearbyUsersState({
    this.status = NearbyUsersStatus.idle,
    this.users = const [],
    this.filteredUsers = const [],
    this.filter = NearbyUsersFilter.all,
    this.rangeMode = BleRangeMode.large,
    this.isDiscovering = false,
    this.searchTimedOut = false,
    this.errorMessage,
    this.bleDebugInfo,
  });

  NearbyUsersState copyWith({
    NearbyUsersStatus? status,
    List<NearbyUser>? users,
    List<NearbyUser>? filteredUsers,
    NearbyUsersFilter? filter,
    BleRangeMode? rangeMode,
    bool? isDiscovering,
    bool? searchTimedOut,
    String? errorMessage,
    bool clearErrorMessage = false,
    BleDebugInfo? bleDebugInfo,
    bool clearBleDebugInfo = false,
  }) {
    return NearbyUsersState(
      status: status ?? this.status,
      users: users ?? this.users,
      filteredUsers: filteredUsers ?? this.filteredUsers,
      filter: filter ?? this.filter,
      rangeMode: rangeMode ?? this.rangeMode,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      searchTimedOut: searchTimedOut ?? this.searchTimedOut,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      bleDebugInfo:
          clearBleDebugInfo ? null : (bleDebugInfo ?? this.bleDebugInfo),
    );
  }

  @override
  List<Object?> get props => [
        status,
        users,
        filteredUsers,
        filter,
        rangeMode,
        isDiscovering,
        searchTimedOut,
        errorMessage,
        bleDebugInfo,
      ];
}
