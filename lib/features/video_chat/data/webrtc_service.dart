import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

/// Service encapsulating WebRTC peer connection management.
///
/// Handles creating/receiving offers and answers, managing local/remote
/// media streams, ICE candidate exchange, and camera/mic controls.
///
/// This is a per-call instance — create a new one for each video call.
class WebRtcService {
  final Logger _logger;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isDisposed = false;

  /// Called when a new ICE candidate is generated locally.
  /// The caller must send this to the remote peer via Firestore.
  void Function(RTCIceCandidate candidate)? onIceCandidate;

  /// Called when the remote peer's media stream is received.
  void Function(MediaStream stream)? onRemoteStream;

  /// Called when the ICE connection state changes.
  void Function(RTCIceConnectionState state)? onConnectionStateChange;

  /// Called when the peer connection is fully connected.
  void Function()? onConnected;

  /// Called when ICE enters a temporary disconnected state (recoverable).
  void Function()? onTemporarilyDisconnected;

  /// Called when the peer connection is permanently disconnected/failed.
  void Function()? onDisconnected;

  WebRtcService({Logger? logger}) : _logger = logger ?? Logger();

  // ════════════════════════════════════════════════════════════════════
  //  Getters
  // ════════════════════════════════════════════════════════════════════

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isDisposed => _isDisposed;

  // ════════════════════════════════════════════════════════════════════
  //  ICE Server Configuration
  // ════════════════════════════════════════════════════════════════════

  /// Default ICE servers — STUN + TURN for reliable connectivity.
  ///
  /// STUN alone covers ~85% of P2P connections. TURN relay servers
  /// are required for peers behind symmetric NATs or restrictive
  /// firewalls (common on mobile carrier networks).
  static const List<Map<String, dynamic>> _defaultIceServers = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
        'stun:stun3.l.google.com:19302',
        'stun:stun4.l.google.com:19302',
      ],
    },
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turns:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  // ════════════════════════════════════════════════════════════════════
  //  Initialization
  // ════════════════════════════════════════════════════════════════════

  /// Initializes the peer connection and local media stream.
  ///
  /// Call this before [createOffer] or [createAnswer].
  /// [iceServers] can override the default STUN config (e.g. to add TURN).
  Future<void> initialize({
    List<Map<String, dynamic>>? iceServers,
    bool enableVideo = true,
    bool enableAudio = true,
  }) async {
    if (_isDisposed) return;

    _logger.d('Initializing WebRTC peer connection');

    // Create peer connection
    final config = {
      'iceServers': iceServers ?? _defaultIceServers,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 1,
    };

    _peerConnection = await createPeerConnection(config);

    // Set up event handlers
    _peerConnection!.onIceCandidate = (candidate) {
      _logger.d('Local ICE candidate: ${candidate.candidate}');
      onIceCandidate?.call(candidate);
    };

    _peerConnection!.onIceConnectionState = (state) {
      _logger.d('ICE connection state: $state');
      onConnectionStateChange?.call(state);

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          // Actively query for remote stream — onTrack can be unreliable
          // on some devices/flutter_webrtc versions.
          _ensureRemoteStream();
          onConnected?.call();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          // Transient — can recover automatically via ICE restart
          onTemporarilyDisconnected?.call();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          onDisconnected?.call();
          break;
        default:
          break;
      }
    };

    _peerConnection!.onTrack = (event) {
      _logger.d('Remote track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream?.call(_remoteStream!);
      } else if (_remoteStream != null) {
        // Unified-plan may deliver tracks without associated streams.
        _logger.w('Remote track has no associated streams, adding to existing');
        _remoteStream!.addTrack(event.track);
        onRemoteStream?.call(_remoteStream!);
      } else {
        // No existing remote stream — create one for this orphan track.
        _logger.w('Remote track has no streams and no existing remote stream, creating one');
        createLocalMediaStream('remote_ontrack').then((stream) {
          stream.addTrack(event.track);
          _remoteStream = stream;
          onRemoteStream?.call(stream);
        });
      }
    };

    // Fallback for platforms/configurations where onTrack doesn't
    // provide streams (deprecated in spec but reliable in flutter_webrtc).
    _peerConnection!.onAddStream = (stream) {
      _logger.d('Remote stream added (onAddStream fallback): ${stream.id}');
      _remoteStream = stream;
      onRemoteStream?.call(stream);
    };

    // Get local media stream
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': enableAudio,
      'video': enableVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    });

    // Add local tracks to the peer connection
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _logger.d('WebRTC initialized with local stream');
  }

  // ════════════════════════════════════════════════════════════════════
  //  Remote Stream Fallback
  // ════════════════════════════════════════════════════════════════════

  /// Actively queries the peer connection for remote streams/receivers.
  ///
  /// Fallback for when [onTrack]/[onAddStream] callbacks don't fire
  /// (known issue on some devices with flutter_webrtc).
  void _ensureRemoteStream() {
    if (_remoteStream != null || _peerConnection == null || _isDisposed) return;

    // Try legacy getRemoteStreams() — matches our onAddStream fallback.
    final streams = _peerConnection!.getRemoteStreams();
    if (streams.isNotEmpty) {
      _logger.d('Remote stream found via getRemoteStreams fallback');
      _remoteStream = streams.first;
      onRemoteStream?.call(_remoteStream!);
      return;
    }

    // If still null, schedule a delayed retry — remote tracks may
    // arrive slightly after ICE connects.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_remoteStream != null || _peerConnection == null || _isDisposed) {
        return;
      }
      final retryStreams = _peerConnection!.getRemoteStreams();
      if (retryStreams.isNotEmpty) {
        _logger.d('Remote stream found via delayed getRemoteStreams fallback');
        _remoteStream = retryStreams.first;
        onRemoteStream?.call(_remoteStream!);
      } else {
        _logger.w('No remote streams found after delayed retry');
      }
    });
  }

  // ════════════════════════════════════════════════════════════════════
  //  Offer / Answer
  // ════════════════════════════════════════════════════════════════════

  /// Creates an SDP offer. Call this if you are the **caller**.
  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _logger.d('Created and set local offer');
    return offer;
  }

  /// Creates an SDP answer after setting the remote offer.
  /// Call this if you are the **receiver**.
  Future<RTCSessionDescription> createAnswer(
      RTCSessionDescription remoteOffer) async {
    await _peerConnection!.setRemoteDescription(remoteOffer);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _logger.d('Created and set local answer');
    return answer;
  }

  /// Sets the remote SDP description (answer from the receiver).
  /// Call this if you are the **caller** after receiver sends their answer.
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _peerConnection!.setRemoteDescription(description);
    _logger.d('Set remote description: ${description.type}');
  }

  // ════════════════════════════════════════════════════════════════════
  //  ICE Candidates
  // ════════════════════════════════════════════════════════════════════

  /// Adds an ICE candidate from the remote peer.
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    try {
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      _logger.w('Failed to add ICE candidate: $e');
    }
  }

  /// Attempts an ICE restart to recover a failed connection.
  ///
  /// Returns the new offer SDP, or `null` if restart is not possible.
  Future<RTCSessionDescription?> restartIce() async {
    if (_peerConnection == null || _isDisposed) return null;

    _logger.d('Attempting ICE restart');
    try {
      final offer = await _peerConnection!.createOffer({
        'iceRestart': true,
      });
      await _peerConnection!.setLocalDescription(offer);
      return offer;
    } catch (e) {
      _logger.e('ICE restart failed: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Media Controls
  // ════════════════════════════════════════════════════════════════════

  /// Toggles the microphone on/off. Returns new mute state.
  bool toggleMic() {
    if (_localStream == null) return _isMicMuted;

    _isMicMuted = !_isMicMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMicMuted;
    }
    _logger.d('Mic ${_isMicMuted ? "muted" : "unmuted"}');
    return _isMicMuted;
  }

  /// Toggles the camera on/off. Returns new camera-off state.
  bool toggleCamera() {
    if (_localStream == null) return _isCameraOff;

    _isCameraOff = !_isCameraOff;
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = !_isCameraOff;
    }
    _logger.d('Camera ${_isCameraOff ? "off" : "on"}');
    return _isCameraOff;
  }

  /// Switches between front and back camera.
  Future<void> switchCamera() async {
    if (_localStream == null) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
      _logger.d('Camera switched');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Cleanup
  // ════════════════════════════════════════════════════════════════════

  /// Disposes all resources — local/remote streams and peer connection.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _logger.d('Disposing WebRTC service');

    // Stop local tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Dispose remote stream
    if (_remoteStream != null) {
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    // Close peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }

    onIceCandidate = null;
    onRemoteStream = null;
    onConnectionStateChange = null;
    onConnected = null;
    onTemporarilyDisconnected = null;
    onDisconnected = null;
  }
}
