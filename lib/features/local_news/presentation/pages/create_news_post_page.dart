import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../../posts/presentation/widgets/media_picker_sheet.dart';
import '../bloc/create_news_post_bloc.dart';

/// Page for creating a local news post or reel with mandatory GPS verification.
class CreateNewsPostPage extends StatefulWidget {
  /// When true, the page is in reel-creation mode (single video, 30s max).
  final bool isReel;

  const CreateNewsPostPage({super.key, this.isReel = false});

  @override
  State<CreateNewsPostPage> createState() => _CreateNewsPostPageState();
}

class _CreateNewsPostPageState extends State<CreateNewsPostPage> {
  final _textController = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initializeBloc();
    }
  }

  void _initializeBloc() {
    final bloc = context.read<CreateNewsPostBloc>();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      bloc.setAuthorInfo(
        authorId: authState.user.id,
        authorName: authState.user.displayName ?? 'Unknown',
        authorPhotoUrl: authState.user.avatarUrl,
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CreateNewsPostBloc, CreateNewsPostState>(
      listener: (context, state) {
        if (state.status == CreateNewsPostStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('News post published!')),
          );
          context.pop(true);
        } else if (state.status == CreateNewsPostStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(state.errorMessage ?? 'Failed to create news post'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.isReel ? 'Create Reel' : 'Post News'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: state.canSubmit
                      ? () => context
                          .read<CreateNewsPostBloc>()
                          .add(const CreateNewsPostSubmitted())
                      : null,
                  child: state.isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.isReel ? 'Post' : 'Post'),
                ),
              ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: state.isBusy,
            child: Column(
              children: [
                // Progress bar during processing
                if (state.isBusy) _ProgressSection(state: state),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // GPS notice
                        _GpsNotice(state: state),
                        const SizedBox(height: 16),

                        // Text input
                        TextField(
                          controller: _textController,
                          maxLines: null,
                          minLines: widget.isReel ? 2 : 4,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: widget.isReel
                                ? 'Add a caption...'
                                : 'What\'s happening in your area?',
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          onChanged: (value) => context
                              .read<CreateNewsPostBloc>()
                              .add(CreateNewsPostTextChanged(value)),
                        ),

                        const SizedBox(height: 16),

                        // Reel guidelines
                        if (widget.isReel && state.selectedMedia.isEmpty)
                          _ReelGuidelines(),

                        // Media preview strip
                        if (state.selectedMedia.isNotEmpty) ...[
                          _MediaPreviewStrip(
                            media: state.selectedMedia,
                            onRemove: (index) => context
                                .read<CreateNewsPostBloc>()
                                .add(CreateNewsPostMediaRemoved(index)),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Add media button
                        if (state.canAddMedia)
                          OutlinedButton.icon(
                            onPressed: () => _addMedia(context, state),
                            icon: Icon(widget.isReel
                                ? Icons.videocam
                                : Icons.add_photo_alternate),
                            label: Text(widget.isReel
                                ? 'Select Video'
                                : state.selectedMedia.isEmpty
                                    ? 'Add Photos or Video'
                                    : 'Add More (${state.selectedMedia.length}/10)'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addMedia(
      BuildContext context, CreateNewsPostState state) async {
    if (widget.isReel) {
      // For reels: pick a single video
      final files = await _pickReelVideo(context);
      if (files != null && files.isNotEmpty && context.mounted) {
        context
            .read<CreateNewsPostBloc>()
            .add(CreateNewsPostMediaAdded(files));
      }
    } else {
      final remaining = 10 - state.selectedMedia.length;
      final files = await MediaPickerSheet.show(
        context,
        maxItems: remaining,
      );
      if (files != null && files.isNotEmpty && context.mounted) {
        context
            .read<CreateNewsPostBloc>()
            .add(CreateNewsPostMediaAdded(files));
      }
    }
  }

  Future<List<File>?> _pickReelVideo(BuildContext context) async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (picked != null) return [File(picked.path)];
      return null;
    } catch (_) {
      return null;
    }
  }
}

// ─── GPS status notice ────────────────────────────────────────────────

class _GpsNotice extends StatelessWidget {
  final CreateNewsPostState state;

  const _GpsNotice({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = state.detectedLocation;

    if (location != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Will be posted to ${location.shortDisplayString}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.gps_fixed,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your GPS location will be used to tag this news post.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Progress section ─────────────────────────────────────────────────

class _ProgressSection extends StatelessWidget {
  final CreateNewsPostState state;

  const _ProgressSection({required this.state});

  String get _statusLabel {
    switch (state.status) {
      case CreateNewsPostStatus.detectingLocation:
        return 'Detecting your location…';
      case CreateNewsPostStatus.locationDetected:
        return 'Location confirmed';
      case CreateNewsPostStatus.optimizing:
        return 'Optimizing media…';
      case CreateNewsPostStatus.uploading:
        return 'Uploading…';
      case CreateNewsPostStatus.creating:
        return 'Publishing…';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: state.status == CreateNewsPostStatus.detectingLocation
              ? null
              : state.progress,
          minHeight: 3,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            _statusLabel,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

// ─── Media preview strip ──────────────────────────────────────────────

class _MediaPreviewStrip extends StatelessWidget {
  final List<SelectedNewsMedia> media;
  final ValueChanged<int> onRemove;

  const _MediaPreviewStrip({
    required this.media,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = media[index];
          return _MediaThumbnail(
            media: item,
            onRemove: () => onRemove(index),
          );
        },
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  final SelectedNewsMedia media;
  final VoidCallback onRemove;

  const _MediaThumbnail({
    required this.media,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (media.type == PostMediaType.image)
              Image.file(
                media.file,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image),
                ),
              )
            else
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Video',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            // Remove button
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reel guidelines notice ───────────────────────────────────────────

class _ReelGuidelines extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                'Reel Guidelines',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\u2022 Maximum 30 seconds\n'
            '\u2022 Vertical video (9:16 aspect ratio)\n'
            '\u2022 One video per reel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
