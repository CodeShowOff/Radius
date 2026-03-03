part of 'video_call_bloc.dart';

/// Events for the Video Call BLoC.
sealed class VideoCallEvent extends Equatable {
  const VideoCallEvent();

  @override
  List<Object?> get props => [];
}

/// Initiates a call to another user.
class VideoCallInitiated extends VideoCallEvent {
  final String receiverId;
  final String receiverName;
  final String? receiverPhotoUrl;

  const VideoCallInitiated({
    required this.receiverId,
    required this.receiverName,
    this.receiverPhotoUrl,
  });

  @override
  List<Object?> get props => [receiverId, receiverName, receiverPhotoUrl];
}

/// Handles an incoming call (loads call data and shows UI).
class VideoCallIncoming extends VideoCallEvent {
  final String callId;

  const VideoCallIncoming({required this.callId});

  @override
  List<Object?> get props => [callId];
}

/// Accepts an incoming call.
class VideoCallAccepted extends VideoCallEvent {
  const VideoCallAccepted();
}

/// Declines an incoming call.
class VideoCallDeclined extends VideoCallEvent {
  const VideoCallDeclined();
}

/// Ends an active call.
class VideoCallEnded extends VideoCallEvent {
  const VideoCallEnded();
}

/// Toggles the microphone on/off.
class VideoCallMicToggled extends VideoCallEvent {
  const VideoCallMicToggled();
}

/// Toggles the camera on/off.
class VideoCallCameraToggled extends VideoCallEvent {
  const VideoCallCameraToggled();
}

/// Switches between front and back camera.
class VideoCallCameraSwitched extends VideoCallEvent {
  const VideoCallCameraSwitched();
}

/// Receiver waits for the matched caller to create the call document,
/// then auto-accepts. Used in the Omegle-style random match flow where
/// both users have already consented.
class VideoCallAwaitMatch extends VideoCallEvent {
  final String matchedUserId;
  final String matchedName;
  final String? matchedPhotoUrl;

  const VideoCallAwaitMatch({
    required this.matchedUserId,
    required this.matchedName,
    this.matchedPhotoUrl,
  });

  @override
  List<Object?> get props => [matchedUserId, matchedName, matchedPhotoUrl];
}

/// Internal: remote call status changed (from Firestore listener).
class _VideoCallStatusChanged extends VideoCallEvent {
  final VideoCall? call;

  const _VideoCallStatusChanged({this.call});

  @override
  List<Object?> get props => [call];
}

/// Internal: new ICE candidates received from the remote peer.
class _IceCandidatesReceived extends VideoCallEvent {
  final List<Map<String, dynamic>> candidates;

  const _IceCandidatesReceived({required this.candidates});

  @override
  List<Object?> get props => [candidates];
}

/// Internal: WebRTC connection state changed.
class _WebRtcConnected extends VideoCallEvent {
  const _WebRtcConnected();
}

/// Internal: WebRTC disconnected/failed.
class _WebRtcDisconnected extends VideoCallEvent {
  const _WebRtcDisconnected();
}

/// Internal: ICE temporarily disconnected (may recover).
class _WebRtcTemporarilyDisconnected extends VideoCallEvent {
  const _WebRtcTemporarilyDisconnected();
}

/// Internal: Remote media stream received/updated.
class _RemoteStreamReceived extends VideoCallEvent {
  const _RemoteStreamReceived();
}

/// Internal: the receiver detected an incoming call from the matched caller.
/// Triggers auto-accept (WebRTC init → answer → ICE).
class _IncomingMatchCallFound extends VideoCallEvent {
  final VideoCall call;

  const _IncomingMatchCallFound({required this.call});

  @override
  List<Object?> get props => [call];
}
