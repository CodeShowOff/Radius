import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

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
      return const _LoadingPlaceholder(icon: Icons.image);
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
      return const _LoadingPlaceholder(icon: Icons.mic);
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
      return const _LoadingPlaceholder(icon: Icons.description);
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
      return const _LoadingPlaceholder(icon: Icons.emoji_emotions);
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

/// Video message content (placeholder - requires video player).
class _VideoContent extends StatelessWidget {
  final Message message;

  const _VideoContent({required this.message});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement video player when needed
    return Container(
      width: 250,
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.play_circle_outline, size: 64),
      ),
    );
  }
}

/// Loading placeholder for media that's still uploading.
class _LoadingPlaceholder extends StatelessWidget {
  final IconData icon;

  const _LoadingPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
