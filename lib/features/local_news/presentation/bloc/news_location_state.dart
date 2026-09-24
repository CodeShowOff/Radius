part of 'news_location_bloc.dart';

/// Status of the news location setup flow.
enum NewsLocationStatus {
  /// Initial state â€” checking for saved location.
  initial,

  /// Loading / checking saved location.
  loading,

  /// No saved location â€” show setup UI.
  needsSetup,

  /// Location selected â€” awaiting user confirmation.
  detected,

  /// Saving location to Firestore.
  saving,

  /// Location saved and ready â€” navigate to feed.
  ready,

  /// An error occurred.
  error,
}

/// State for the news location setup flow.
class NewsLocationState extends Equatable {
  /// Current status.
  final NewsLocationStatus status;

  /// The resolved / saved news location.
  final NewsLocation? location;

  /// Error message if status is error.
  final String? errorMessage;

  const NewsLocationState({
    this.status = NewsLocationStatus.initial,
    this.location,
    this.errorMessage,
  });

  /// Whether the user has a confirmed location ready for the feed.
  bool get hasLocation =>
      location != null && status == NewsLocationStatus.ready;

  /// Whether an operation is in progress.
  bool get isLoading =>
      status == NewsLocationStatus.loading ||
      status == NewsLocationStatus.saving;

  NewsLocationState copyWith({
    NewsLocationStatus? status,
    NewsLocation? location,
    String? errorMessage,
    bool clearLocation = false,
    bool clearError = false,
  }) {
    return NewsLocationState(
      status: status ?? this.status,
      location: clearLocation ? null : (location ?? this.location),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, location, errorMessage];
}
