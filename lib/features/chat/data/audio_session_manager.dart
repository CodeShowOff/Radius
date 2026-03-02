import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:logger/logger.dart';

/// Global audio session manager — ensures only one audio plays at a time.
///
/// Inspired by v_chat_sdk's centralized audio management approach.
/// Instead of each `_AudioContent` widget creating its own `AudioPlayer`,
/// this singleton manages a shared player and tracks the currently-playing
/// message to pause previous playback when a new one starts.
///
/// Usage:
/// ```dart
/// final manager = AudioSessionManager();
/// // Start playing (auto-stops any current playback)
/// await manager.play(messageId: 'msg_1', url: 'https://...');
/// // Pause
/// await manager.pause();
/// // Listen for events
/// manager.playerStateStream.listen((state) { ... });
/// ```
class AudioSessionManager {
  final Logger _logger;

  AudioPlayer? _player;
  String? _currentMessageId;

  /// Stream controllers for broadcasting state to widgets.
  final _stateController = StreamController<AudioSessionState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  AudioSessionManager({Logger? logger}) : _logger = logger ?? Logger();

  /// The message currently being played (null if nothing playing).
  String? get currentMessageId => _currentMessageId;

  /// Whether audio is currently playing.
  bool get isPlaying => _currentMessageId != null && _lastState == PlayerState.playing;

  PlayerState? _lastState;

  /// Stream of player state changes tagged with the message ID.
  Stream<AudioSessionState> get playerStateStream => _stateController.stream;

  /// Stream of position updates.
  Stream<Duration> get positionStream => _positionController.stream;

  /// Stream of duration updates.
  Stream<Duration> get durationStream => _durationController.stream;

  /// Play audio for a specific message. Stops any currently-playing audio first.
  Future<void> play({required String messageId, required String url}) async {
    try {
      // If same message, just resume
      if (_currentMessageId == messageId && _lastState == PlayerState.paused) {
        await _player?.resume();
        return;
      }

      // Stop current playback
      await _stopCurrent();

      // Create fresh player
      _player = AudioPlayer();
      _currentMessageId = messageId;
      _setupListeners();

      await _player!.play(UrlSource(url));
      _logger.d('Playing audio for message: $messageId');
    } catch (e) {
      _logger.e('Failed to play audio: $e');
      _stateController.add(AudioSessionState(
        messageId: messageId,
        state: PlayerState.stopped,
      ));
      _currentMessageId = null;
    }
  }

  /// Pause current playback.
  Future<void> pause() async {
    try {
      await _player?.pause();
    } catch (e) {
      _logger.e('Failed to pause audio: $e');
    }
  }

  /// Resume current playback.
  Future<void> resume() async {
    try {
      await _player?.resume();
    } catch (e) {
      _logger.e('Failed to resume audio: $e');
    }
  }

  /// Stop and release current playback.
  Future<void> stop() async {
    await _stopCurrent();
  }

  /// Seek to position.
  Future<void> seek(Duration position) async {
    try {
      await _player?.seek(position);
    } catch (e) {
      _logger.e('Failed to seek audio: $e');
    }
  }

  /// Stop current player and clear state.
  Future<void> _stopCurrent() async {
    final previousId = _currentMessageId;
    _cancelListeners();

    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}

    _player = null;
    _lastState = null;

    if (previousId != null) {
      _stateController.add(AudioSessionState(
        messageId: previousId,
        state: PlayerState.stopped,
      ));
      _currentMessageId = null;
    }
  }

  void _setupListeners() {
    _playerStateSub = _player?.onPlayerStateChanged.listen((state) {
      _lastState = state;
      if (_currentMessageId != null) {
        _stateController.add(AudioSessionState(
          messageId: _currentMessageId!,
          state: state,
        ));
      }

      // Auto-cleanup when playback completes
      if (state == PlayerState.completed) {
        _currentMessageId = null;
        _lastState = null;
      }
    });

    _positionSub = _player?.onPositionChanged.listen((position) {
      _positionController.add(position);
    });

    _durationSub = _player?.onDurationChanged.listen((duration) {
      _durationController.add(duration);
    });
  }

  void _cancelListeners() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub = null;
    _positionSub = null;
    _durationSub = null;
  }

  /// Dispose the manager — call on app shutdown.
  Future<void> dispose() async {
    await _stopCurrent();
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

/// A snapshot of the audio session state for a specific message.
class AudioSessionState {
  final String messageId;
  final PlayerState state;

  const AudioSessionState({
    required this.messageId,
    required this.state,
  });

  bool get isPlaying => state == PlayerState.playing;
  bool get isPaused => state == PlayerState.paused;
  bool get isStopped =>
      state == PlayerState.stopped || state == PlayerState.completed;
}
