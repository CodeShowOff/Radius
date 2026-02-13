import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../domain/entities/message.dart';

/// Widget for displaying media content in message bubbles.
class MediaMessageContent extends StatelessWidget {
  final Message message;
  final bool isSent;

  const MediaMessageContent({
    super.key,
    required this.message,
    required this.isSent,
  });

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return _ImageContent(message: message);
      case MessageType.audio:
        return _AudioContent(message: message, isSent: isSent);
      case MessageType.document:
        return _DocumentContent(message: message, isSent: isSent);
      case MessageType.sticker:
        return _StickerContent(message: message);
      case MessageType.video:
        return _VideoContent(message: message);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Image message content.
class _ImageContent extends StatelessWidget {
  final Message message;

  const _ImageContent({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.mediaUrl == null) {
      return _LoadingPlaceholder(icon: Icons.image, uploadProgress: message.uploadProgress);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: message.mediaUrl!,
        width: 250,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 250,
          height: 250,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 250,
          height: 250,
          color: Theme.of(context).colorScheme.errorContainer,
          child: Icon(
            Icons.broken_image,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}

/// Audio/voice message content.
class _AudioContent extends StatefulWidget {
  final Message message;
  final bool isSent;

  const _AudioContent({
    required this.message,
    required this.isSent,
  });

  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _duration = widget.message.duration != null
        ? Duration(seconds: widget.message.duration!)
        : null;

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (widget.message.mediaUrl == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(UrlSource(widget.message.mediaUrl!));
      }
    } catch (e) {
      // Handle playback errors (network issues, invalid URL, etc.)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play audio: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = widget.isSent
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    if (widget.message.mediaUrl == null) {
      return _LoadingPlaceholder(icon: Icons.mic, uploadProgress: widget.message.uploadProgress);
    }

    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlayback,
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: iconColor,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _duration != null && _duration!.inMilliseconds > 0
                      ? _position.inMilliseconds / _duration!.inMilliseconds
                      : 0.0,
                  backgroundColor: iconColor.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(iconColor),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(_position),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: iconColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatDuration(_duration ?? Duration.zero),
            style: theme.textTheme.bodySmall?.copyWith(
              color: iconColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Document message content.
class _DocumentContent extends StatelessWidget {
  final Message message;
  final bool isSent;

  const _DocumentContent({
    required this.message,
    required this.isSent,
  });

  Future<void> _openDocument() async {
    if (message.mediaUrl == null) return;

    try {
      final uri = Uri.parse(message.mediaUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Cannot launch URL - silently fail or log
        debugPrint('Cannot open document: URL scheme not supported');
      }
    } catch (e) {
      // Log error - user will see if download doesn't start
      debugPrint('Failed to open document: $e');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor =
        isSent ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    if (message.mediaUrl == null) {
      return _LoadingPlaceholder(icon: Icons.description, uploadProgress: message.uploadProgress);
    }

    return InkWell(
      onTap: _openDocument,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.description,
              size: 40,
              color: iconColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.mediaFileName ?? 'Document',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.mediaFileSize != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(message.mediaFileSize!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: iconColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.download,
              color: iconColor.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sticker message content.
class _StickerContent extends StatelessWidget {
  final Message message;

  const _StickerContent({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.mediaUrl == null) {
      return _LoadingPlaceholder(icon: Icons.emoji_emotions, uploadProgress: message.uploadProgress);
    }

    return CachedNetworkImage(
      imageUrl: message.mediaUrl!,
      width: 150,
      height: 150,
      fit: BoxFit.contain,
      placeholder: (context, url) => Container(
        width: 150,
        height: 150,
        color: Colors.transparent,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: 150,
        height: 150,
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.broken_image,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

/// Video message content.
class _VideoContent extends StatefulWidget {
  final Message message;

  const _VideoContent({required this.message});

  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    if (widget.message.mediaUrl == null) return;

    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.message.mediaUrl!),
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.message.mediaUrl == null) {
      return _LoadingPlaceholder(icon: Icons.videocam, uploadProgress: widget.message.uploadProgress);
    }

    if (_hasError) {
      return Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                'Failed to load video',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 250,
        height: 150,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 150,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  color: Colors.transparent,
                  child: AnimatedOpacity(
                    opacity: _controller!.value.isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder(
                valueListenable: _controller!,
                builder: (context, VideoPlayerValue value, child) {
                  return LinearProgressIndicator(
                    value: value.duration.inMilliseconds > 0
                        ? value.position.inMilliseconds /
                            value.duration.inMilliseconds
                        : 0.0,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder for media that's still uploading.
/// Shows a determinate progress indicator when [uploadProgress] is provided.
class _LoadingPlaceholder extends StatelessWidget {
  final IconData icon;
  final double? uploadProgress;

  const _LoadingPlaceholder({required this.icon, this.uploadProgress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProgress = uploadProgress != null;
    final progressPercent = hasProgress ? (uploadProgress! * 100).toInt() : 0;

    return Container(
      width: 250,
      height: 150,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            if (hasProgress) ...[
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: uploadProgress,
                      strokeWidth: 3,
                      color: theme.colorScheme.primary,
                    ),
                    Text(
                      '$progressPercent%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sending...',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
