import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../../posts/presentation/widgets/media_picker_sheet.dart';
import '../bloc/create_news_post_bloc.dart';
import 'dart:ui';

/// Page for creating a local news post or reel.
class CreateNewsPostPage extends StatefulWidget {
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
    final theme = Theme.of(context);
    
    return BlocConsumer<CreateNewsPostBloc, CreateNewsPostState>(
      listener: (context, state) {
        if (state.status == CreateNewsPostStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Published successfully!'), backgroundColor: Colors.green),
          );
          context.pop(true);
        } else if (state.status == CreateNewsPostStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Failed to publish'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isBusy = state.status == CreateNewsPostStatus.uploading || state.status == CreateNewsPostStatus.optimizing;
        
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: theme.colorScheme.surface,
            title: Text(widget.isReel ? 'Create Reel' : 'Local News', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: state.canSubmit && !isBusy ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: state.canSubmit && !isBusy ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  onPressed: state.canSubmit && !isBusy ? () => context.read<CreateNewsPostBloc>().add(const CreateNewsPostSubmitted()) : null,
                  child: isBusy
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onSurfaceVariant))
                      : Text(widget.isReel ? 'Post Reel' : 'Publish', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          body: isBusy ? _buildUploadingState(state, theme) : _buildEditor(state, theme),
        );
      },
    );
  }
  
  Widget _buildUploadingState(CreateNewsPostState state, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 32),
          Text(
            state.status == CreateNewsPostStatus.optimizing ? 'Optimizing Media...' : 'Publishing...',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: LinearProgressIndicator(
              value: state.progress, 
              borderRadius: BorderRadius.circular(8),
              minHeight: 6,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEditor(CreateNewsPostState state, ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GPS notice
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This post will be broadcasted to your saved local radius.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),

                // Reel guidelines
                if (widget.isReel && state.selectedMedia.isEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.video_library_rounded, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Reel Guidelines', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('• Select one high-quality video\\n• Maximum length is 30 seconds', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),

                // Text input
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    minLines: widget.isReel ? 2 : 4,
                    maxLength: 2000,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: widget.isReel ? 'Write a catchy caption...' : "What's happening in your area?",
                      hintStyle: TextStyle(color: theme.colorScheme.outline, fontSize: 18),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (value) => context.read<CreateNewsPostBloc>().add(CreateNewsPostTextChanged(value)),
                  ),
                ),

                // Media preview strip
                if (state.selectedMedia.isNotEmpty)
                  SizedBox(
                    height: widget.isReel ? 300 : 160,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: state.selectedMedia.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final item = state.selectedMedia[index];
                        return _MediaThumbnail(
                          media: item,
                          isReel: widget.isReel,
                          onRemove: () => context.read<CreateNewsPostBloc>().add(CreateNewsPostMediaRemoved(index)),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        
        // Bottom Action Bar
        Container(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 12, 
            bottom: MediaQuery.of(context).padding.bottom + 12
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1))),
          ),
          child: Row(
            children: [
              Text(widget.isReel ? 'Add Video' : 'Add Media', style: TextStyle(fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (state.canAddMedia)
                FilledButton.tonalIcon(
                  icon: Icon(widget.isReel ? Icons.videocam_rounded : Icons.photo_library_rounded),
                  label: Text(widget.isReel ? 'Gallery' : 'Library'),
                  onPressed: () => _addMedia(context, state),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addMedia(BuildContext context, CreateNewsPostState state) async {
    if (widget.isReel) {
      final files = await MediaPickerSheet.show(context, maxItems: 1, videoOnly: true);
      if (files != null && files.isNotEmpty && context.mounted) {
        context.read<CreateNewsPostBloc>().add(CreateNewsPostMediaAdded(files));
      }
    } else {
      final remaining = 10 - state.selectedMedia.length;
      final files = await MediaPickerSheet.show(context, maxItems: remaining);
      if (files != null && files.isNotEmpty && context.mounted) {
        context.read<CreateNewsPostBloc>().add(CreateNewsPostMediaAdded(files));
      }
    }
  }
}

class _MediaThumbnail extends StatelessWidget {
  final SelectedNewsMedia media;
  final bool isReel;
  final VoidCallback onRemove;

  const _MediaThumbnail({
    required this.media,
    required this.isReel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: isReel ? 9/16 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (media.type == PostMediaType.image)
              Image.file(media.file, fit: BoxFit.cover)
            else
              Container(
                color: Colors.black,
                child: const Center(child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white54)),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
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
