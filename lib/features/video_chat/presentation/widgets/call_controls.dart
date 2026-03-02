import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Bottom control bar for an active video call.
///
/// Provides buttons for: mute mic, toggle camera, switch camera, end call.
class CallControls extends StatelessWidget {
  final bool isMicMuted;
  final bool isCameraOff;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEndCall;

  const CallControls({
    super.key,
    required this.isMicMuted,
    required this.isCameraOff,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Toggle Mic
          _ControlButton(
            icon: isMicMuted ? Icons.mic_off : Icons.mic,
            label: isMicMuted ? 'Unmute' : 'Mute',
            isActive: !isMicMuted,
            onPressed: onToggleMic,
          ),

          // Toggle Camera
          _ControlButton(
            icon: isCameraOff ? Icons.videocam_off : Icons.videocam,
            label: isCameraOff ? 'Camera On' : 'Camera Off',
            isActive: !isCameraOff,
            onPressed: onToggleCamera,
          ),

          // Switch Camera
          _ControlButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Flip',
            isActive: true,
            onPressed: onSwitchCamera,
          ),

          // End Call
          _ControlButton(
            icon: Icons.call_end,
            label: 'End',
            isActive: false,
            isEndCall: true,
            onPressed: onEndCall,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isEndCall;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.isEndCall = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isEndCall
        ? AppTheme.errorColor
        : isActive
            ? Colors.white24
            : Colors.white.withValues(alpha: 0.1);

    final iconColor = isEndCall
        ? Colors.white
        : isActive
            ? Colors.white
            : Colors.white60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
