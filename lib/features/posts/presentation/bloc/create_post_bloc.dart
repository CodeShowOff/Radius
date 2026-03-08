import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/services/media_optimizer.dart';
import '../../data/services/post_media_service.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/post.dart';
import '../../domain/repositories/i_post_repository.dart';

part 'create_post_event.dart';
part 'create_post_state.dart';

/// BLoC for the post creation flow.
///
/// Handles media selection, text/visibility changes, upload with progress,
/// and Firestore post creation.
class CreatePostBloc extends Bloc<CreatePostEvent, CreatePostState> {
  final IPostRepository _postRepository;
  final PostMediaService _mediaService;
  final MediaOptimizer _mediaOptimizer;
  final Logger _logger;

  CreatePostBloc({
    required IPostRepository postRepository,
    required PostMediaService mediaService,
    required MediaOptimizer mediaOptimizer,
    Logger? logger,
  })  : _postRepository = postRepository,
        _mediaService = mediaService,
        _mediaOptimizer = mediaOptimizer,
        _logger = logger ?? Logger(),
        super(const CreatePostState()) {
    on<CreatePostMediaAdded>(_onMediaAdded);
    on<CreatePostMediaRemoved>(_onMediaRemoved);
    on<CreatePostTextChanged>(_onTextChanged);
    on<CreatePostVisibilityChanged>(_onVisibilityChanged);
    on<CreatePostSubmitted>(_onSubmitted);
  }

  void _onMediaAdded(
    CreatePostMediaAdded event,
    Emitter<CreatePostState> emit,
  ) {
    final currentMedia = List<SelectedMedia>.from(state.selectedMedia);
    final remaining = 10 - currentMedia.length;
    if (remaining <= 0) return;

    // Determine media type from file extension
    final newMedia = event.files.take(remaining).map((file) {
      final ext = file.path.split('.').last.toLowerCase();
      final type = ['mp4', 'mov', 'avi'].contains(ext)
          ? PostMediaType.video
          : PostMediaType.image;
      return SelectedMedia(file: file, type: type);
    }).toList();

    emit(state.copyWith(
      selectedMedia: [...currentMedia, ...newMedia],
    ));
  }

  void _onMediaRemoved(
    CreatePostMediaRemoved event,
    Emitter<CreatePostState> emit,
  ) {
    if (event.index < 0 || event.index >= state.selectedMedia.length) return;

    final updated = List<SelectedMedia>.from(state.selectedMedia)
      ..removeAt(event.index);
    emit(state.copyWith(selectedMedia: updated));
  }

  void _onTextChanged(
    CreatePostTextChanged event,
    Emitter<CreatePostState> emit,
  ) {
    emit(state.copyWith(text: event.text));
  }

  void _onVisibilityChanged(
    CreatePostVisibilityChanged event,
    Emitter<CreatePostState> emit,
  ) {
    emit(state.copyWith(visibility: event.visibility));
  }

  Future<void> _onSubmitted(
    CreatePostSubmitted event,
    Emitter<CreatePostState> emit,
  ) async {
    if (!state.canSubmit) return;

    // ─── Optimize media ───────────────────────────────────────────────
    emit(state.copyWith(
      status: CreatePostStatus.optimizing,
      uploadProgress: 0.0,
    ));

    final optimizedMedia = <SelectedMedia>[];

    try {
      for (var i = 0; i < state.selectedMedia.length; i++) {
        final media = state.selectedMedia[i];

        if (media.type == PostMediaType.image) {
          final result = await _mediaOptimizer.optimizeImage(media.file);
          optimizedMedia.add(SelectedMedia(
            file: result.file,
            type: media.type,
          ));
        } else {
          final result = await _mediaOptimizer.optimizeVideo(media.file);
          optimizedMedia.add(SelectedMedia(
            file: result.file,
            type: media.type,
          ));
        }

        if (!isClosed) {
          emit(state.copyWith(
            status: CreatePostStatus.optimizing,
            uploadProgress:
                (i + 1) / (state.selectedMedia.isNotEmpty ? state.selectedMedia.length : 1),
          ));
        }
      }
    } catch (e, stack) {
      _logger.e('Media optimization failed', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: CreatePostStatus.error,
        errorMessage: e.toString(),
      ));
      return;
    }

    // ─── Upload ───────────────────────────────────────────────────────
    emit(state.copyWith(
      status: CreatePostStatus.uploading,
      uploadProgress: 0.0,
    ));

    try {
      // Generate a post ID for organizing media uploads
      final postId = _mediaService.generatePostId();

      // Upload media files
      final mediaItems = <Map<String, dynamic>>[];
      final totalFiles = optimizedMedia.length;

      for (var i = 0; i < optimizedMedia.length; i++) {
        final media = optimizedMedia[i];

        PostUploadResult result;
        String? thumbnailUrl;

        if (media.type == PostMediaType.video) {
          result = await _mediaService.uploadVideo(
            file: media.file,
            authorId: _authorId!,
            postId: postId,
          );

          // Generate & upload video thumbnail
          final thumbFile =
              await _mediaOptimizer.generateVideoThumbnail(media.file.path);
          if (thumbFile != null) {
            final thumbResult = await _mediaService.uploadThumbnail(
              file: thumbFile,
              authorId: _authorId!,
              postId: postId,
            );
            thumbnailUrl = thumbResult.downloadUrl;
          }
        } else {
          result = await _mediaService.uploadImage(
            file: media.file,
            authorId: _authorId!,
            postId: postId,
          );
        }

        final item = <String, dynamic>{
          'url': result.downloadUrl,
          'type': media.type,
          'storagePath': result.storagePath,
        };
        if (thumbnailUrl != null) {
          item['thumbnailUrl'] = thumbnailUrl;
        }

        mediaItems.add(item);

        // Update progress after each file upload completes
        if (!isClosed) {
          emit(state.copyWith(
            status: CreatePostStatus.uploading,
            uploadProgress: (i + 1) / (totalFiles > 0 ? totalFiles : 1),
          ));
        }
      }

      // Create the post in Firestore
      final createResult = await _postRepository.createPost(
        authorId: _authorId!,
        authorName: _authorName!,
        authorPhotoUrl: _authorPhotoUrl,
        text: state.text.trim().isNotEmpty ? state.text.trim() : null,
        mediaItems: mediaItems,
        visibility: state.visibility,
        connectionIds: _connectionIds,
      );

      createResult.fold(
        (failure) {
          _logger.e('Failed to create post: ${failure.message}');
          emit(state.copyWith(
            status: CreatePostStatus.error,
            errorMessage: failure.message,
          ));
        },
        (post) {
          _logger.i('Post created successfully: ${post.id}');
          emit(state.copyWith(
            status: CreatePostStatus.success,
            uploadProgress: 1.0,
          ));
        },
      );
    } catch (e, stack) {
      _logger.e('Error creating post', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: CreatePostStatus.error,
        errorMessage: e.toString(),
      ));
    } finally {
      _mediaOptimizer.dispose();
    }
  }

  // ─── User context (set before submitting) ──────────────────────────

  String? _authorId;
  String? _authorName;
  String? _authorPhotoUrl;
  List<String> _connectionIds = const [];

  /// Sets the current user's info for post creation.
  /// Call this when the page initializes with auth context.
  void setAuthorInfo({
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
  }) {
    _authorId = authorId;
    _authorName = authorName;
    _authorPhotoUrl = authorPhotoUrl;
  }

  /// Sets the current user's connection IDs for connections-visibility posts.
  void setConnectionIds(List<String> connectionIds) {
    _connectionIds = connectionIds;
  }
}
