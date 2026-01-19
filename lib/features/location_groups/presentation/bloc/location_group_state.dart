part of 'location_group_bloc.dart';

/// Status of the group operations.
enum GroupBlocStatus {
  initial,
  loading,
  loaded,
  creating,
  joining,
  leaving,
  error,
}

/// State for the LocationGroupBloc.
class LocationGroupState extends Equatable {
  final GroupBlocStatus status;

  /// Currently browsing location.
  final String? selectedCountryCode;
  final String? selectedStateCode;

  /// Groups in the currently selected location.
  final List<LocationGroup> locationGroups;

  /// User's joined groups.
  final List<LocationGroup> userGroups;

  /// Currently viewed group details.
  final LocationGroup? currentGroup;

  /// Current user's membership in the viewed group.
  final GroupMembership? currentMembership;

  /// Members of the current group.
  final List<GroupMembership> groupMembers;

  /// Pending join requests (admin view).
  final List<GroupJoinRequest> joinRequests;

  /// Sort option for group listing.
  final GroupSortOption sortBy;

  /// Error message if any.
  final String? errorMessage;

  /// Recently created group (for navigation).
  final LocationGroup? createdGroup;

  /// Whether the user has a pending request for the current group.
  final bool hasPendingRequest;

  const LocationGroupState({
    this.status = GroupBlocStatus.initial,
    this.selectedCountryCode,
    this.selectedStateCode,
    this.locationGroups = const [],
    this.userGroups = const [],
    this.currentGroup,
    this.currentMembership,
    this.groupMembers = const [],
    this.joinRequests = const [],
    this.sortBy = GroupSortOption.mostActive,
    this.errorMessage,
    this.createdGroup,
    this.hasPendingRequest = false,
  });

  bool get isLoading =>
      status == GroupBlocStatus.loading ||
      status == GroupBlocStatus.creating ||
      status == GroupBlocStatus.joining ||
      status == GroupBlocStatus.leaving;

  bool get hasError => status == GroupBlocStatus.error;

  bool get isMember => currentMembership?.isActive ?? false;

  bool get isAdmin => currentMembership?.isAdmin ?? false;

  LocationGroupState copyWith({
    GroupBlocStatus? status,
    String? selectedCountryCode,
    String? selectedStateCode,
    List<LocationGroup>? locationGroups,
    List<LocationGroup>? userGroups,
    LocationGroup? currentGroup,
    GroupMembership? currentMembership,
    List<GroupMembership>? groupMembers,
    List<GroupJoinRequest>? joinRequests,
    GroupSortOption? sortBy,
    String? errorMessage,
    LocationGroup? createdGroup,
    bool? hasPendingRequest,
  }) {
    return LocationGroupState(
      status: status ?? this.status,
      selectedCountryCode: selectedCountryCode ?? this.selectedCountryCode,
      selectedStateCode: selectedStateCode ?? this.selectedStateCode,
      locationGroups: locationGroups ?? this.locationGroups,
      userGroups: userGroups ?? this.userGroups,
      currentGroup: currentGroup ?? this.currentGroup,
      currentMembership: currentMembership ?? this.currentMembership,
      groupMembers: groupMembers ?? this.groupMembers,
      joinRequests: joinRequests ?? this.joinRequests,
      sortBy: sortBy ?? this.sortBy,
      errorMessage: errorMessage,
      createdGroup: createdGroup,
      hasPendingRequest: hasPendingRequest ?? this.hasPendingRequest,
    );
  }

  @override
  List<Object?> get props => [
        status,
        selectedCountryCode,
        selectedStateCode,
        locationGroups,
        userGroups,
        currentGroup,
        currentMembership,
        groupMembers,
        joinRequests,
        sortBy,
        errorMessage,
        createdGroup,
        hasPendingRequest,
      ];
}
