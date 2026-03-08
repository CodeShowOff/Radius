part of 'create_post_bloc.dart';

/// Status of the post creation process.
enum CreatePostStatus {
  /// Initial idle state — user is composing.
  idle,

  /// Media files are being optimized (compressed/resized).
  optimizing,

  /// Media is being uploaded / post is being created.
  uploading,

  /// Post created successfully.
  success,

  /// An error occurred during creation.
  error,
}

/// A media item selected by the user but not yet uploaded.
class SelectedMedia extends Equatable {
  /// Local file reference.
  final File file;

  /// Whether this is an image or video.
  final PostMediaType type;

  const SelectedMedia({
    required this.file,
    required this.type,
  });

  @override
  List<Object?> get props => [file.path, type];
}

/// State for the create post flow.
class CreatePostState extends Equatable {
  /// Media items selected by the user.
  final List<SelectedMedia> selectedMedia;

  /// Post text/caption.
  final String text;

  /// Visibility setting.
  final PostVisibility visibility;

  /// Aggregate upload progress (0.0 to 1.0).
  final double uploadProgress;

  /// Current status of the creation process.
  final CreatePostStatus status;

  /// Error message if status is error.
  final String? errorMessage;

  const CreatePostState({
    this.selectedMedia = const [],
    this.text = '',
    this.visibility = PostVisibility.public,
    this.uploadProgress = 0.0,
    this.status = CreatePostStatus.idle,
    this.errorMessage,
  });

  /// Whether the post can be submitted (has text or media).
  bool get canSubmit =>
      status == CreatePostStatus.idle &&
      (text.trim().isNotEmpty || selectedMedia.isNotEmpty);

  /// Whether media can still be added (max 10).
  bool get canAddMedia => selectedMedia.length < 10;

  CreatePostState copyWith({
    List<SelectedMedia>? selectedMedia,
    String? text,
    PostVisibility? visibility,
    double? uploadProgress,
    CreatePostStatus? status,
    String? errorMessage,
  }) {
    return CreatePostState(
      selectedMedia: selectedMedia ?? this.selectedMedia,
      text: text ?? this.text,
      visibility: visibility ?? this.visibility,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        selectedMedia,
        text,
        visibility,
        uploadProgress,
        status,
        errorMessage,
      ];
}
