part of 'video_chat_lobby_bloc.dart';

/// States for the Video Chat Lobby BLoC.
sealed class VideoChatLobbyState extends Equatable {
  const VideoChatLobbyState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any loading has occurred.
class VideoChatLobbyInitial extends VideoChatLobbyState {
  const VideoChatLobbyInitial();
}

/// Loading profile and settings from Firestore/Hive.
class VideoChatLobbyLoading extends VideoChatLobbyState {
  const VideoChatLobbyLoading();
}

/// The user must confirm they are 18+ before proceeding.
class VideoChatLobbyAgeGate extends VideoChatLobbyState {
  const VideoChatLobbyAgeGate();
}

/// Show the headphones advisory dialog.
class VideoChatLobbyHeadphonesAdvisory extends VideoChatLobbyState {
  const VideoChatLobbyHeadphonesAdvisory();
}

/// Profile setup screen — shown for new users (no saved profile)
/// or returning users who want to modify their profile.
class VideoChatLobbyProfileSetup extends VideoChatLobbyState {
  /// The existing profile, if any. Null for first-time users.
  final VideoChatProfile? existingProfile;

  /// Whether this is a first-time setup (true) or modification (false).
  final bool isFirstTime;

  const VideoChatLobbyProfileSetup({
    this.existingProfile,
    required this.isFirstTime,
  });

  @override
  List<Object?> get props => [existingProfile, isFirstTime];
}

/// Ask returning users if they want to modify their profile.
class VideoChatLobbyProfilePrompt extends VideoChatLobbyState {
  final VideoChatProfile existingProfile;

  const VideoChatLobbyProfilePrompt({required this.existingProfile});

  @override
  List<Object?> get props => [existingProfile];
}

/// Profile is being saved (uploading photo, writing to Firestore).
class VideoChatLobbySavingProfile extends VideoChatLobbyState {
  const VideoChatLobbySavingProfile();
}

/// All gates passed, profile is ready — user can enter the matching lobby.
class VideoChatLobbyReady extends VideoChatLobbyState {
  final VideoChatProfile profile;

  const VideoChatLobbyReady({required this.profile});

  @override
  List<Object?> get props => [profile];
}

/// An error occurred during the lobby flow.
class VideoChatLobbyError extends VideoChatLobbyState {
  final String message;

  const VideoChatLobbyError({required this.message});

  @override
  List<Object?> get props => [message];
}
