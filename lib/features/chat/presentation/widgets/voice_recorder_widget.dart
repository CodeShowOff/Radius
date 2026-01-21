import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Widget for recording voice messages.
class VoiceRecorderWidget extends StatefulWidget {
  final ValueChanged<File> onRecordingComplete;
  final int Function() getDuration;
  final VoidCallback onCancel;

  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    required this.getDuration,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _timer;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // Check if we have permission
      final hasPermission = await _audioRecorder.hasPermission();

      if (!hasPermission) {
        // Try to request permission
        final permissionGranted = await _audioRecorder.hasPermission();

        if (!permissionGranted) {
          _showError('Microphone access is required to record voice messages. '
              'Please enable microphone permission in your device settings.');
          return;
        }
      }

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _audioPath = path;
      });

      // Start timer
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordDuration++;
          });

          // Auto-stop after 5 minutes
          if (_recordDuration >= 300) {
            _stopRecording();
          }
        }
      });
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _timer?.cancel();

      if (_isRecording) {
        final path = await _audioRecorder.stop();

        if (!mounted) return;
        setState(() {
          _isRecording = false;
        });

        if (path != null && await File(path).exists()) {
          widget.onRecordingComplete(File(path));
        } else {
          _showError('Recording file not found');
        }
      }
    } catch (e) {
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _timer?.cancel();

      if (_isRecording) {
        await _audioRecorder.stop();

        // Delete the recorded file
        if (_audioPath != null) {
          final file = File(_audioPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      widget.onCancel();
    } catch (e) {
      _showError('Failed to cancel recording: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      widget.onCancel();
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
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
        children: [
          // Cancel button
          IconButton(
            onPressed: _cancelRecording,
            icon: const Icon(Icons.delete),
            color: theme.colorScheme.error,
          ),

          const SizedBox(width: 8),

          // Recording indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated recording dot
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? theme.colorScheme.error
                        : Colors.transparent,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.mic,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(_recordDuration),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Send button
          Material(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: _recordDuration > 0 ? _stopRecording : null,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Icon(
                  Icons.send_rounded,
                  size: 22,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
