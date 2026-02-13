part of 'discovery_bloc.dart';

/// Status of the discovery bloc.
enum DiscoveryStatus {
  initial,
  loading,
  loaded,
  searching,
  searchResult,
  searchNoResult,
  searchError,
  error,
}

/// Status of username availability check.
enum UsernameCheckStatus {
  idle,
  checking,
  available,
  taken,
  invalid,
}

/// State for the discovery bloc.
class DiscoveryState extends Equatable {
  /// Current status.
  final DiscoveryStatus status;

  /// Current user's ID.
  final String? userId;

  /// Search query.
  final String searchQuery;

  /// Search result (single user from exact username match).
  final Map<String, dynamic>? searchResult;

  /// Prefix search results (multiple users).
  final List<Map<String, dynamic>> searchResults;

  /// Received discovery connection requests.
  final List<ConnectionRequest> receivedRequests;

  /// Sent discovery connection requests.
  final List<ConnectionRequest> sentRequests;

  /// Username availability check status.
  final UsernameCheckStatus usernameCheckStatus;

  /// Username validation error (format issues).
  final String? usernameError;

  /// Error message.
  final String? errorMessage;

  /// Success message.
  final String? successMessage;

  /// Whether an action is in progress.
  final bool isActionLoading;

  /// ID of request being processed.
  final String? processingId;

  const DiscoveryState({
    this.status = DiscoveryStatus.initial,
    this.userId,
    this.searchQuery = '',
    this.searchResult,
    this.searchResults = const [],
    this.receivedRequests = const [],
    this.sentRequests = const [],
    this.usernameCheckStatus = UsernameCheckStatus.idle,
    this.usernameError,
    this.errorMessage,
    this.successMessage,
    this.isActionLoading = false,
    this.processingId,
  });

  /// Number of pending received discovery requests.
  int get pendingRequestCount => receivedRequests.length;

  /// Gets sent request to a specific user.
  ConnectionRequest? getSentRequestTo(String userId) {
    try {
      return sentRequests.firstWhere((r) => r.receiverId == userId);
    } catch (_) {
      return null;
    }
  }

  /// Gets received request from a specific user.
  ConnectionRequest? getReceivedRequestFrom(String userId) {
    try {
      return receivedRequests.firstWhere((r) => r.senderId == userId);
    } catch (_) {
      return null;
    }
  }

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    String? userId,
    String? searchQuery,
    Map<String, dynamic>? searchResult,
    bool clearSearchResult = false,
    List<Map<String, dynamic>>? searchResults,
    List<ConnectionRequest>? receivedRequests,
    List<ConnectionRequest>? sentRequests,
    UsernameCheckStatus? usernameCheckStatus,
    String? usernameError,
    bool clearUsernameError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? successMessage,
    bool clearSuccessMessage = false,
    bool? isActionLoading,
    String? processingId,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResult:
          clearSearchResult ? null : (searchResult ?? this.searchResult),
      searchResults: searchResults ?? this.searchResults,
      receivedRequests: receivedRequests ?? this.receivedRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      usernameCheckStatus:
          usernameCheckStatus ?? this.usernameCheckStatus,
      usernameError:
          clearUsernameError ? null : (usernameError ?? this.usernameError),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearSuccessMessage ? null : (successMessage ?? this.successMessage),
      isActionLoading: isActionLoading ?? this.isActionLoading,
      processingId: processingId,
    );
  }

  @override
  List<Object?> get props => [
        status,
        userId,
        searchQuery,
        searchResult,
        searchResults,
        receivedRequests,
        sentRequests,
        usernameCheckStatus,
        usernameError,
        errorMessage,
        successMessage,
        isActionLoading,
        processingId,
      ];
}
