import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/entities/chat_config.dart';
import 'chat_input.dart';

/// Shared chat input widget for chat conversations.
/// 
/// Provides appropriate input controls based on [config].
class SharedChatInput extends StatefulWidget {
  /// Configuration for chat display and features.
  final ChatConfig config;

  /// Callback when user sends a text message.
  final void Function(String text) onSend;

  /// Callback when typing status changes (optional, for identified mode).
  final void Function(bool isTyping)? onTypingChanged;

  /// Callback when image is selected from gallery (optional, for identified mode).
  final void Function(File file)? onImageSelected;

  /// Callback when image is taken with camera (optional, for identified mode).
  final void Function(File file)? onCameraImageSelected;

  /// Callback when document is selected (optional, for identified mode).
  final void Function(File file)? onDocumentSelected;

  /// Callback when voice message is recorded (optional, for identified mode).
  final void Function(File file, int duration)? onVoiceRecorded;

  /// Whether the input is enabled.
  final bool enabled;

  /// Custom disabled message to show when input is disabled.
  final String? disabledMessage;

  const SharedChatInput({
    super.key,
    required this.config,
    required this.onSend,
    this.onTypingChanged,
    this.onImageSelected,
    this.onCameraImageSelected,
    this.onDocumentSelected,
    this.onVoiceRecorded,
    this.enabled = true,
    this.disabledMessage,
  });

  @override
  State<SharedChatInput> createState() => _SharedChatInputState();
}

class _SharedChatInputState extends State<SharedChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;

    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // If disabled, show disabled message
    if (!widget.enabled) {
      return _buildDisabledInput(context);
    }

    // For Connections chat, use full ChatInput widget with media support
    if (widget.config.enableMediaAttachments &&
        widget.config.displayMode == ChatDisplayMode.identified) {
      return ChatInput(
        onSend: widget.onSend,
        onTypingChanged: widget.onTypingChanged ?? (_) {},
        onImageSelected: widget.onImageSelected,
        onCameraImageSelected: widget.onCameraImageSelected,
        onDocumentSelected: widget.onDocumentSelected,
        onVoiceRecorded: widget.onVoiceRecorded,
      );
    }

    // For text-only chat, use simplified input
    return _buildSimpleInput(context);
  }

  Widget _buildDisabledInput(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Text(
        widget.disabledMessage ?? 'Chat ended',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSimpleInput(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: widget.config.inputPlaceholder ?? 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              onChanged: (text) {
                // Notify typing status if callback provided
                if (widget.onTypingChanged != null &&
                    widget.config.showTypingIndicator) {
                  widget.onTypingChanged!(text.isNotEmpty);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _handleSend,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
