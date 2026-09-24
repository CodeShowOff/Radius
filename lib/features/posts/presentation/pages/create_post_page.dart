import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'dart:ui';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../domain/entities/media_item.dart';
import '../bloc/create_post_bloc.dart';
import '../widgets/media_picker_sheet.dart';
import '../widgets/post_visibility_selector.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _textController = TextEditingController();
  final PageController _pageController = PageController();
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
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      bloc.setAuthorInfo(
        authorId: authState.user.id,
        authorName: authState.user.displayName ?? 'Unknown',
        authorPhotoUrl: authState.user.avatarUrl,
      );
      final connectionState = context.read<ConnectionBloc>().state;
      final connectionIds = connectionState.connections
          .map((c) => c.getOtherUserId(authState.user.id))
          .toList();
      bloc.setConnectionIds(connectionIds);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _addMedia(CreatePostState state) async {
    final remaining = 10 - state.selectedMedia.length;
    final files = await MediaPickerSheet.show(context, maxItems: remaining);
    if (files != null && files.isNotEmpty && mounted) {
      context.read<CreatePostBloc>().add(CreatePostMediaAdded(files));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return BlocConsumer<CreatePostBloc, CreatePostState>(
      listener: (context, state) {
        if (state.status == CreatePostStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post published successfully!'), backgroundColor: Colors.green));
          context.pop(true);
        } else if (state.status == CreatePostStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage ?? 'Error'), backgroundColor: theme.colorScheme.error));
        }
      },
      builder: (context, state) {
        final isBusy = state.status == CreatePostStatus.uploading || state.status == CreatePostStatus.optimizing;
        
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: theme.colorScheme.surface,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.pop(),
            ),
            title: const Text('New Post', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
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
                  onPressed: state.canSubmit && !isBusy ? () => context.read<CreatePostBloc>().add(const CreatePostSubmitted()) : null,
                  child: isBusy 
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onSurfaceVariant))
                      : const Text('Share', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
          body: isBusy ? _buildUploadingState(state, theme) : _buildEditor(state, theme),
        );
      },
    );
  }

  Widget _buildUploadingState(CreatePostState state, ThemeData theme) {
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
            state.status == CreatePostStatus.optimizing ? 'Optimizing Media...' : 'Publishing Post...',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: LinearProgressIndicator(
              value: state.uploadProgress, 
              borderRadius: BorderRadius.circular(8),
              minHeight: 6,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEditor(CreatePostState state, ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('You', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            PostVisibilitySelector(
                              visibility: state.visibility,
                              onChanged: (v) => context.read<CreatePostBloc>().add(CreatePostVisibilityChanged(v)),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),

                // Caption Input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    maxLength: 2000,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: "What's on your mind?",
                      hintStyle: TextStyle(color: theme.colorScheme.outline, fontSize: 18),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (value) => context.read<CreatePostBloc>().add(CreatePostTextChanged(value)),
                  ),
                ),

                const SizedBox(height: 16),

                // Premium Media Carousel
                if (state.selectedMedia.isNotEmpty)
                  _buildMediaCarousel(state, theme),

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
              Text('Add to your post', style: TextStyle(fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (state.canAddMedia)
                IconButton.filledTonal(
                  icon: const Icon(Icons.photo_library_rounded),
                  onPressed: () => _addMedia(state),
                  tooltip: 'Add Photos/Videos',
                ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.location_on_rounded),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location feature coming soon'))),
                tooltip: 'Check in',
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.person_add_rounded),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tagging feature coming soon'))),
                tooltip: 'Tag people',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCarousel(CreatePostState state, ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.width, // Square aspect ratio
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: state.selectedMedia.length,
                itemBuilder: (context, index) {
                  final media = state.selectedMedia[index];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      media.type == PostMediaType.image
                          ? Image.file(media.file, fit: BoxFit.cover)
                          : Container(color: Colors.black, child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white54, size: 64))),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: GestureDetector(
                              onTap: () => context.read<CreatePostBloc>().add(CreatePostMediaRemoved(index)),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                      )
                    ],
                  );
                },
              ),
              if (state.selectedMedia.length > 1)
                Positioned(
                  bottom: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
                        child: SmoothPageIndicator(
                          controller: _pageController,
                          count: state.selectedMedia.length,
                          effect: ScrollingDotsEffect(
                            activeDotColor: Colors.white,
                            dotColor: Colors.white.withValues(alpha: 0.4),
                            dotHeight: 6,
                            dotWidth: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
