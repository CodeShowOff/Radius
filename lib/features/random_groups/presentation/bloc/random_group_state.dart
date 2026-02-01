part of 'random_group_bloc.dart';

/// Status of the RandomGroupBloc.
enum RandomGroupBlocStatus {
  initial,
  loading,
  loaded,
  creating,
  created,
  joining,
  joined,
  error,
}

/// Membership status for a user in a group.
enum UserMembershipStatus {
  unknown,
  notMember,
  pending,
  member,
  admin,
  creator,
}

/// State for the RandomGroupBloc.
class RandomGroupState extends Equatable {
  /// Current status of the bloc.
  final RandomGroupBlocStatus status;

  /// All active random groups (for discovery).
  final List<RandomGroup> activeGroups;

  /// Groups the user is a member of.
  final List<RandomGroup> userGroups;

  /// Groups created by the user.
  final List<RandomGroup> userCreatedGroups;

  /// Currently selected/viewing group.
  final RandomGroup? selectedGroup;

  /// Members of the selected group.
  final List<RandomGroupMember> selectedGroupMembers;

  /// Pending join requests for the selected group (admin only).
  final List<JoinRequest> pendingRequests;

  /// User's membership status for the selected group.
  final UserMembershipStatus membershipStatus;

  /// User's join request (if any).
  final JoinRequest? userJoinRequest;

  /// Error message if any.
  final String? errorMessage;

  const RandomGroupState({
    this.status = RandomGroupBlocStatus.initial,
    this.activeGroups = const [],
    this.userGroups = const [],
    this.userCreatedGroups = const [],
    this.selectedGroup,
    this.selectedGroupMembers = const [],
    this.pendingRequests = const [],
    this.membershipStatus = UserMembershipStatus.unknown,
    this.userJoinRequest,
    this.errorMessage,
  });

  /// Creates a copy with updated fields.
  RandomGroupState copyWith({
    RandomGroupBlocStatus? status,
    List<RandomGroup>? activeGroups,
    List<RandomGroup>? userGroups,
    List<RandomGroup>? userCreatedGroups,
    RandomGroup? selectedGroup,
    List<RandomGroupMember>? selectedGroupMembers,
    List<JoinRequest>? pendingRequests,
    UserMembershipStatus? membershipStatus,
    JoinRequest? userJoinRequest,
    String? errorMessage,
    bool clearError = false,
    bool clearSelectedGroup = false,
    bool clearUserJoinRequest = false,
  }) {
    return RandomGroupState(
      status: status ?? this.status,
      activeGroups: activeGroups ?? this.activeGroups,
      userGroups: userGroups ?? this.userGroups,
      userCreatedGroups: userCreatedGroups ?? this.userCreatedGroups,
      selectedGroup:
          clearSelectedGroup ? null : (selectedGroup ?? this.selectedGroup),
      selectedGroupMembers:
          selectedGroupMembers ?? this.selectedGroupMembers,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      membershipStatus: membershipStatus ?? this.membershipStatus,
      userJoinRequest: clearUserJoinRequest
          ? null
          : (userJoinRequest ?? this.userJoinRequest),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        activeGroups,
        userGroups,
        userCreatedGroups,
        selectedGroup,
        selectedGroupMembers,
        pendingRequests,
        membershipStatus,
        userJoinRequest,
        errorMessage,
      ];
}
