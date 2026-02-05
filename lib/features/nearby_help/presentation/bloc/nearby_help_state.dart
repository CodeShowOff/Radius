part of 'nearby_help_bloc.dart';

/// Status of the nearby help bloc.
enum NearbyHelpStatus {
  initial,
  loading,
  loaded,
  creating,
  accepting,
  updating,
  error,
}

/// State for the nearby help feature.
class NearbyHelpState extends Equatable {
  /// Current status of the bloc.
  final NearbyHelpStatus status;

  /// Current user ID.
  final String? userId;

  /// Current user name.
  final String? userName;

  /// Current user photo URL.
  final String? userPhotoUrl;

  /// User's saved locations (home/work).
  final List<UserLocation> savedLocations;

  /// User's help alert settings.
  final NearbyHelpSettings? settings;

  /// User's active help request (as seeker).
  final HelpRequest? activeRequest;

  /// Currently viewed help request (e.g., from notification).
  final HelpRequest? viewedRequest;

  /// Active help requests where user is the helper.
  final List<HelpRequest> helperRequests;

  /// Incoming/open help requests from others that user can help with.
  final List<HelpRequest> incomingRequests;

  /// Error message if any.
  final String? errorMessage;

  /// Success message for displaying snackbars.
  final String? successMessage;

  const NearbyHelpState({
    this.status = NearbyHelpStatus.initial,
    this.userId,
    this.userName,
    this.userPhotoUrl,
    this.savedLocations = const [],
    this.settings,
    this.activeRequest,
    this.viewedRequest,
    this.helperRequests = const [],
    this.incomingRequests = const [],
    this.errorMessage,
    this.successMessage,
  });

  /// Whether the user has any saved locations.
  bool get hasLocations => savedLocations.isNotEmpty;

  /// Whether the user has opted in for help alerts.
  bool get receiveHelpAlerts => settings?.receiveHelpAlerts ?? true;

  /// Get home location if saved.
  UserLocation? get homeLocation => savedLocations
      .where((l) => l.type == LocationType.home)
      .firstOrNull;

  /// Get work location if saved.
  UserLocation? get workLocation => savedLocations
      .where((l) => l.type == LocationType.work)
      .firstOrNull;

  /// Whether the user has an active request as seeker.
  bool get hasActiveRequest => activeRequest != null && activeRequest!.isActive;

  /// Whether the user is currently helping someone.
  bool get isHelping => helperRequests.isNotEmpty;

  /// Whether there are incoming help requests.
  bool get hasIncomingRequests => incomingRequests.isNotEmpty;

  /// Count of incoming help requests.
  int get incomingRequestsCount => incomingRequests.length;

  NearbyHelpState copyWith({
    NearbyHelpStatus? status,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    List<UserLocation>? savedLocations,
    NearbyHelpSettings? settings,
    HelpRequest? activeRequest,
    HelpRequest? viewedRequest,
    List<HelpRequest>? helperRequests,
    List<HelpRequest>? incomingRequests,
    String? errorMessage,
    String? successMessage,
    bool clearActiveRequest = false,
    bool clearViewedRequest = false,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return NearbyHelpState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      savedLocations: savedLocations ?? this.savedLocations,
      settings: settings ?? this.settings,
      activeRequest: clearActiveRequest ? null : (activeRequest ?? this.activeRequest),
      viewedRequest: clearViewedRequest ? null : (viewedRequest ?? this.viewedRequest),
      helperRequests: helperRequests ?? this.helperRequests,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        userId,
        userName,
        userPhotoUrl,
        savedLocations,
        settings,
        activeRequest,
        viewedRequest,
        helperRequests,
        incomingRequests,
        errorMessage,
        successMessage,
      ];
}
