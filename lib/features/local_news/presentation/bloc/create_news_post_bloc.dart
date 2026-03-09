import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../../posts/data/services/media_optimizer.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../data/services/geocoding_service.dart';
import '../../data/services/news_location_service.dart';
import '../../data/services/news_media_service.dart';
import '../../data/services/news_post_service.dart';
import '../../domain/entities/news_location.dart';
import '../../domain/repositories/i_news_post_repository.dart';

part 'create_news_post_event.dart';
part 'create_news_post_state.dart';

/// BLoC for the news post creation flow.
///
/// Key rule: When submitting, the BLoC **always** requests live GPS first.
/// The post is tagged with the GPS-derived district/city/locality.
/// No manual override for post creation — this ensures location integrity.
///
/// Flow: compose → submit → GPS detect → optimize media → upload → create doc
class CreateNewsPostBloc
    extends Bloc<CreateNewsPostEvent, CreateNewsPostState> {
  final INewsPostRepository _repository;
  final NewsMediaService _mediaService;
  final NewsLocationService _locationService;
  final MediaOptimizer _mediaOptimizer;
  final NewsPostService _newsPostService;
  final Logger _logger;

  /// The type of post being created: 'post' or 'reel'.
  final String postType;

  /// Maximum number of local news posts + reels a user can create per day.
  static const int maxNewsPostsPerDay = 3;

  CreateNewsPostBloc({
    required INewsPostRepository repository,
    required NewsMediaService mediaService,
    required NewsLocationService locationService,
    required MediaOptimizer mediaOptimizer,
    required NewsPostService newsPostService,
    this.postType = 'post',
    Logger? logger,
  })  : _repository = repository,
        _mediaService = mediaService,
        _locationService = locationService,
        _mediaOptimizer = mediaOptimizer,
        _newsPostService = newsPostService,
        _logger = logger ?? Logger(),
        super(const CreateNewsPostState()) {
    on<CreateNewsPostMediaAdded>(_onMediaAdded);
    on<CreateNewsPostMediaRemoved>(_onMediaRemoved);
    on<CreateNewsPostTextChanged>(_onTextChanged);
    on<CreateNewsPostSubmitted>(_onSubmitted);
    on<CreateNewsPostLocationRetry>(_onLocationRetry);
  }

  // ─── User context (set before submitting) ──────────────────────────

  String? _authorId;
  String? _authorName;
  String? _authorPhotoUrl;

  /// Sets the current user's info for post creation.
  void setAuthorInfo({
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
  }) {
    _authorId = authorId;
    _authorName = authorName;
    _authorPhotoUrl = authorPhotoUrl;
  }

  // ─── Event handlers ────────────────────────────────────────────────

  /// Whether this BLoC is creating a reel.
  bool get isReel => postType == 'reel';

  void _onMediaAdded(
    CreateNewsPostMediaAdded event,
    Emitter<CreateNewsPostState> emit,
  ) {
    final currentMedia = List<SelectedNewsMedia>.from(state.selectedMedia);

    // Reels allow exactly 1 video
    if (isReel) {
      if (currentMedia.isNotEmpty) return;

      final file = event.files.first;
      final ext = file.path.split('.').last.toLowerCase();
      final type = ['mp4', 'mov', 'avi'].contains(ext)
          ? PostMediaType.video
          : PostMediaType.image;

      if (type != PostMediaType.video) {
        emit(state.copyWith(
          status: CreateNewsPostStatus.error,
          errorMessage: 'Reels only support video files.',
        ));
        return;
      }

      emit(state.copyWith(
        selectedMedia: [SelectedNewsMedia(file: file, type: type)],
        status: CreateNewsPostStatus.idle,
      ));
      return;
    }

    final remaining = 10 - currentMedia.length;
    if (remaining <= 0) return;

    final newMedia = event.files.take(remaining).map((file) {
      final ext = file.path.split('.').last.toLowerCase();
      final type = ['mp4', 'mov', 'avi'].contains(ext)
          ? PostMediaType.video
          : PostMediaType.image;
      return SelectedNewsMedia(file: file, type: type);
    }).toList();

    emit(state.copyWith(
      selectedMedia: [...currentMedia, ...newMedia],
    ));
  }

  void _onMediaRemoved(
    CreateNewsPostMediaRemoved event,
    Emitter<CreateNewsPostState> emit,
  ) {
    if (event.index < 0 || event.index >= state.selectedMedia.length) return;

    final updated = List<SelectedNewsMedia>.from(state.selectedMedia)
      ..removeAt(event.index);
    emit(state.copyWith(selectedMedia: updated));
  }

  void _onTextChanged(
    CreateNewsPostTextChanged event,
    Emitter<CreateNewsPostState> emit,
  ) {
    emit(state.copyWith(text: event.text));
  }

  Future<void> _onSubmitted(
    CreateNewsPostSubmitted event,
    Emitter<CreateNewsPostState> emit,
  ) async {
    if (!state.canSubmit || _authorId == null) return;

    // ─── Rate limit check ─────────────────────────────────────────────
    try {
      final todayCount =
          await _newsPostService.countTodayPostsByAuthor(_authorId!);
      if (todayCount >= maxNewsPostsPerDay) {
        emit(state.copyWith(
          status: CreateNewsPostStatus.error,
          errorMessage:
              'Daily limit reached. You can only create $maxNewsPostsPerDay local news posts and reels per day.',
        ));
        return;
      }
    } catch (e) {
      _logger.w('Rate limit check failed, allowing post', error: e);
    }

    // Reel-specific pre-validation
    if (isReel) {
      if (state.selectedMedia.length != 1 ||
          state.selectedMedia.first.type != PostMediaType.video) {
        emit(state.copyWith(
          status: CreateNewsPostStatus.error,
          errorMessage: 'A reel requires exactly one video.',
        ));
        return;
      }
    }

    // ─── Step 1: Detect live GPS location ─────────────────────────
    emit(state.copyWith(
      status: CreateNewsPostStatus.detectingLocation,
      progress: 0.0,
      clearError: true,
    ));

    NewsLocation location;
    try {
      location = await _locationService.detectCurrentLocation();
      _logger.i('News post location: ${location.shortDisplayString}');

      if (isClosed) return;
      emit(state.copyWith(
        status: CreateNewsPostStatus.locationDetected,
        detectedLocation: location,
      ));
    } on LocationServiceException catch (e) {
      _logger.w('Location detection failed: ${e.message}');
      emit(state.copyWith(
        status: CreateNewsPostStatus.error,
        errorMessage: e.message,
        locationFailureReason: e.reason,
      ));
      return;
    } on GeocodingException catch (e) {
      _logger.w('Geocoding failed: ${e.message}');
      emit(state.copyWith(
        status: CreateNewsPostStatus.error,
        errorMessage: 'Could not determine your location name. '
            'Please try again.',
      ));
      return;
    } catch (e, stack) {
      _logger.e('Unexpected location error', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: CreateNewsPostStatus.error,
        errorMessage: 'Failed to detect location. Please try again.',
      ));
      return;
    }

    // ─── Step 2: Optimize media ───────────────────────────────────
    final optimizedMedia = <SelectedNewsMedia>[];

    if (state.selectedMedia.isNotEmpty) {
      emit(state.copyWith(
        status: CreateNewsPostStatus.optimizing,
        progress: 0.0,
      ));

      try {
        for (var i = 0; i < state.selectedMedia.length; i++) {
          final media = state.selectedMedia[i];

          if (media.type == PostMediaType.image) {
            final result = await _mediaOptimizer.optimizeImage(media.file);
            optimizedMedia.add(SelectedNewsMedia(
              file: result.file,
              type: media.type,
            ));
          } else if (isReel) {
            final result = await _mediaOptimizer.optimizeReelVideo(media.file);
            optimizedMedia.add(SelectedNewsMedia(
              file: result.file,
              type: media.type,
            ));
          } else {
            final result = await _mediaOptimizer.optimizeVideo(media.file);
            optimizedMedia.add(SelectedNewsMedia(
              file: result.file,
              type: media.type,
            ));
          }

          if (!isClosed) {
            emit(state.copyWith(
              status: CreateNewsPostStatus.optimizing,
              progress: (i + 1) / state.selectedMedia.length,
            ));
          }
        }
      } catch (e, stack) {
        _logger.e('Media optimization failed', error: e, stackTrace: stack);
        emit(state.copyWith(
          status: CreateNewsPostStatus.error,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    // ─── Step 3: Upload media ─────────────────────────────────────
    emit(state.copyWith(
      status: CreateNewsPostStatus.uploading,
      progress: 0.0,
    ));

    try {
      final postId = _mediaService.generatePostId();
      final mediaItems = <Map<String, dynamic>>[];
      final totalFiles = optimizedMedia.length;

      for (var i = 0; i < optimizedMedia.length; i++) {
        final media = optimizedMedia[i];

        NewsUploadResult result;
        String? thumbnailUrl;

        if (media.type == PostMediaType.video) {
          if (isReel) {
            result = await _mediaService.uploadReel(
              file: media.file,
              authorId: _authorId!,
              postId: postId,
            );
          } else {
            result = await _mediaService.uploadVideo(
              file: media.file,
              authorId: _authorId!,
              postId: postId,
            );
          }

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
          'type': media.type.name,
          'storagePath': result.storagePath,
        };
        if (thumbnailUrl != null) {
          item['thumbnailUrl'] = thumbnailUrl;
        }

        mediaItems.add(item);

        if (!isClosed) {
          emit(state.copyWith(
            status: CreateNewsPostStatus.uploading,
            progress: (i + 1) / (totalFiles > 0 ? totalFiles : 1),
          ));
        }
      }

      // ─── Step 4: Create the Firestore document ────────────────────
      if (isClosed) return;
      emit(state.copyWith(
        status: CreateNewsPostStatus.creating,
        progress: 1.0,
      ));

      final createResult = await _repository.createPost(
        authorId: _authorId!,
        authorName: _authorName!,
        authorPhotoUrl: _authorPhotoUrl,
        text: state.text.trim().isNotEmpty ? state.text.trim() : null,
        mediaItems: mediaItems,
        latitude: location.latitude,
        longitude: location.longitude,
        district: location.district,
        city: location.city,
        locality: location.locality,
        country: location.country,
        postType: postType,
      );

      createResult.fold(
        (failure) {
          _logger.e('Failed to create news post: ${failure.message}');
          emit(state.copyWith(
            status: CreateNewsPostStatus.error,
            errorMessage: failure.message,
          ));
        },
        (post) {
          _logger.i('News post created: ${post.id}');
          emit(state.copyWith(
            status: CreateNewsPostStatus.success,
            progress: 1.0,
          ));
        },
      );
    } catch (e, stack) {
      _logger.e('Error creating news post', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: CreateNewsPostStatus.error,
        errorMessage: e.toString(),
      ));
    } finally {
      _mediaOptimizer.dispose();
    }
  }

  /// Retries only the GPS location detection (no submission).
  /// Used after the user enables location services or grants permission.
  Future<void> _onLocationRetry(
    CreateNewsPostLocationRetry event,
    Emitter<CreateNewsPostState> emit,
  ) async {
    emit(state.copyWith(
      status: CreateNewsPostStatus.detectingLocation,
      clearError: true,
    ));

    try {
      final location = await _locationService.detectCurrentLocation();
      _logger.i('Location retry succeeded: ${location.shortDisplayString}');

      if (isClosed) return;
      emit(state.copyWith(
        status: CreateNewsPostStatus.idle,
        detectedLocation: location,
      ));
    } on LocationServiceException catch (e) {
      _logger.w('Location retry failed: ${e.message}');
      emit(state.copyWith(
        status: CreateNewsPostStatus.error,
        errorMessage: e.message,
        locationFailureReason: e.reason,
      ));
    } catch (e, stack) {
      _logger.e('Location retry unexpected error', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: CreateNewsPostStatus.error,
        errorMessage: 'Failed to detect location. Please try again.',
      ));
    }
  }
}
