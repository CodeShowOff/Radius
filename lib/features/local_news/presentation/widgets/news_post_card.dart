import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';
import '../bloc/news_interaction_cubit.dart';

class NewsPostCard extends StatelessWidget {
  final NewsPost post;
  final VoidCallback? onAuthorTap;
  final bool isOwnPost;
  final VoidCallback? onDelete;
    final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;

  const NewsPostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
    this.isOwnPost = false,
    this.onDelete,
        this.onLikeTap,
    this.onCommentTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PostHeader(
            authorName: post.authorName,
            authorPhotoUrl: post.authorPhotoUrl,
            createdAt: post.createdAt,
                        onTap: onAuthorTap,
            isOwnPost: isOwnPost,
            onDelete: onDelete,
                      ),
          
          if (post.text != null && post.text!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                post.text!,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ),
            
          if (post.hasMedia)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: post.hasMultipleMedia
                  ? _MediaCarousel(mediaItems: post.mediaItems)
                  : _SingleMedia(mediaItem: post.mediaItems.first),
            ),
            
          _PostActionBar(
            onLikeTap: onLikeTap,
            onCommentTap: onCommentTap,
          ),
        ],
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
    final VoidCallback? onTap;
  final bool isOwnPost;
  final VoidCallback? onDelete;
  
  const _PostHeader({
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
        this.onTap,
    this.isOwnPost = false,
    this.onDelete,
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: GestureDetector(
        onTap: onTap,
        child: CachedAvatar(imageUrl: authorPhotoUrl, name: authorName, radius: 22),
      ),
      title: GestureDetector(
        onTap: onTap,
        child: Text(
          authorName,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      subtitle: Row(
        children: [
          _TimeAgoText(dateTime: createdAt),
          const SizedBox(width: 4),
          const Text('·', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),

        ],
      ),
      trailing: isOwnPost ? PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (val) {
          if (val == 'del') onDelete?.call();

        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'del', child: Text('Delete', style: TextStyle(color: theme.colorScheme.error))),
        ],
      ) : null,
    );
  }
}

class _TimeAgoText extends StatelessWidget {
  final DateTime dateTime;
  const _TimeAgoText({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(dateTime);
    String text = '';
    if (diff.inMinutes < 1) {
      text = 'Now';
    } else if (diff.inHours < 1) {
      text = '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      text = '${diff.inHours}h';
    } else {
      text = '${diff.inDays}d';
    }
    return Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline));
  }
}

class _PostActionBar extends StatelessWidget {
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;

  const _PostActionBar({this.onLikeTap, this.onCommentTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<NewsInteractionCubit, NewsInteractionState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: onLikeTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        state.isLiked ? Icons.favorite : Icons.favorite_border,
                        color: state.isLiked ? Colors.redAccent : theme.colorScheme.onSurface,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onCommentTap,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.chat_bubble_outline, size: 26, color: theme.colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
              if (state.likeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    '${state.likeCount} likes',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              if (state.commentCount > 0)
                GestureDetector(
                  onTap: onCommentTap,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'View all ${state.commentCount} comments',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SingleMedia extends StatelessWidget {
  final MediaItem mediaItem;
  const _SingleMedia({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    if (mediaItem.type == PostMediaType.video) {
      return _AutoplayVideoThumbnail(mediaItem: mediaItem);
    }
    return _PostImage(imageUrl: mediaItem.url);
  }
}

class _PostImage extends StatelessWidget {
  final String imageUrl;
  const _PostImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey.withValues(alpha: 0.1),
          height: 300,
        ),
      ),
    );
  }
}

class _AutoplayVideoThumbnail extends StatefulWidget {
  final MediaItem mediaItem;
  const _AutoplayVideoThumbnail({required this.mediaItem});

  @override
  State<_AutoplayVideoThumbnail> createState() => _AutoplayVideoThumbnailState();
}

class _AutoplayVideoThumbnailState extends State<_AutoplayVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  double _visibleFraction = 0.0;

  static final _cacheManager = CacheManager(Config('post_videos', stalePeriod: const Duration(days: 7), maxNrOfCacheObjects: 100));

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) async {
    if (!mounted) return;
    _visibleFraction = info.visibleFraction;
    
    if (_visibleFraction > 0.6) {
      if (_controller == null && !_isInitializing) {
        _isInitializing = true;
        try {
          final file = await _cacheManager.getSingleFile(widget.mediaItem.url);
          if (!mounted) return;
          _controller = VideoPlayerController.file(file);
          _controller!.setLooping(true);
          _controller!.setVolume(0); // Auto-play muted like Insta
          await _controller!.initialize();
          if (!mounted) return;
          setState(() => _isInitialized = true);
        } catch (e) {
          debugPrint('Video load error: $e');
        } finally {
          if (mounted) _isInitializing = false;
        }
      }
      
      // Double check visibility after potential async gap
      if (mounted && _controller != null && _isInitialized && _visibleFraction > 0.6) {
        if (!_controller!.value.isPlaying) {
          _controller!.play();
        }
      }
    } else if (_visibleFraction < 0.3) {
      if (_controller != null && _controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
  }

  void _toggleAudio() {
    if (_controller == null) return;
    final currentVolume = _controller!.value.volume;
    _controller!.setVolume(currentVolume == 0 ? 1.0 : 0.0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${widget.mediaItem.url}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: _toggleAudio,
        child: Container(
          width: double.infinity,
          color: Colors.black,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: _isInitialized && _controller != null
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: Icon(
                          _controller!.value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    )
                  ],
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.mediaItem.thumbnailUrl != null)
                      CachedNetworkImage(
                        imageUrl: widget.mediaItem.thumbnailUrl!,
                        width: double.infinity,
                        height: 300,
                        fit: BoxFit.cover,
                      ),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MediaCarousel extends StatelessWidget {
  final List<MediaItem> mediaItems;
  const _MediaCarousel({required this.mediaItems});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: PageView.builder(
        itemCount: mediaItems.length,
        itemBuilder: (context, index) {
          final item = mediaItems[index];
          return item.type == PostMediaType.video ? _AutoplayVideoThumbnail(mediaItem: item) : _PostImage(imageUrl: item.url);
        },
      ),
    );
  }
}
