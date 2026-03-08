part of 'create_news_post_bloc.dart';

/// Status of the news post creation process.
enum CreateNewsPostStatus {
  /// Initial idle state — user is composing.
  idle,

  /// Live GPS detection + reverse geocoding in progress.
  detectingLocation,

  /// Location detected — brief confirmation before proceeding.
  locationDetected,

  /// Media files are being optimized (compressed/resized).
  optimizing,

  /// Media is being uploaded to Firebase Storage.
  uploading,

  /// Firestore document is being created.
  creating,

  /// Post created successfully.
  success,

  /// An error occurred during creation.
  error,
}

/// A media item selected by the user but not yet uploaded.
class SelectedNewsMedia extends Equatable {
  /// Local file reference.
  final File file;

  /// Whether this is an image or video.
  final PostMediaType type;

  const SelectedNewsMedia({
    required this.file,
    required this.type,
  });

  @override
  List<Object?> get props => [file.path, type];
}

/// State for the create news post flow.
class CreateNewsPostState extends Equatable {
  /// Media items selected by the user.
  final List<SelectedNewsMedia> selectedMedia;

  /// Post text/caption.
  final String text;

  /// Aggregate progress (0.0 to 1.0) for current operation.
  final double progress;

  /// Current status of the creation process.
  final CreateNewsPostStatus status;

  /// Detected location (populated after GPS detection).
  final NewsLocation? detectedLocation;

  /// Error message if status is error.
  final String? errorMessage;

  const CreateNewsPostState({
    this.selectedMedia = const [],
    this.text = '',
    this.progress = 0.0,
    this.status = CreateNewsPostStatus.idle,
    this.detectedLocation,
    this.errorMessage,
  });

  /// Whether the post can be submitted (has text or media, and is idle).
  bool get canSubmit =>
      status == CreateNewsPostStatus.idle &&
      (text.trim().isNotEmpty || selectedMedia.isNotEmpty);

  /// Whether media can still be added (max 10).
  bool get canAddMedia => selectedMedia.length < 10;

  /// Whether any processing is in progress.
  bool get isBusy =>
      status == CreateNewsPostStatus.detectingLocation ||
      status == CreateNewsPostStatus.optimizing ||
      status == CreateNewsPostStatus.uploading ||
      status == CreateNewsPostStatus.creating;

  CreateNewsPostState copyWith({
    List<SelectedNewsMedia>? selectedMedia,
    String? text,
    double? progress,
    CreateNewsPostStatus? status,
    NewsLocation? detectedLocation,
    String? errorMessage,
    bool clearLocation = false,
    bool clearError = false,
  }) {
    return CreateNewsPostState(
      selectedMedia: selectedMedia ?? this.selectedMedia,
      text: text ?? this.text,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      detectedLocation:
          clearLocation ? null : (detectedLocation ?? this.detectedLocation),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        selectedMedia,
        text,
        progress,
        status,
        detectedLocation,
        errorMessage,
      ];
}
