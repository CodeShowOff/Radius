import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../domain/entities/media_item.dart';
import '../bloc/create_post_bloc.dart';
import '../widgets/media_picker_sheet.dart';
import '../widgets/post_visibility_selector.dart';

/// Page for creating a new post with text, media, and visibility options.
class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
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
    final bloc = context.read<CreatePostBloc>();

    // Set author info from AuthBloc
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      bloc.setAuthorInfo(
        authorId: authState.user.id,
        authorName: authState.user.displayName ?? 'Unknown',
        authorPhotoUrl: authState.user.avatarUrl,
      );
    }

    // Set connection IDs from ConnectionBloc
    final connectionState = context.read<ConnectionBloc>().state;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';
    final connectionIds = connectionState.connections
        .map((c) => c.getOtherUserId(currentUserId))
        .toList();
    bloc.setConnectionIds(connectionIds);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CreatePostBloc, CreatePostState>(
      listener: (context, state) {
        if (state.status == CreatePostStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post created!')),
          );
          context.pop(true); // Return true to indicate a post was created
        } else if (state.status == CreatePostStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Failed to create post'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isBusy = state.status == CreatePostStatus.uploading ||
            state.status == CreatePostStatus.optimizing;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Create Post'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: state.canSubmit && !isBusy
                      ? () => context
                          .read<CreatePostBloc>()
                          .add(const CreatePostSubmitted())
                      : null,
                  child: isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Post'),
                ),
              ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: isBusy,
            child: Column(
              children: [
                // Progress bar (optimizing or uploading)
                if (isBusy)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.uploadProgress,
                        minHeight: 3,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Text(
                          state.status == CreatePostStatus.optimizing
                              ? 'Optimizing mediaâ€¦'
                              : 'Uploadingâ€¦',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Text input
                        TextField(
                          controller: _textController,
                          maxLines: null,
                          minLines: 3,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: "What's on your mind?",
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          onChanged: (value) => context
                              .read<CreatePostBloc>()
                              .add(CreatePostTextChanged(value)),
                        ),

                        const SizedBox(height: 16),

                        // Selected media thumbnails
                        if (state.selectedMedia.isNotEmpty) ...[
                          _MediaPreviewStrip(
                            media: state.selectedMedia,
                            onRemove: (index) => context
                                .read<CreatePostBloc>()
                                .add(CreatePostMediaRemoved(index)),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Add media button
                        if (state.canAddMedia)
                          OutlinedButton.icon(
                            onPressed: () => _addMedia(context, state),
                            icon: const Icon(Icons.add_photo_alternate),
                            label: Text(state.selectedMedia.isEmpty
                                ? 'Add Photos or Video'
                                : 'Add More (${state.selectedMedia.length}/10)'),
                          ),

                        const SizedBox(height: 24),

                        // Visibility selector
                        PostVisibilitySelector(
                          visibility: state.visibility,
                          onChanged: (v) => context
                              .read<CreatePostBloc>()
                              .add(CreatePostVisibilityChanged(v)),
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

  Future<void> _addMedia(BuildContext context, CreatePostState state) async {
    final remaining = 10 - state.selectedMedia.length;
    final files = await MediaPickerSheet.show(
      context,
      maxItems: remaining,
    );

    if (files != null && files.isNotEmpty && context.mounted) {
      context.read<CreatePostBloc>().add(CreatePostMediaAdded(files));
    }
  }
}

/// Horizontal strip of selected media thumbnails with remove buttons.
class _MediaPreviewStrip extends StatelessWidget {
  final List<SelectedMedia> media;
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

/// Single media thumbnail with a remove button overlay.
class _MediaThumbnail extends StatelessWidget {
  final SelectedMedia media;
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
            // Thumbnail
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

            // Video badge
            if (media.type == PostMediaType.video)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, size: 12, color: Colors.white),
                      SizedBox(width: 2),
                      Text(
                        'VIDEO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
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
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
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
