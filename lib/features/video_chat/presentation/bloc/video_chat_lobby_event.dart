part of 'video_chat_lobby_bloc.dart';

/// Events for the Video Chat Lobby BLoC.
sealed class VideoChatLobbyEvent extends Equatable {
  const VideoChatLobbyEvent();

  @override
  List<Object?> get props => [];
}

/// Triggered when the user enters the video chat feature.
/// Loads the anonymous profile from Firestore (if exists) and checks
/// local settings (age gate, headphones preference).
class VideoChatLobbyEntered extends VideoChatLobbyEvent {
  final String userId;

  const VideoChatLobbyEntered({required this.userId});

  @override
  List<Object?> get props => [userId];
}

/// User has confirmed they are 18+.
class VideoChatAgeVerified extends VideoChatLobbyEvent {
  const VideoChatAgeVerified();
}

/// User dismissed the headphones advisory.
/// If [permanently] is true, it won't show again.
class VideoChatHeadphonesDismissed extends VideoChatLobbyEvent {
  final bool permanently;

  const VideoChatHeadphonesDismissed({this.permanently = false});

  @override
  List<Object?> get props => [permanently];
}

/// User wants to save/update their anonymous profile and proceed.
class VideoChatProfileSaved extends VideoChatLobbyEvent {
  final String displayName;
  final String? photoFilePath;

  const VideoChatProfileSaved({
    required this.displayName,
    this.photoFilePath,
  });

  @override
  List<Object?> get props => [displayName, photoFilePath];
}

/// User chose to skip profile modification for this session
/// (uses existing profile as-is).
class VideoChatProfileSkipped extends VideoChatLobbyEvent {
  const VideoChatProfileSkipped();
}

/// User wants to modify their existing profile (from the prompt screen).
class VideoChatProfileModifyRequested extends VideoChatLobbyEvent {
  const VideoChatProfileModifyRequested();
}

/// User wants to remove their current profile photo.
class VideoChatProfilePhotoRemoved extends VideoChatLobbyEvent {
  const VideoChatProfilePhotoRemoved();
}
