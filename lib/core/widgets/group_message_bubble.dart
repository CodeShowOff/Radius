import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../features/chat/data/audio_session_manager.dart';
import '../../features/location_groups/domain/entities/group_message.dart';
import 'linkified_text.dart';

/// Status of a group chat message.
///
/// Modeled after the v_chat_sdk VMessageEmitStatus pattern.
/// Groups don't need delivered/seen (no per-user read receipts in groups).
enum GroupMessageStatus {
  /// Message is pending (optimistic, not yet confirmed by server).
  pending,

  /// Message has been confirmed by server (arrived via Firestore stream).
  sent,

  /// Message failed to send.
  error,
}

/// A reusable message bubble for all group chat types (random, location, nearby).
///
/// Modeled after the v_chat_sdk VMessageItem pattern:
/// - Sender avatar + name for non-self messages (group context)
/// - System messages centered (like v_chat_sdk CenterItemHolder)
/// - Status indicator (clock for pending, check for sent, error icon)
/// - WhatsApp-style inline time
/// - Long-press actions (copy, delete, retry)
/// - Error overlay with "tap to retry" for failed messages
class GroupMessageBubble extends StatelessWidget {
  final String messageId;
  final String text;
  final bool isMe;
  final bool isSystemMessage;
  final bool showSenderInfo;
  final String? senderName;
  final String? senderPhotoUrl;
  final DateTime sentAt;
  final GroupMessageStatus status;
  final bool isDeleted;
  final VoidCallback? onSenderTap;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  // Media fields
  final GroupMessageType messageType;
  final String? mediaUrl;
  final String? mediaFileName;
  final int? mediaFileSize;
  final int? duration;
  final String? thumbnailUrl;
  final double? uploadProgress;
  final AudioSessionManager? audioSessionManager;

  const GroupMessageBubble({
    super.key,
    required this.messageId,
    required this.text,
    required this.isMe,
    this.isSystemMessage = false,
    this.showSenderInfo = false,
    this.senderName,
    this.senderPhotoUrl,
    required this.sentAt,
    this.status = GroupMessageStatus.sent,
    this.isDeleted = false,
    this.onSenderTap,
    this.onRetry,
    this.onDelete,
    this.messageType = GroupMessageType.text,
    this.mediaUrl,
    this.mediaFileName,
    this.mediaFileSize,
    this.duration,
    this.thumbnailUrl,
    this.uploadProgress,
    this.audioSessionManager,
  });

  bool get _isMediaMessage =>
      messageType != GroupMessageType.text &&
      messageType != GroupMessageType.system;

  @override
  Widget build(BuildContext context) {
    // System messages (like v_chat_sdk CenterItemHolder)
    if (isSystemMessage) {
      return _SystemMessage(text: text);
    }

    // Deleted messages
    if (isDeleted) {
      return _DeletedBubble(isMe: isMe, sentAt: sentAt);
    }

    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.75;
    final isError = status == GroupMessageStatus.error;

    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    final contentPadding = _isMediaMessage
        ? const EdgeInsets.all(4)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar for other users (like v_chat_sdk _getGroupUserAvatar)
          if (!isMe) ...[
            if (showSenderInfo)
              GestureDetector(
                onTap: onSenderTap,
                child: _SenderAvatar(
                  name: senderName,
                  photoUrl: senderPhotoUrl,
                ),
              )
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],

          // Message content column
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: () => _showMessageActions(context),
                onTap: isError ? onRetry : null,
                child: IntrinsicWidth(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    padding: contentPadding,
                    decoration: BoxDecoration(
                      color: isError
                          ? bubbleColor.withValues(alpha: 0.6)
                          : bubbleColor,
                      borderRadius: borderRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sender name (like v_chat_sdk _getGroupUserTitle)
                        if (!isMe && showSenderInfo && senderName != null)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: 4,
                              left: _isMediaMessage ? 8 : 0,
                              top: _isMediaMessage ? 4 : 0,
                            ),
                            child: Text(
                              senderName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isMe
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        // Media content
                        if (_isMediaMessage)
                          _GroupMediaContent(
                            messageType: messageType,
                            mediaUrl: mediaUrl,
                            mediaFileName: mediaFileName,
                            mediaFileSize: mediaFileSize,
                            duration: duration,
                            uploadProgress: uploadProgress,
                            isSent: isMe,
                            audioSessionManager: audioSessionManager,
                            messageId: messageId,
                          ),

                        // Caption for media messages
                        if (_isMediaMessage && text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 10,
                              right: 10,
                              top: 4,
                              bottom: 6,
                            ),
                            child: LinkifiedText(
                              text: text,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isMe
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                                height: 1.3,
                              ) ?? const TextStyle(),
                              linkColor: isMe
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.primary,
                            ),
                          ),

                        // Text-only message with inline time (WhatsApp style)
                        if (!_isMediaMessage && text.isNotEmpty)
                          Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.end,
                            children: [
                              LinkifiedText(
                                text: text,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: isMe
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                  height: 1.3,
                                ) ?? const TextStyle(),
                                linkColor: isMe
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 1),
                                child: _MessageMeta(
                                  sentAt: sentAt,
                                  status: status,
                                  isMe: isMe,
                                ),
                              ),
                            ],
                          ),

                        // For media messages, show time separately below
                        if (_isMediaMessage)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2, right: 4),
                              child: _MessageMeta(
                                sentAt: sentAt,
                                status: status,
                                isMe: isMe,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Error indicator row (like 1:1 chat MessageBubble)
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Failed to send. Tap to retry.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Show contextual actions on long-press (like v_chat_sdk message actions).
  void _showMessageActions(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Copy text
            if (text.isNotEmpty && !isDeleted)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),

            // Retry (for failed messages)
            if (status == GroupMessageStatus.error && onRetry != null)
              ListTile(
                leading: Icon(Icons.refresh, color: theme.colorScheme.primary),
                title: const Text('Retry'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRetry?.call();
                },
              ),

            // Delete (only for own messages)
            if (isMe && !isDeleted && onDelete != null)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: theme.colorScheme.error),
                title: Text('Delete',
                    style: TextStyle(color: theme.colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Time + status indicator row (modeled after 1:1 chat _MessageMeta).
class _MessageMeta extends StatelessWidget {
  final DateTime sentAt;
  final GroupMessageStatus status;
  final bool isMe;

  const _MessageMeta({
    required this.sentAt,
    required this.status,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.5)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(sentAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: metaColor,
            fontSize: 11,
          ),
        ),
        // Status indicator (only for own messages)
        if (isMe) ...[
          const SizedBox(width: 3),
          _StatusIcon(status: status, color: metaColor),
        ],
      ],
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Status icon for group messages (like v_chat_sdk MessageStatusIcon).
class _StatusIcon extends StatelessWidget {
  final GroupMessageStatus status;
  final Color color;

  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case GroupMessageStatus.pending:
        return Icon(Icons.access_time, size: 14, color: color);
      case GroupMessageStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case GroupMessageStatus.error:
        return Icon(Icons.error_outline, size: 14,
            color: Theme.of(context).colorScheme.error);
    }
  }
}

/// Sender avatar widget (like v_chat_sdk VCircleAvatar).
class _SenderAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;

  const _SenderAvatar({this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundImage:
          photoUrl != null && photoUrl!.isNotEmpty
              ? NetworkImage(photoUrl!)
              : null,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: photoUrl == null || photoUrl!.isEmpty
          ? Text(
              (name ?? '?')[0].toUpperCase(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );
  }
}

/// System message (centered, like v_chat_sdk CenterItemHolder).
class _SystemMessage extends StatelessWidget {
  final String text;

  const _SystemMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

/// Deleted message bubble.
class _DeletedBubble extends StatelessWidget {
  final bool isMe;
  final DateTime sentAt;

  const _DeletedBubble({required this.isMe, required this.sentAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 48 : 12,
            right: isMe ? 12 : 48,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Message deleted',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unread divider shown above the first unread message (WhatsApp style).
class GroupUnreadDivider extends StatelessWidget {
  final int count;

  const GroupUnreadDivider({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count <= 0
        ? 'Unread messages'
        : count == 1
            ? '1 unread message'
            : '$count unread messages';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ========================================================================
// GROUP MEDIA CONTENT WIDGETS
// ========================================================================

/// Dispatcher widget for group media content rendering.
class _GroupMediaContent extends StatelessWidget {
  final GroupMessageType messageType;
  final String? mediaUrl;
  final String? mediaFileName;
  final int? mediaFileSize;
  final int? duration;
  final double? uploadProgress;
  final bool isSent;
  final AudioSessionManager? audioSessionManager;
  final String messageId;

  const _GroupMediaContent({
    required this.messageType,
    this.mediaUrl,
    this.mediaFileName,
    this.mediaFileSize,
    this.duration,
    this.uploadProgress,
    required this.isSent,
    this.audioSessionManager,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    switch (messageType) {
      case GroupMessageType.image:
        return _GroupImageContent(mediaUrl: mediaUrl, uploadProgress: uploadProgress);
      case GroupMessageType.audio:
        return _GroupAudioContent(
          mediaUrl: mediaUrl,
          duration: duration,
          isSent: isSent,
          audioSessionManager: audioSessionManager,
          messageId: messageId,
          uploadProgress: uploadProgress,
        );
      case GroupMessageType.document:
        return _GroupDocumentContent(
          mediaUrl: mediaUrl,
          mediaFileName: mediaFileName,
          mediaFileSize: mediaFileSize,
          isSent: isSent,
          uploadProgress: uploadProgress,
        );
      case GroupMessageType.video:
        return _GroupVideoContent(
          mediaUrl: mediaUrl,
          audioSessionManager: audioSessionManager,
          uploadProgress: uploadProgress,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Image content for group messages.
class _GroupImageContent extends StatelessWidget {
  final String? mediaUrl;
  final double? uploadProgress;

  const _GroupImageContent({this.mediaUrl, this.uploadProgress});

  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null) {
      return _GroupMediaLoadingPlaceholder(icon: Icons.image, uploadProgress: uploadProgress);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: mediaUrl!,
        width: 250,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 250,
          height: 250,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator()),
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

/// Audio/voice content for group messages.
class _GroupAudioContent extends StatefulWidget {
  final String? mediaUrl;
  final int? duration;
  final bool isSent;
  final AudioSessionManager? audioSessionManager;
  final String messageId;
  final double? uploadProgress;

  const _GroupAudioContent({
    this.mediaUrl,
    this.duration,
    required this.isSent,
    this.audioSessionManager,
    required this.messageId,
    this.uploadProgress,
  });

  @override
  State<_GroupAudioContent> createState() => _GroupAudioContentState();
}

class _GroupAudioContentState extends State<_GroupAudioContent> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  late final List<dynamic> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _duration = widget.duration != null
        ? Duration(seconds: widget.duration!)
        : null;

    final manager = widget.audioSessionManager;
    if (manager != null) {
      _subscriptions.add(manager.playerStateStream.listen((state) {
        if (!mounted) return;
        if (state.messageId == widget.messageId) {
          setState(() {
            _isPlaying = state.isPlaying;
            if (state.isStopped) _position = Duration.zero;
          });
        } else if (_isPlaying) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      }));
      _subscriptions.add(manager.positionStream.listen((position) {
        if (!mounted) return;
        if (manager.currentMessageId == widget.messageId) {
          setState(() => _position = position);
        }
      }));
      _subscriptions.add(manager.durationStream.listen((duration) {
        if (!mounted) return;
        if (manager.currentMessageId == widget.messageId) {
          setState(() => _duration = duration);
        }
      }));
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (widget.mediaUrl == null) return;
    final manager = widget.audioSessionManager;
    if (manager != null) {
      if (_isPlaying) {
        await manager.pause();
      } else {
        await manager.play(
          messageId: widget.messageId,
          url: widget.mediaUrl!,
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

    if (widget.mediaUrl == null) {
      return _GroupMediaLoadingPlaceholder(icon: Icons.mic, uploadProgress: widget.uploadProgress);
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

/// Document content for group messages.
class _GroupDocumentContent extends StatelessWidget {
  final String? mediaUrl;
  final String? mediaFileName;
  final int? mediaFileSize;
  final bool isSent;
  final double? uploadProgress;

  const _GroupDocumentContent({
    this.mediaUrl,
    this.mediaFileName,
    this.mediaFileSize,
    required this.isSent,
    this.uploadProgress,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openDocument() async {
    if (mediaUrl == null) return;
    try {
      final uri = Uri.parse(mediaUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor =
        isSent ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    if (mediaUrl == null) {
      return _GroupMediaLoadingPlaceholder(icon: Icons.description, uploadProgress: uploadProgress);
    }

    return InkWell(
      onTap: _openDocument,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.description, size: 40, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mediaFileName ?? 'Document',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (mediaFileSize != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(mediaFileSize!),
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

/// Video content for group messages.
class _GroupVideoContent extends StatefulWidget {
  final String? mediaUrl;
  final AudioSessionManager? audioSessionManager;
  final double? uploadProgress;

  const _GroupVideoContent({
    this.mediaUrl,
    this.audioSessionManager,
    this.uploadProgress,
  });

  @override
  State<_GroupVideoContent> createState() => _GroupVideoContentState();
}

class _GroupVideoContentState extends State<_GroupVideoContent> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  StreamSubscription? _audioStateSub;

  @override
  void initState() {
    super.initState();
    _initializePlayer();

    final manager = widget.audioSessionManager;
    if (manager != null) {
      _audioStateSub = manager.playerStateStream.listen((state) {
        if (!mounted) return;
        if (state.isPlaying && _controller?.value.isPlaying == true) {
          _controller!.pause();
          if (mounted) setState(() {});
        }
      });
    }
  }

  Future<void> _initializePlayer() async {
    if (widget.mediaUrl == null) return;
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.mediaUrl!),
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _audioStateSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        widget.audioSessionManager?.stop();
        _controller!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.mediaUrl == null) {
      return _GroupMediaLoadingPlaceholder(icon: Icons.videocam, uploadProgress: widget.uploadProgress);
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
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text('Failed to load video', style: TextStyle(color: theme.colorScheme.error)),
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
        child: const Center(child: CircularProgressIndicator()),
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
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
                        ? value.position.inMilliseconds / value.duration.inMilliseconds
                        : 0.0,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
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

/// Loading placeholder for group media that's still uploading.
class _GroupMediaLoadingPlaceholder extends StatelessWidget {
  final IconData icon;
  final double? uploadProgress;

  const _GroupMediaLoadingPlaceholder({required this.icon, this.uploadProgress});

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

/// Empty state for group chats.
class GroupChatEmptyState extends StatelessWidget {
  const GroupChatEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
