part of 'video_match_bloc.dart';

/// Events for the Video Match BLoC.
sealed class VideoMatchEvent extends Equatable {
  const VideoMatchEvent();

  @override
  List<Object?> get props => [];
}

/// Start searching for a random match.
class VideoMatchStarted extends VideoMatchEvent {
  final VideoChatProfile profile;

  const VideoMatchStarted({required this.profile});

  @override
  List<Object?> get props => [profile];
}

/// Cancel the current search.
class VideoMatchCancelled extends VideoMatchEvent {
  const VideoMatchCancelled();
}

/// Internal: queue document changed (from Firestore listener).
class _QueueDocChanged extends VideoMatchEvent {
  final Map<String, dynamic>? data;

  const _QueueDocChanged({this.data});

  @override
  List<Object?> get props => [data];
}

/// Internal: periodic retry to find a match.
class _MatchRetryTick extends VideoMatchEvent {
  const _MatchRetryTick();
}

/// Internal: elapsed time tick (every second) to update the UI timer.
class _SearchElapsedTick extends VideoMatchEvent {
  const _SearchElapsedTick();
}
