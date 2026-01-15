import 'package:flutter/material.dart';

/// Chat input widget for composing messages.
class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final ValueChanged<bool>? onTypingChanged;
  final bool enabled;
  final String? hintText;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onTypingChanged,
    this.enabled = true,
    this.hintText,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  late TextEditingController _controller;
  bool _hasText = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }

    // Notify typing state
    if (hasText && !_isTyping) {
      _isTyping = true;
      widget.onTypingChanged?.call(true);
    } else if (!hasText && _isTyping) {
      _isTyping = false;
      widget.onTypingChanged?.call(false);
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSend(text);
    _controller.clear();
    _isTyping = false;
    widget.onTypingChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: widget.hintText ?? 'Message',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 48,
            height: 48,
            child: Material(
              color: _hasText && widget.enabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                onTap: _hasText && widget.enabled ? _sendMessage : null,
                borderRadius: BorderRadius.circular(24),
                child: Center(
                  child: Icon(
                    Icons.send_rounded,
                    size: 22,
                    color: _hasText && widget.enabled
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional attachment picker for future use.
class AttachmentPicker extends StatelessWidget {
  final VoidCallback? onImagePressed;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onFilePressed;
  final VoidCallback? onLocationPressed;

  const AttachmentPicker({
    super.key,
    this.onImagePressed,
    this.onCameraPressed,
    this.onFilePressed,
    this.onLocationPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AttachmentOption(
            icon: Icons.image_outlined,
            label: 'Gallery',
            color: theme.colorScheme.primary,
            onTap: onImagePressed,
          ),
          _AttachmentOption(
            icon: Icons.camera_alt_outlined,
            label: 'Camera',
            color: theme.colorScheme.secondary,
            onTap: onCameraPressed,
          ),
          _AttachmentOption(
            icon: Icons.insert_drive_file_outlined,
            label: 'File',
            color: theme.colorScheme.tertiary,
            onTap: onFilePressed,
          ),
          _AttachmentOption(
            icon: Icons.location_on_outlined,
            label: 'Location',
            color: theme.colorScheme.error,
            onTap: onLocationPressed,
          ),
        ],
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
