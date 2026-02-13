import 'dart:async';

import 'package:logger/logger.dart';

import '../../random_groups/domain/entities/random_group.dart';
import '../../random_groups/presentation/bloc/random_group_bloc.dart';
import 'random_group_chat_cache_service.dart';
import 'random_group_chat_service.dart';

/// Service responsible for preloading random group chat messages on app startup.
///
/// This implements WhatsApp-level instant group chat loading by:
/// 1. Waiting for the user's random groups to be loaded
/// 2. Selecting the most recent groups to preload
/// 3. Fetching messages in parallel without blocking UI
/// 4. Warming the in-memory cache before user navigates to any group chat
///
/// This eliminates the "No messages yet" flash when opening a random group chat
/// for the first time after app startup.
class RandomGroupChatPreloadService {
  final RandomGroupChatService _chatService;
  final RandomGroupChatCacheService _cacheService;
  final RandomGroupBloc _randomGroupBloc;
  final Logger _logger;

  /// Maximum number of group chats to preload
  static const int maxPreloadCount = 5;

  /// Number of messages to fetch per group
  static const int messagesPerGroup = 30;

  /// Tracks if preload is in progress
  bool _isPreloading = false;

  /// Tracks completed preloads for this session
  final Set<String> _preloadedGroups = {};

  RandomGroupChatPreloadService({
    required RandomGroupChatService chatService,
    required RandomGroupChatCacheService cacheService,
    required RandomGroupBloc randomGroupBloc,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _randomGroupBloc = randomGroupBloc,
        _logger = logger ?? Logger();

  /// Whether preloading is currently in progress.
  bool get isPreloading => _isPreloading;

  /// Groups that have been preloaded this session.
  Set<String> get preloadedGroups => Set.unmodifiable(_preloadedGroups);

  /// Preload random group chat messages on app startup.
  ///
  /// This method:
  /// 1. Waits for user random groups to be loaded
  /// 2. Selects the most recent groups to preload
  /// 3. Fetches messages in parallel
  /// 4. Stores them in the cache for instant display
  ///
  /// This is non-blocking and will not throw errors to the caller.
  Future<void> preloadOnStartup(String userId) async {
    if (_isPreloading) {
      _logger.d('Random group chat preload already in progress, skipping');
      return;
    }

    _isPreloading = true;
    _logger.i('Starting random group chat preload for user $userId');

    try {
      // Wait for groups to be loaded (with timeout)
      final groups = await _waitForGroups(
        timeout: const Duration(seconds: 10),
      );

      if (groups.isEmpty) {
        _logger.i('No random groups to preload');
        return;
      }

      // Select groups to preload (most recently active)
      final toPreload = _selectGroupsToPreload(groups);
      _logger.i('Selected ${toPreload.length} random groups to preload: '
          '${toPreload.map((g) => g.id.substring(0, 8)).join(", ")}');

      // Preload in parallel (with concurrency limit)
      await _preloadGroups(toPreload, userId);

      _logger.i(
          'Random group chat preload completed: ${_preloadedGroups.length} groups cached');
    } catch (e, stack) {
      _logger.e('Random group chat preload failed',
          error: e, stackTrace: stack);
      // Preload failures are silent - don't affect UX
    } finally {
      _isPreloading = false;
    }
  }

  /// Wait for random groups to be loaded from the bloc.
  Future<List<RandomGroup>> _waitForGroups({
    required Duration timeout,
  }) async {
    final completer = Completer<List<RandomGroup>>();
    StreamSubscription<RandomGroupState>? subscription;
    Timer? timer;

    // Guard: Check if bloc is closed before accessing
    if (_randomGroupBloc.isClosed) {
      _logger.w('RandomGroupBloc is closed, cannot wait for groups');
      return const [];
    }

    // Check current state first
    final currentState = _randomGroupBloc.state;
    if (currentState.status == RandomGroupBlocStatus.loaded &&
        currentState.userGroups.isNotEmpty) {
      return currentState.userGroups;
    }

    // Wait for groups to load
    subscription = _randomGroupBloc.stream.listen(
      (state) {
        if (state.status == RandomGroupBlocStatus.loaded) {
          if (!completer.isCompleted) {
            completer.complete(state.userGroups);
          }
          subscription?.cancel();
          timer?.cancel();
        } else if (state.status == RandomGroupBlocStatus.error) {
          if (!completer.isCompleted) {
            completer.complete(const []);
          }
          subscription?.cancel();
          timer?.cancel();
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          _logger.w('Stream error while waiting for random groups: $e');
          completer.complete(const []);
        }
        subscription?.cancel();
        timer?.cancel();
      },
      onDone: () {
        if (!completer.isCompleted) {
          _logger.w('Stream closed while waiting for random groups');
          completer.complete(const []);
        }
        timer?.cancel();
      },
    );

    // Timeout fallback
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _logger.w('Timed out waiting for random groups');
        completer.complete(currentState.userGroups);
      }
      subscription?.cancel();
    });

    return completer.future;
  }

  /// Select which groups to preload based on recency.
  List<RandomGroup> _selectGroupsToPreload(List<RandomGroup> groups) {
    // Sort by most recent activity
    final sorted = groups.toList()
      ..sort((a, b) {
        final aTime = a.lastMessageAt ?? a.lastActiveAt;
        final bTime = b.lastMessageAt ?? b.lastActiveAt;
        return bTime.compareTo(aTime);
      });

    // Return top N groups
    return sorted.take(maxPreloadCount).toList();
  }

  /// Preload messages for selected groups.
  Future<void> _preloadGroups(
      List<RandomGroup> groups, String userId) async {
    // Preload in parallel with concurrency limit
    const maxConcurrency = 3;
    final chunks = <List<RandomGroup>>[];

    for (var i = 0; i < groups.length; i += maxConcurrency) {
      chunks.add(groups.sublist(
        i,
        i + maxConcurrency > groups.length ? groups.length : i + maxConcurrency,
      ));
    }

    for (final chunk in chunks) {
      await Future.wait(
        chunk.map((g) => _preloadSingleGroup(g.id, userId)),
        eagerError: false, // Continue even if some fail
      );
    }
  }

  /// Preload a single group's messages.
  Future<void> _preloadSingleGroup(String groupId, String userId) async {
    // Skip if already cached with valid TTL
    if (_cacheService.hasValidCache(
      groupId,
      ttl: RandomGroupChatCacheService.defaultTtl,
    )) {
      _logger.d('Skipping preload for random group $groupId: already cached');
      _preloadedGroups.add(groupId);
      return;
    }

    try {
      final messages = await _chatService.getMessages(
        groupId: groupId,
        limit: messagesPerGroup,
      );

      if (messages.isNotEmpty) {
        _cacheService.updateCache(
          groupId: groupId,
          messages: messages,
          hasMore: messages.length >= messagesPerGroup,
          isPreload: true,
        );
        _preloadedGroups.add(groupId);
        _logger.d(
            'Preloaded ${messages.length} messages for random group $groupId');
      }
    } catch (e) {
      _logger.d('Failed to preload random group $groupId: $e');
      // Individual failures don't stop other preloads
    }
  }

  /// Clear preload tracking (e.g., on logout).
  void clear() {
    _preloadedGroups.clear();
    _isPreloading = false;
  }
}
