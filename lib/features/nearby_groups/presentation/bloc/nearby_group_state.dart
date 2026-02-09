part of 'nearby_group_bloc.dart';

/// Status of the nearby group bloc UI state.
enum NearbyGroupBlocStatus {
  initial,
  loading,
  loaded,
  creating,
  created,
  scanning,
  error,
}

/// State for NearbyGroupBloc.
class NearbyGroupState extends Equatable {
  /// Current status
  final NearbyGroupBlocStatus status;

  /// List of all active nearby groups (for discovery)
  final List<NearbyGroup> activeGroups;

  /// List of groups the current user is a member of
  final List<NearbyGroup> userGroups;

  /// The user's own active group (if they created one)
  final NearbyGroup? myActiveGroup;

  /// Currently selected group details
  final NearbyGroup? selectedGroup;

  /// Members of the selected/active group
  final List<NearbyGroupMember> groupMembers;

  /// Whether the creator is currently scanning
  final bool isScanning;

  /// Error message if any
  final String? errorMessage;

  /// User ID for tracked groups (to detect account switches)
  final String? userGroupsUserId;

  const NearbyGroupState({
    this.status = NearbyGroupBlocStatus.initial,
    this.activeGroups = const [],
    this.userGroups = const [],
    this.myActiveGroup,
    this.selectedGroup,
    this.groupMembers = const [],
    this.isScanning = false,
    this.errorMessage,
    this.userGroupsUserId,
  });

  /// Whether currently loading
  bool get isLoading =>
      status == NearbyGroupBlocStatus.loading ||
      status == NearbyGroupBlocStatus.creating;

  /// Whether user has an active group they created
  bool get hasActiveGroup => myActiveGroup != null;

  NearbyGroupState copyWith({
    NearbyGroupBlocStatus? status,
    List<NearbyGroup>? activeGroups,
    List<NearbyGroup>? userGroups,
    NearbyGroup? myActiveGroup,
    bool clearMyActiveGroup = false,
    NearbyGroup? selectedGroup,
    bool clearSelectedGroup = false,
    List<NearbyGroupMember>? groupMembers,
    bool? isScanning,
    String? errorMessage,
    bool clearError = false,
    String? userGroupsUserId,
  }) {
    return NearbyGroupState(
      status: status ?? this.status,
      activeGroups: activeGroups ?? this.activeGroups,
      userGroups: userGroups ?? this.userGroups,
      myActiveGroup:
          clearMyActiveGroup ? null : (myActiveGroup ?? this.myActiveGroup),
      selectedGroup:
          clearSelectedGroup ? null : (selectedGroup ?? this.selectedGroup),
      groupMembers: groupMembers ?? this.groupMembers,
      isScanning: isScanning ?? this.isScanning,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      userGroupsUserId: userGroupsUserId ?? this.userGroupsUserId,
    );
  }

  @override
  List<Object?> get props => [
        status,
        activeGroups,
        userGroups,
        myActiveGroup,
        selectedGroup,
        groupMembers,
        isScanning,
        errorMessage,
        userGroupsUserId,
      ];
}
