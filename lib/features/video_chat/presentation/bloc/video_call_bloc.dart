import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

import '../../data/video_call_service.dart';
import '../../data/webrtc_service.dart';
import '../../domain/entities/call_status.dart';
import '../../domain/entities/video_call.dart';
import '../../domain/entities/video_chat_profile.dart';

part 'video_call_event.dart';
part 'video_call_state.dart';

/// BLoC managing the full lifecycle of a video call:
///
/// - Outgoing: create offer → wait for answer → ICE → connected
/// - Incoming: receive offer → create answer → ICE → connected
/// - Controls: mute mic, toggle camera, switch camera, end call
class VideoCallBloc extends Bloc<VideoCallEvent, VideoCallState> {
  final VideoCallService _callService;
  final WebRtcService _webRtcService;
  final Logger _logger;

  /// Current user's anonymous video chat profile.
  VideoChatProfile? _myProfile;

  String _currentCallId = '';
  String _myUserId = '';
  String _otherUserName = '';
  String? _otherUserPhotoUrl;
  bool _iceConnected = false;

  StreamSubscription? _callStatusSub;
  StreamSubscription? _iceCandidateSub;

  VideoCallBloc({
    required VideoCallService callService,
    required WebRtcService webRtcService,
    Logger? logger,
  })  : _callService = callService,
        _webRtcService = webRtcService,
        _logger = logger ?? Logger(),
        super(const VideoCallIdle()) {
    on<VideoCallInitiated>(_onInitiated);
    on<VideoCallIncoming>(_onIncoming);
    on<VideoCallAccepted>(_onAccepted);
    on<VideoCallDeclined>(_onDeclined);
    on<VideoCallEnded>(_onEnded);
    on<VideoCallMicToggled>(_onMicToggled);
    on<VideoCallCameraToggled>(_onCameraToggled);
    on<VideoCallCameraSwitched>(_onCameraSwitched);
    on<VideoCallAwaitMatch>(_onAwaitMatch);
    on<_IncomingMatchCallFound>(_onIncomingMatchCallFound);
    on<_VideoCallStatusChanged>(_onStatusChanged);
    on<_IceCandidatesReceived>(_onIceCandidatesReceived);
    on<_WebRtcConnected>(_onWebRtcConnected);
    on<_WebRtcDisconnected>(_onWebRtcDisconnected);
  }

  /// Sets the current user's profile. Must be called before initiating/receiving calls.
  void setMyProfile(VideoChatProfile profile) {
    _myProfile = profile;
    _myUserId = profile.userId;
  }

  // ════════════════════════════════════════════════════════════════════
  //  Outgoing Call Flow
  // ════════════════════════════════════════════════════════════════════

  Future<void> _onInitiated(
    VideoCallInitiated event,
    Emitter<VideoCallState> emit,
  ) async {
    if (_myProfile == null) {
      emit(const VideoCallError(message: 'Profile not set up'));
      return;
    }

    emit(const VideoCallSettingUp());
    _otherUserName = event.receiverName;
    _otherUserPhotoUrl = event.receiverPhotoUrl;

    try {
      // Initialize WebRTC (gets local camera/mic stream, creates peer connection)
      await _webRtcService.initialize();

      // Wire up WebRTC callbacks
      _setupWebRtcCallbacks();

      // Create SDP offer
      final offer = await _webRtcService.createOffer();

      // Create call document in Firestore
      _currentCallId = await _callService.createCall(
        callerId: _myUserId,
        callerName: _myProfile!.displayName,
        callerPhotoUrl: _myProfile!.photoUrl,
        receiverId: event.receiverId,
        receiverName: event.receiverName,
        receiverPhotoUrl: event.receiverPhotoUrl,
        offer: {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      );

      // Start listening for call status changes (waiting for answer)
      _watchCallStatus(_currentCallId);
      _watchIceCandidates(_currentCallId);

      emit(VideoCallRinging(
        callId: _currentCallId,
        receiverName: event.receiverName,
        receiverPhotoUrl: event.receiverPhotoUrl,
        localStream: _webRtcService.localStream,
      ));
    } catch (e, st) {
      _logger.e('Failed to initiate call', error: e, stackTrace: st);
      await _cleanup();
      emit(VideoCallError(message: 'Failed to start call: $e'));
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Incoming Call Flow
  // ════════════════════════════════════════════════════════════════════

  Future<void> _onIncoming(
    VideoCallIncoming event,
    Emitter<VideoCallState> emit,
  ) async {
    _currentCallId = event.callId;

    try {
      // Fetch call data
      final callStream = _callService.watchCall(event.callId);
      final call = await callStream.first;

      if (call == null || call.status != CallStatus.ringing) {
        emit(const VideoCallEndedState(reason: 'Call no longer available'));
        return;
      }

      _otherUserName = call.callerName;
      _otherUserPhotoUrl = call.callerPhotoUrl;

      emit(VideoCallIncomingState(
        callId: event.callId,
        callerName: call.callerName,
        callerPhotoUrl: call.callerPhotoUrl,
      ));
    } catch (e, st) {
      _logger.e('Failed to load incoming call', error: e, stackTrace: st);
      emit(VideoCallError(message: 'Failed to load call: $e'));
    }
  }

  Future<void> _onAccepted(
    VideoCallAccepted event,
    Emitter<VideoCallState> emit,
  ) async {
    emit(VideoCallConnecting(
      callId: _currentCallId,
      localStream: null,
    ));

    try {
      // Initialize WebRTC
      await _webRtcService.initialize();
      _setupWebRtcCallbacks();

      // Get the call's offer from Firestore
      final callStream = _callService.watchCall(_currentCallId);
      final call = await callStream.first;

      if (call?.offer == null) {
        emit(const VideoCallError(message: 'Call offer not found'));
        return;
      }

      // Create answer from the offer
      final remoteOffer = RTCSessionDescription(
        call!.offer!['sdp'] as String?,
        call.offer!['type'] as String?,
      );
      final answer = await _webRtcService.createAnswer(remoteOffer);

      // Send answer to Firestore
      await _callService.answerCall(
        callId: _currentCallId,
        answer: {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      );

      // Start listening for ICE candidates
      _watchIceCandidates(_currentCallId);

      emit(VideoCallConnecting(
        callId: _currentCallId,
        localStream: _webRtcService.localStream,
      ));
    } catch (e, st) {
      _logger.e('Failed to accept call', error: e, stackTrace: st);
      await _cleanup();
      emit(VideoCallError(message: 'Failed to accept call: $e'));
    }
  }

  Future<void> _onDeclined(
    VideoCallDeclined event,
    Emitter<VideoCallState> emit,
  ) async {
    if (_currentCallId.isNotEmpty) {
      await _callService.declineCall(_currentCallId);
    }
    await _cleanup();
    emit(const VideoCallEndedState(reason: 'Call declined'));
  }

  Future<void> _onEnded(
    VideoCallEnded event,
    Emitter<VideoCallState> emit,
  ) async {
    if (_currentCallId.isNotEmpty) {
      await _callService.endCall(_currentCallId);
      // Cleanup signaling data after a short delay
      final callIdToClean = _currentCallId;
      Future.delayed(const Duration(seconds: 5), () {
        _callService.cleanupCall(callIdToClean);
      });
    }
    await _cleanup();
    emit(const VideoCallEndedState(reason: 'Call ended'));
  }

  // ════════════════════════════════════════════════════════════════════
  //  Media Controls
  // ════════════════════════════════════════════════════════════════════

  void _onMicToggled(
    VideoCallMicToggled event,
    Emitter<VideoCallState> emit,
  ) {
    final muted = _webRtcService.toggleMic();
    if (state is VideoCallConnected) {
      emit((state as VideoCallConnected).copyWith(isMicMuted: muted));
    }
  }

  void _onCameraToggled(
    VideoCallCameraToggled event,
    Emitter<VideoCallState> emit,
  ) {
    final off = _webRtcService.toggleCamera();
    if (state is VideoCallConnected) {
      emit((state as VideoCallConnected).copyWith(isCameraOff: off));
    }
  }

  Future<void> _onCameraSwitched(
    VideoCallCameraSwitched event,
    Emitter<VideoCallState> emit,
  ) async {
    await _webRtcService.switchCamera();
  }

  // ════════════════════════════════════════════════════════════════
  //  Receiver: Wait for Matched Caller’s Call
  // ════════════════════════════════════════════════════════════════

  /// Receiver side of the Omegle-style match flow.
  ///
  /// Watches for an incoming call from the matched caller and
  /// dispatches [_IncomingMatchCallFound] when detected. The actual
  /// WebRTC auto-accept work happens in [_onIncomingMatchCallFound]
  /// which has a valid [emit].
  Future<void> _onAwaitMatch(
    VideoCallAwaitMatch event,
    Emitter<VideoCallState> emit,
  ) async {
    if (_myProfile == null) {
      emit(const VideoCallError(message: 'Profile not set up'));
      return;
    }

    _otherUserName = event.matchedName;
    _otherUserPhotoUrl = event.matchedPhotoUrl;

    emit(const VideoCallConnecting(
      callId: '',
      localStream: null,
    ));

    _logger.d('Receiver waiting for call from ${event.matchedUserId}');

    // Watch for incoming calls where we are the receiver.
    // When found, dispatch an internal event so the work runs
    // inside a proper handler with a valid `emit`.
    _callStatusSub?.cancel();
    _callStatusSub = _callService.watchIncomingCalls(_myUserId).listen(
      (call) {
        if (call != null && call.callerId == event.matchedUserId) {
          _logger.d('Incoming call detected from match: ${call.id}');
          _callStatusSub?.cancel();
          _callStatusSub = null;
          add(_IncomingMatchCallFound(call: call));
        }
      },
      onError: (e) {
        _logger.e('Incoming call watch error: $e');
      },
    );
  }

  /// Handles the actual auto-accept once the receiver detects the
  /// matched caller's call document in Firestore.
  Future<void> _onIncomingMatchCallFound(
    _IncomingMatchCallFound event,
    Emitter<VideoCallState> emit,
  ) async {
    final call = event.call;
    _currentCallId = call.id;

    try {
      await _webRtcService.initialize();
      _setupWebRtcCallbacks();

      if (call.offer == null) {
        emit(const VideoCallError(message: 'Call offer not found'));
        return;
      }

      final remoteOffer = RTCSessionDescription(
        call.offer!['sdp'] as String?,
        call.offer!['type'] as String?,
      );
      final answer = await _webRtcService.createAnswer(remoteOffer);

      await _callService.answerCall(
        callId: _currentCallId,
        answer: {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      );

      // Listen for ICE candidates and call status changes.
      _watchCallStatus(_currentCallId);
      _watchIceCandidates(_currentCallId);

      emit(VideoCallConnecting(
        callId: _currentCallId,
        localStream: _webRtcService.localStream,
      ));
    } catch (e, st) {
      _logger.e('Failed to auto-accept call', error: e, stackTrace: st);
      await _cleanup();
      emit(VideoCallError(message: 'Failed to connect: $e'));
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Internal: Firestore & WebRTC Callbacks
  // ════════════════════════════════════════════════════════════════════

  Future<void> _onStatusChanged(
    _VideoCallStatusChanged event,
    Emitter<VideoCallState> emit,
  ) async {
    final call = event.call;
    if (call == null) return;

    switch (call.status) {
      case CallStatus.connecting:
        // Caller receives the answer — set remote description
        if (call.answer != null && state is VideoCallRinging) {
          try {
            final remoteAnswer = RTCSessionDescription(
              call.answer!['sdp'] as String?,
              call.answer!['type'] as String?,
            );
            await _webRtcService.setRemoteDescription(remoteAnswer);
            emit(VideoCallConnecting(
              callId: _currentCallId,
              localStream: _webRtcService.localStream,
            ));
          } catch (e) {
            _logger.e('Failed to set remote answer: $e');
          }
        }
        break;

      case CallStatus.ended:
      case CallStatus.declined:
      case CallStatus.missed:
        await _cleanup();
        final reason = switch (call.status) {
          CallStatus.declined => 'Call was declined',
          CallStatus.missed => 'No answer',
          _ => 'Call ended',
        };
        emit(VideoCallEndedState(reason: reason));
        break;

      default:
        break;
    }
  }

  void _onIceCandidatesReceived(
    _IceCandidatesReceived event,
    Emitter<VideoCallState> emit,
  ) {
    for (final candidateData in event.candidates) {
      final candidate = RTCIceCandidate(
        candidateData['candidate'] as String?,
        candidateData['sdpMid'] as String?,
        candidateData['sdpMLineIndex'] as int?,
      );
      _webRtcService.addIceCandidate(candidate);
    }
  }

  void _onWebRtcConnected(
    _WebRtcConnected event,
    Emitter<VideoCallState> emit,
  ) {
    // Only mark as connected in Firestore once.
    if (_currentCallId.isNotEmpty && state is! VideoCallConnected) {
      _callService.markConnected(_currentCallId);
    }

    emit(VideoCallConnected(
      callId: _currentCallId,
      otherUserName: _otherUserName,
      otherUserPhotoUrl: _otherUserPhotoUrl,
      localStream: _webRtcService.localStream,
      remoteStream: _webRtcService.remoteStream,
      isMicMuted: _webRtcService.isMicMuted,
      isCameraOff: _webRtcService.isCameraOff,
      connectedAt: DateTime.now(),
    ));
  }

  Future<void> _onWebRtcDisconnected(
    _WebRtcDisconnected event,
    Emitter<VideoCallState> emit,
  ) async {
    if (state is VideoCallConnected || state is VideoCallConnecting) {
      if (_currentCallId.isNotEmpty) {
        await _callService.endCall(_currentCallId);
      }
      await _cleanup();
      emit(const VideoCallEndedState(reason: 'Connection lost'));
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Helpers
  // ════════════════════════════════════════════════════════════════════

  void _setupWebRtcCallbacks() {
    _webRtcService.onIceCandidate = (candidate) {
      if (_currentCallId.isNotEmpty) {
        _callService.addIceCandidate(
          callId: _currentCallId,
          from: _myUserId,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    _webRtcService.onRemoteStream = (stream) {
      // Always notify: if ICE already connected, re-emit so the UI
      // picks up the remote stream. If ICE hasn't connected yet, the
      // stream is stored in the service and will be included when
      // onConnected fires.
      if (_iceConnected && !isClosed) {
        add(const _WebRtcConnected());
      }
    };

    _webRtcService.onConnected = () {
      _iceConnected = true;
      add(const _WebRtcConnected());
    };

    _webRtcService.onDisconnected = () {
      add(const _WebRtcDisconnected());
    };
  }

  void _watchCallStatus(String callId) {
    _callStatusSub?.cancel();
    _callStatusSub = _callService.watchCall(callId).listen(
      (call) => add(_VideoCallStatusChanged(call: call)),
      onError: (e) => _logger.e('Call status stream error: $e'),
    );
  }

  void _watchIceCandidates(String callId) {
    _iceCandidateSub?.cancel();
    _iceCandidateSub = _callService
        .watchIceCandidates(callId: callId, myUserId: _myUserId)
        .listen(
      (candidates) {
        if (candidates.isNotEmpty) {
          add(_IceCandidatesReceived(candidates: candidates));
        }
      },
      onError: (e) => _logger.e('ICE candidates stream error: $e'),
    );
  }

  Future<void> _cleanup() async {
    _callStatusSub?.cancel();
    _callStatusSub = null;
    _iceCandidateSub?.cancel();
    _iceCandidateSub = null;
    _iceConnected = false;
    await _webRtcService.dispose();
  }

  @override
  Future<void> close() async {
    await _cleanup();
    return super.close();
  }
}
