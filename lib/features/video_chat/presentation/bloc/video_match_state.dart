part of 'video_match_bloc.dart';

/// States for the Video Match BLoC.
sealed class VideoMatchState extends Equatable {
  const VideoMatchState();

  @override
  List<Object?> get props => [];
}

/// Idle — not searching.
class VideoMatchIdle extends VideoMatchState {
  const VideoMatchIdle();
}

/// Actively searching for a partner.
class VideoMatchSearching extends VideoMatchState {
  final Duration elapsed;

  const VideoMatchSearching({this.elapsed = Duration.zero});

  @override
  List<Object?> get props => [elapsed];
}

/// A match was found.
class VideoMatchFound extends VideoMatchState {
  /// The matched user's ID.
  final String matchedUserId;

  /// The matched user's display name.
  final String matchedName;

  /// The matched user's photo URL.
  final String? matchedPhotoUrl;

  /// Whether this user should create the WebRTC offer ('caller')
  /// or wait for the offer ('receiver').
  final String callRole;

  const VideoMatchFound({
    required this.matchedUserId,
    required this.matchedName,
    this.matchedPhotoUrl,
    required this.callRole,
  });

  @override
  List<Object?> get props => [matchedUserId, matchedName, callRole];
}

/// An error occurred during matching.
class VideoMatchError extends VideoMatchState {
  final String message;

  const VideoMatchError({required this.message});

  @override
  List<Object?> get props => [message];
}
