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
  final String? selectedCountryName;
  final String? selectedCityName;

  /// Groups in the currently selected location.
  final List<LocationGroup> locationGroups;

  /// User's joined groups.
  final List<LocationGroup> userGroups;
  
  /// The user ID whose groups are currently loaded (for avoiding redundant reloads).
  final String? userGroupsUserId;

  /// Unread counts per group for the current user (groupId -> count).
  final Map<String, int> userGroupUnreadCounts;

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

  /// Flag to indicate a group was successfully deleted (for navigation).
  final bool groupDeleted;

  /// Flag to indicate the user successfully left a group (for navigation).
  final bool groupLeft;

  /// The current user's ID for the group detail view.
  /// Used to reactively update currentMembership when groupMembers changes.
  final String? currentGroupUserId;

  const LocationGroupState({
    this.status = GroupBlocStatus.initial,
    this.selectedCountryName,
    this.selectedCityName,
    this.locationGroups = const [],
    this.userGroups = const [],
    this.userGroupsUserId,
    this.userGroupUnreadCounts = const {},
    this.currentGroup,
    this.currentMembership,
    this.groupMembers = const [],
    this.joinRequests = const [],
    this.sortBy = GroupSortOption.mostActive,
    this.errorMessage,
    this.createdGroup,
    this.hasPendingRequest = false,
    this.groupDeleted = false,
    this.groupLeft = false,
    this.currentGroupUserId,
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
    String? selectedCountryName,
    String? selectedCityName,
    List<LocationGroup>? locationGroups,
    List<LocationGroup>? userGroups,
    String? userGroupsUserId,
    Map<String, int>? userGroupUnreadCounts,
    LocationGroup? currentGroup,
    GroupMembership? currentMembership,
    bool clearCurrentMembership = false,
    List<GroupMembership>? groupMembers,
    List<GroupJoinRequest>? joinRequests,
    GroupSortOption? sortBy,
    String? errorMessage,
    LocationGroup? createdGroup,
    bool? hasPendingRequest,
    bool? groupDeleted,
    bool? groupLeft,
    String? currentGroupUserId,
    bool clearCurrentGroupUserId = false,
  }) {
    return LocationGroupState(
      status: status ?? this.status,
      selectedCountryName: selectedCountryName ?? this.selectedCountryName,
      selectedCityName: selectedCityName ?? this.selectedCityName,
      locationGroups: locationGroups ?? this.locationGroups,
      userGroups: userGroups ?? this.userGroups,
      userGroupsUserId: userGroupsUserId ?? this.userGroupsUserId,
      userGroupUnreadCounts: userGroupUnreadCounts ?? this.userGroupUnreadCounts,
      currentGroup: currentGroup ?? this.currentGroup,
      currentMembership: clearCurrentMembership ? null : (currentMembership ?? this.currentMembership),
      groupMembers: groupMembers ?? this.groupMembers,
      joinRequests: joinRequests ?? this.joinRequests,
      sortBy: sortBy ?? this.sortBy,
      errorMessage: errorMessage,
      createdGroup: createdGroup,
      hasPendingRequest: hasPendingRequest ?? this.hasPendingRequest,
      groupDeleted: groupDeleted ?? this.groupDeleted,
      groupLeft: groupLeft ?? this.groupLeft,
      currentGroupUserId: clearCurrentGroupUserId ? null : (currentGroupUserId ?? this.currentGroupUserId),
    );
  }

  @override
  List<Object?> get props => [
        status,
        selectedCountryName,
        selectedCityName,
        locationGroups,
        userGroups,
        userGroupsUserId,
        userGroupUnreadCounts,
        currentGroup,
        currentMembership,
        groupMembers,
        joinRequests,
        sortBy,
        errorMessage,
        createdGroup,
        hasPendingRequest,
        groupDeleted,
        groupLeft,
        currentGroupUserId,
      ];
}
