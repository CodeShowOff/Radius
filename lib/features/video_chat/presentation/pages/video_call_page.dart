import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/video_call_bloc.dart';
import '../widgets/call_controls.dart';

/// Full-screen video call page.
///
/// Shows local + remote video streams, call controls,
/// caller info, and a call duration timer.
class VideoCallPage extends StatefulWidget {
  const VideoCallPage({super.key});

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage>
    with WidgetsBindingObserver {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  bool _durationTimerStarted = false;

  // Pending streams queued before renderers were ready.
  MediaStream? _pendingLocalStream;
  MediaStream? _pendingRemoteStream;

  // Track last-seen streams so we can reassign on lifecycle resume.
  MediaStream? _lastLocalStream;
  MediaStream? _lastRemoteStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableWakeLock();
    _initRenderers();
  }

  Future<void> _enableWakeLock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Non-fatal — screen may sleep but call still works.
    }
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;
    _renderersReady = true;

    // Apply any streams that arrived before renderers were ready.
    if (_pendingLocalStream != null) {
      _localRenderer.srcObject = _pendingLocalStream;
      _lastLocalStream = _pendingLocalStream;
      _pendingLocalStream = null;
    }
    if (_pendingRemoteStream != null) {
      _remoteRenderer.srcObject = _pendingRemoteStream;
      _lastRemoteStream = _pendingRemoteStream;
      _pendingRemoteStream = null;
    }
    setState(() {});
  }

  void _assignLocal(MediaStream? stream) {
    if (stream == null) return;
    _lastLocalStream = stream;
    if (_renderersReady) {
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    } else {
      _pendingLocalStream = stream;
    }
  }

  void _assignRemote(MediaStream? stream) {
    if (stream == null) return;
    _lastRemoteStream = stream;
    if (_renderersReady) {
      // When the same stream is reassigned (e.g. new track added),
      // set to null first, wait a frame for the native texture to
      // release, then reassign. Direct null→set in the same sync
      // frame can cause the texture to never re-acquire.
      if (_remoteRenderer.srcObject?.id == stream.id) {
        _remoteRenderer.srcObject = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _remoteRenderer.srcObject = stream;
          setState(() {});
        });
      } else {
        _remoteRenderer.srcObject = stream;
        if (mounted) setState(() {});
      }
    } else {
      _pendingRemoteStream = stream;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _renderersReady) {
      // Reassign streams after returning from background —
      // the native textures may have been released.
      if (_lastLocalStream != null) {
        _localRenderer.srcObject = _lastLocalStream;
      }
      if (_lastRemoteStream != null) {
        _remoteRenderer.srcObject = _lastRemoteStream;
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disableWakeLock();
    _durationTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _callDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocConsumer<VideoCallBloc, VideoCallState>(
        listener: (context, state) {
          if (state is VideoCallConnected) {
            // Attach streams to renderers.
            _assignLocal(state.localStream);
            _assignRemote(state.remoteStream);
            if (!_durationTimerStarted) {
              _durationTimerStarted = true;
              _startDurationTimer();
            }
          } else if (state is VideoCallConnecting) {
            _assignLocal(state.localStream);
          } else if (state is VideoCallRinging) {
            _assignLocal(state.localStream);
          } else if (state is VideoCallEndedState) {
            _durationTimer?.cancel();
            // Show end reason and pop after delay
            final navigator = Navigator.of(context);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) navigator.pop();
            });
          } else if (state is VideoCallError) {
            final navigator = Navigator.of(context);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) navigator.pop();
            });
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // Remote video (full screen background)
              _buildRemoteVideo(state),

              // Local video (draggable PiP)
              _buildLocalVideo(state),

              // Top bar with user info and call duration
              _buildTopBar(state),

              // Call status overlay (ringing, connecting, ended)
              _buildStatusOverlay(state),

              // Bottom call controls
              if (state is VideoCallConnected ||
                  state is VideoCallConnecting ||
                  state is VideoCallRinging)
                _buildCallControls(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRemoteVideo(VideoCallState state) {
    final hasSrcObject = _remoteRenderer.srcObject != null;
    final hasRemoteVideoTrack = hasSrcObject &&
        _remoteRenderer.srcObject!.getVideoTracks().isNotEmpty;
    final showRenderer =
        (state is VideoCallConnected || state is VideoCallConnecting) &&
            hasSrcObject;

    if (showRenderer) {
      return Positioned.fill(
        child: Stack(
          children: [
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            // Overlay when connected but no video tracks in stream
            if (!hasRemoteVideoTrack && state is VideoCallConnected)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off, color: Colors.white54, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No video from other side',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final waitingText = state is VideoCallConnected
        ? 'Connected • Waiting for video...'
        : state is VideoCallConnecting
            ? 'Connecting video...'
            : null;

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: waitingText == null
            ? null
            : Center(
                child: Text(
                  waitingText,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }

  Widget _buildLocalVideo(VideoCallState state) {
    final hasLocalStream = state is VideoCallConnected ||
        state is VideoCallConnecting ||
        state is VideoCallRinging;

    if (!hasLocalStream || !_renderersReady) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      top: MediaQuery.of(context).padding.top + 80,
      child: GestureDetector(
        child: Container(
          width: 120,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white30, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(VideoCallState state) {
    String name = '';
    if (state is VideoCallConnected) {
      name = state.otherUserName;
    } else if (state is VideoCallRinging) {
      name = state.receiverName;
    } else if (state is VideoCallIncomingState) {
      name = state.callerName;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            if (name.isNotEmpty)
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (state is VideoCallConnected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _formatDuration(_callDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOverlay(VideoCallState state) {
    String? statusText;
    IconData? statusIcon;

    if (state is VideoCallSettingUp) {
      statusText = 'Setting up...';
      statusIcon = Icons.settings;
    } else if (state is VideoCallRinging) {
      statusText = 'Ringing...';
      statusIcon = Icons.ring_volume;
    } else if (state is VideoCallConnecting) {
      statusText = 'Connecting...';
      statusIcon = Icons.sync;
    } else if (state is VideoCallEndedState) {
      statusText = state.reason;
      statusIcon = Icons.call_end;
    } else if (state is VideoCallError) {
      statusText = state.message;
      statusIcon = Icons.error_outline;
    } else if (state is VideoCallIncomingState) {
      statusText = '${state.callerName} is calling...';
      statusIcon = Icons.videocam;
    }

    if (statusText == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (statusIcon != null)
              Icon(statusIcon, size: 48, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (state is VideoCallIncomingState) ...[
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _buildCircleButton(
                    icon: Icons.call_end,
                    color: AppTheme.errorColor,
                    label: 'Decline',
                    onPressed: () {
                      context
                          .read<VideoCallBloc>()
                          .add(const VideoCallDeclined());
                    },
                  ),
                  // Accept button
                  _buildCircleButton(
                    icon: Icons.videocam,
                    color: AppTheme.successColor,
                    label: 'Accept',
                    onPressed: () {
                      context
                          .read<VideoCallBloc>()
                          .add(const VideoCallAccepted());
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: color,
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCallControls(VideoCallState state) {
    bool isMicMuted = false;
    bool isCameraOff = false;

    if (state is VideoCallConnected) {
      isMicMuted = state.isMicMuted;
      isCameraOff = state.isCameraOff;
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: CallControls(
        isMicMuted: isMicMuted,
        isCameraOff: isCameraOff,
        onToggleMic: () =>
            context.read<VideoCallBloc>().add(const VideoCallMicToggled()),
        onToggleCamera: () =>
            context.read<VideoCallBloc>().add(const VideoCallCameraToggled()),
        onSwitchCamera: () =>
            context.read<VideoCallBloc>().add(const VideoCallCameraSwitched()),
        onNext: () {
          final profile = context.read<VideoCallBloc>().myProfile;
          if (profile == null) {
            context.read<VideoCallBloc>().add(const VideoCallEnded());
            return;
          }

          context.pushReplacement(Routes.videoMatch, extra: profile);
        },
        onEndCall: () =>
            context.read<VideoCallBloc>().add(const VideoCallEnded()),
      ),
    );
  }
}
