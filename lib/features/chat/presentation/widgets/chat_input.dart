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
  int _recordingDuration = 0;

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
      ),
    );
  }

  void _startVoiceRecording() {
    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });
  }

  void _cancelVoiceRecording() {
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  void _onVoiceRecordingComplete(File file) {
    widget.onVoiceRecorded?.call(file, _recordingDuration);
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  int _getRecordingDuration() {
    return _recordingDuration;
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
        getDuration: _getRecordingDuration,
        onCancel: _cancelVoiceRecording,
      );
    }

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
          // Attachment button
          IconButton(
            onPressed: widget.enabled ? _showAttachmentOptions : null,
            icon: const Icon(Icons.add_circle_outline),
            color: theme.colorScheme.primary,
          ),

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

          // Send button or voice button
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 48,
            height: 48,
            child: _hasText
                ? Material(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      onTap: widget.enabled ? _sendMessage : null,
                      borderRadius: BorderRadius.circular(24),
                      child: Center(
                        child: Icon(
                          Icons.send_rounded,
                          size: 22,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  )
                : Material(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      onTap: widget.enabled ? _startVoiceRecording : null,
                      borderRadius: BorderRadius.circular(24),
                      child: Center(
                        child: Icon(
                          Icons.mic,
                          size: 22,
                          color: theme.colorScheme.onPrimary,
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

/// Attachment picker bottom sheet.
class AttachmentPicker extends StatelessWidget {
  final VoidCallback? onImagePressed;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onFilePressed;

  const AttachmentPicker({
    super.key,
    this.onImagePressed,
    this.onCameraPressed,
    this.onFilePressed,
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
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
