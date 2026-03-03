import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/video_match_service.dart';
import '../../domain/entities/video_chat_profile.dart';

part 'video_match_event.dart';
part 'video_match_state.dart';

/// BLoC managing the random-match search lifecycle.
///
/// 1. Joins the Firestore queue when [VideoMatchStarted] is dispatched.
/// 2. Immediately attempts to find a waiting partner ([tryMatch]).
/// 3. If no partner yet, retries every few seconds via a periodic timer.
/// 4. Simultaneously listens to its own queue document — if another user
///    matches *us* first, we get notified via the Firestore snapshot.
/// 5. Emits [VideoMatchFound] once a match exists (either we found them
///    or they found us).
class VideoMatchBloc extends Bloc<VideoMatchEvent, VideoMatchState> {
  final VideoMatchService _matchService;
  final Logger _logger;

  String _userId = '';
  String _displayName = '';
  String? _photoUrl;

  StreamSubscription? _queueSub;
  Timer? _retryTimer;
  Timer? _elapsedTimer;
  Duration _searchElapsed = Duration.zero;
  bool _matchResolved = false;

  VideoMatchBloc({
    required VideoMatchService matchService,
    Logger? logger,
  })  : _matchService = matchService,
        _logger = logger ?? Logger(),
        super(const VideoMatchIdle()) {
    on<VideoMatchStarted>(_onStarted);
    on<VideoMatchCancelled>(_onCancelled);
    on<_QueueDocChanged>(_onQueueDocChanged);
    on<_MatchRetryTick>(_onRetryTick);
    on<_SearchElapsedTick>(_onElapsedTick);
  }

  // ════════════════════════════════════════════════════════════════════
  //  Event Handlers
  // ════════════════════════════════════════════════════════════════════

  Future<void> _onStarted(
    VideoMatchStarted event,
    Emitter<VideoMatchState> emit,
  ) async {
    _matchResolved = false;
    _userId = event.profile.userId;
    _displayName = event.profile.displayName;
    _photoUrl = event.profile.photoUrl;
    _searchElapsed = Duration.zero;

    emit(const VideoMatchSearching());

    try {
      // Step 1: Join the queue.
      await _matchService.joinQueue(
        userId: _userId,
        displayName: _displayName,
        photoUrl: _photoUrl,
      );

      // Step 2: Listen to our own queue doc for changes
      // (in case someone else matches us).
      _queueSub?.cancel();
      _queueSub = _matchService.watchMyQueueDoc(_userId).listen(
        (data) => add(_QueueDocChanged(data: data)),
        onError: (e) => _logger.e('Queue watch error: $e'),
      );

      // Step 3: Try to find a match immediately.
      await _attemptMatch();

      // Step 4: Start a periodic retry every 3 seconds.
      _retryTimer?.cancel();
      _retryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_matchResolved) {
          add(const _MatchRetryTick());
        }
      });

      // Step 5: Tick the elapsed-time counter every second.
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_matchResolved) {
          _searchElapsed += const Duration(seconds: 1);
          add(const _SearchElapsedTick());
        }
      });
    } catch (e, st) {
      _logger.e('Failed to start matching', error: e, stackTrace: st);
      emit(VideoMatchError(message: 'Failed to start search: $e'));
    }
  }

  Future<void> _onCancelled(
    VideoMatchCancelled event,
    Emitter<VideoMatchState> emit,
  ) async {
    _matchResolved = true;
    _cancelTimers();
    _queueSub?.cancel();
    _queueSub = null;
    await _matchService.leaveQueue(_userId);
    emit(const VideoMatchIdle());
  }

  Future<void> _onQueueDocChanged(
    _QueueDocChanged event,
    Emitter<VideoMatchState> emit,
  ) async {
    if (_matchResolved) return;

    final data = event.data;
    if (data == null) {
      // Doc deleted — someone cleaned up.
      return;
    }

    if (data['status'] == 'matched') {
      final matchedUserId = data['matchedWith'] as String?;
      if (matchedUserId == null || matchedUserId.isEmpty) {
        _logger.w('Matched queue doc missing matchedWith for user $_userId');
        return;
      }

      _matchResolved = true;
      _cancelTimers();
      _queueSub?.cancel();
      _queueSub = null;

      final matchedName = data['matchedName'] as String? ?? 'Anonymous';
      final matchedPhotoUrl = data['matchedPhotoUrl'] as String?;
      final callRole = data['callRole'] as String? ?? 'caller';

      _logger.d('Match found! $matchedUserId ($matchedName), role: $callRole');

      emit(VideoMatchFound(
        matchedUserId: matchedUserId,
        matchedName: matchedName,
        matchedPhotoUrl: matchedPhotoUrl,
        callRole: callRole,
      ));

      // Clean up queue doc after match is consumed.
      _matchService.leaveQueue(_userId);
    }
  }

  Future<void> _onRetryTick(
    _MatchRetryTick event,
    Emitter<VideoMatchState> emit,
  ) async {
    if (_matchResolved) return;

    // Retry match attempt.
    await _attemptMatch();
  }

  void _onElapsedTick(
    _SearchElapsedTick event,
    Emitter<VideoMatchState> emit,
  ) {
    if (_matchResolved) return;
    emit(VideoMatchSearching(elapsed: _searchElapsed));
  }

  // ════════════════════════════════════════════════════════════════════
  //  Helpers
  // ════════════════════════════════════════════════════════════════════

  Future<void> _attemptMatch() async {
    if (_matchResolved) return;
    try {
      await _matchService.tryMatch(
        myUserId: _userId,
        myDisplayName: _displayName,
        myPhotoUrl: _photoUrl,
      );
      // Result is handled by the queue doc listener (_QueueDocChanged).
    } catch (e) {
      _logger.w('Match attempt error: $e');
    }
  }

  void _cancelTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  @override
  Future<void> close() async {
    _matchResolved = true;
    _cancelTimers();
    _queueSub?.cancel();
    // Best-effort leave queue on close.
    if (_userId.isNotEmpty) {
      _matchService.leaveQueue(_userId);
    }
    return super.close();
  }
}
