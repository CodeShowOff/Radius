import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'voice_recorder_widget.dart';

/// Chat input widget for composing messages.
class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final ValueChanged<bool>? onTypingChanged;
  final ValueChanged<File>? onImageSelected;
  final ValueChanged<File>? onCameraImageSelected;
  final ValueChanged<File>? onDocumentSelected;
  final ValueChanged<File>? onVideoSelected;
  final void Function(File file, int duration)? onVoiceRecorded;
  final bool enabled;
  final String? hintText;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onTypingChanged,
    this.onImageSelected,
    this.onCameraImageSelected,
    this.onDocumentSelected,
    this.onVideoSelected,
    this.onVoiceRecorded,
    this.enabled = true,
    this.hintText,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  late TextEditingController _controller;
  final ImagePicker _imagePicker = ImagePicker();
  bool _hasText = false;
  bool _isTyping = false;
  bool _isRecording = false;

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

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        widget.onImageSelected?.call(File(image.path));
      }
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('permission') ||
          errorMessage.contains('denied')) {
        _showError('Photo library access is required. '
            'Please enable photo library permission in your device settings.');
      } else {
        _showError('Failed to pick image: $e');
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        widget.onCameraImageSelected?.call(File(image.path));
      }
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('permission') ||
          errorMessage.contains('denied')) {
        _showError('Camera access is required. '
            'Please enable camera permission in your device settings.');
      } else {
        _showError('Failed to take photo: $e');
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        widget.onDocumentSelected?.call(File(result.files.single.path!));
      }
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('permission') ||
          errorMessage.contains('denied')) {
        _showError('Storage access is required to select documents. '
            'Please enable storage permission in your device settings.');
      } else {
        _showError('Failed to pick document: $e');
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => AttachmentPicker(
        onImagePressed: () {
          Navigator.pop(context);
          _pickImageFromGallery();
        },
        onCameraPressed: () {
          Navigator.pop(context);
          _pickImageFromCamera();
        },
        onFilePressed: () {
          Navigator.pop(context);
          _pickDocument();
        },
        onVideoPressed: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video sharing is coming soon!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _startVoiceRecording() {
    setState(() {
      _isRecording = true;
    });
  }

  void _cancelVoiceRecording() {
    setState(() {
      _isRecording = false;
    });
  }

  /// Called by VoiceRecorderWidget with the recorded file AND the actual duration.
  void _onVoiceRecordingComplete(File file, int durationSeconds) {
    widget.onVoiceRecorded?.call(file, durationSeconds);
    setState(() {
      _isRecording = false;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecording) {
      return VoiceRecorderWidget(
        onRecordingComplete: _onVoiceRecordingComplete,
        onCancel: _cancelVoiceRecording,
      );
    }

    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: 12 + mediaQuery.viewInsets.bottom / 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button
            IconButton(
              onPressed: widget.enabled ? _showAttachmentOptions : null,
              icon: const Icon(Icons.add_circle_outline),
              color: theme.colorScheme.primary,
              iconSize: 28,
            ),

            const SizedBox(width: 4),

            // Text field - fully rounded
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 48,
                  maxHeight: 120,
                ),
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
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? 'Type a message...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button or voice button
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.enabled
                      ? (_hasText ? _sendMessage : _startVoiceRecording)
                      : null,
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: Icon(
                      _hasText ? Icons.send_rounded : Icons.mic,
                      size: 22,
                      color: theme.colorScheme.onPrimary,
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

/// Attachment picker bottom sheet.
class AttachmentPicker extends StatelessWidget {
  final VoidCallback? onImagePressed;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onFilePressed;
  final VoidCallback? onVideoPressed;

  const AttachmentPicker({
    super.key,
    this.onImagePressed,
    this.onCameraPressed,
    this.onFilePressed,
    this.onVideoPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Send',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachmentOption(
                icon: Icons.photo_library_outlined,
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
                label: 'Document',
                color: theme.colorScheme.tertiary,
                onTap: onFilePressed,
              ),
              _AttachmentOption(
                icon: Icons.videocam_outlined,
                label: 'Video',
                color: Colors.orange,
                onTap: onVideoPressed,
                isUpcoming: true,
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
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
  final bool isUpcoming;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.isUpcoming = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              if (isUpcoming)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Soon',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
