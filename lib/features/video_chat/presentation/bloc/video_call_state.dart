part of 'video_call_bloc.dart';

/// States for the Video Call BLoC.
sealed class VideoCallState extends Equatable {
  const VideoCallState();

  @override
  List<Object?> get props => [];
}

/// No active call.
class VideoCallIdle extends VideoCallState {
  const VideoCallIdle();
}

/// Setting up the WebRTC connection (initializing media, creating offer).
class VideoCallSettingUp extends VideoCallState {
  const VideoCallSettingUp();
}

/// Outgoing call is ringing (waiting for receiver to pick up).
class VideoCallRinging extends VideoCallState {
  final String callId;
  final String receiverName;
  final String? receiverPhotoUrl;
  final MediaStream? localStream;

  const VideoCallRinging({
    required this.callId,
    required this.receiverName,
    this.receiverPhotoUrl,
    this.localStream,
  });

  @override
  List<Object?> get props => [
        callId,
        receiverName,
        receiverPhotoUrl,
        localStream?.id,
      ];
}

/// Incoming call is being presented to the user.
class VideoCallIncomingState extends VideoCallState {
  final String callId;
  final String callerName;
  final String? callerPhotoUrl;

  const VideoCallIncomingState({
    required this.callId,
    required this.callerName,
    this.callerPhotoUrl,
  });

  @override
  List<Object?> get props => [callId, callerName, callerPhotoUrl];
}

/// WebRTC connection is being established (SDP exchange done, ICE in progress).
class VideoCallConnecting extends VideoCallState {
  final String callId;
  final MediaStream? localStream;

  const VideoCallConnecting({
    required this.callId,
    this.localStream,
  });

  @override
  List<Object?> get props => [callId, localStream?.id];
}

/// Call is connected — both local and remote media are flowing.
class VideoCallConnected extends VideoCallState {
  final String callId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final MediaStream? localStream;
  final MediaStream? remoteStream;
  final bool isMicMuted;
  final bool isCameraOff;
  final DateTime connectedAt;

  const VideoCallConnected({
    required this.callId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
    this.localStream,
    this.remoteStream,
    this.isMicMuted = false,
    this.isCameraOff = false,
    required this.connectedAt,
  });

  VideoCallConnected copyWith({
    MediaStream? remoteStream,
    bool? isMicMuted,
    bool? isCameraOff,
  }) {
    return VideoCallConnected(
      callId: callId,
      otherUserName: otherUserName,
      otherUserPhotoUrl: otherUserPhotoUrl,
      localStream: localStream,
      remoteStream: remoteStream ?? this.remoteStream,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      connectedAt: connectedAt,
    );
  }

  @override
  List<Object?> get props => [
        callId,
        otherUserName,
        isMicMuted,
        isCameraOff,
        connectedAt,
        localStream?.id,
        remoteStream?.id,
      ];
}

/// The call has ended.
class VideoCallEndedState extends VideoCallState {
  final String reason;

  const VideoCallEndedState({this.reason = 'Call ended'});

  @override
  List<Object?> get props => [reason];
}

/// An error occurred during the call.
class VideoCallError extends VideoCallState {
  final String message;

  const VideoCallError({required this.message});

  @override
  List<Object?> get props => [message];
}
