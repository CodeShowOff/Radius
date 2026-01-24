import 'dart:async';

import 'package:logger/logger.dart';

import '../domain/entities/conversation.dart';
import '../presentation/bloc/conversations_bloc.dart';
import 'chat_cache_service.dart';
import 'chat_service.dart';

/// Service responsible for preloading chat messages on app startup.
///
/// This implements WhatsApp-level instant chat loading by:
/// 1. Selecting the most important chats to preload (recent conversations)
/// 2. Fetching messages in parallel without blocking UI
/// 3. Warming the in-memory cache before user navigates to any chat
///
/// Preloading rules:
/// - Top 3-5 most recent conversations (by lastMessageAt)
/// - Capped at 5 total to limit memory and network usage
/// - One-time fetch (no subscriptions)
/// - Does NOT mark messages as read
class ChatPreloadService {
  final ChatService _chatService;
  final ChatCacheService _cacheService;
  final ConversationsBloc _conversationsBloc;
  final Logger _logger;

  /// Maximum number of chats to preload
  static const int maxPreloadCount = 5;

  /// Number of messages to fetch per chat
  static const int messagesPerChat = 30;

  /// Tracks if preload is in progress
  bool _isPreloading = false;

  /// Tracks completed preloads for this session
  final Set<String> _preloadedConversations = {};

  ChatPreloadService({
    required ChatService chatService,
    required ChatCacheService cacheService,
    required ConversationsBloc conversationsBloc,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _conversationsBloc = conversationsBloc,
        _logger = logger ?? Logger();

  /// Whether preloading is currently in progress.
  bool get isPreloading => _isPreloading;

  /// Conversations that have been preloaded this session.
  Set<String> get preloadedConversations => Set.unmodifiable(_preloadedConversations);

  /// Preload chat messages on app startup.
  ///
  /// This method:
  /// 1. Waits for conversations to be loaded
  /// 2. Selects the most important chats to preload
  /// 3. Fetches messages in parallel
  /// 4. Stores them in the cache for instant display
  ///
  /// This is non-blocking and will not throw errors to the caller.
  Future<void> preloadOnStartup(String userId) async {
    if (_isPreloading) {
      _logger.d('Preload already in progress, skipping');
      return;
    }

    _isPreloading = true;
    _logger.i('Starting chat preload for user $userId');

    try {
      // Wait for conversations to be loaded (with timeout)
      final conversations = await _waitForConversations(
        timeout: const Duration(seconds: 10),
      );

      if (conversations.isEmpty) {
        _logger.i('No conversations to preload');
        return;
      }

      // Select chats to preload
      final toPreload = _selectConversationsToPreload(conversations, userId);
      _logger.i('Selected ${toPreload.length} conversations to preload: '
          '${toPreload.map((c) => c.id.substring(0, 8)).join(", ")}');

      // Preload in parallel (but limit concurrency)
      await _preloadConversations(toPreload);

      _logger.i('Chat preload completed: ${_preloadedConversations.length} chats cached');
    } catch (e, stack) {
      _logger.e('Chat preload failed', error: e, stackTrace: stack);
      // Preload failures are silent - don't affect UX
    } finally {
      _isPreloading = false;
    }
  }

  /// Wait for conversations to be loaded from the bloc.
  Future<List<Conversation>> _waitForConversations({
    required Duration timeout,
  }) async {
    final completer = Completer<List<Conversation>>();
    StreamSubscription<ConversationsState>? subscription;
    Timer? timer;

    // Guard: Check if bloc is closed before accessing
    if (_conversationsBloc.isClosed) {
      _logger.w('ConversationsBloc is closed, cannot wait for conversations');
      return const [];
    }

    // Check current state first
    final currentState = _conversationsBloc.state;
    if (currentState.status == ConversationsStatus.success &&
        currentState.conversations.isNotEmpty) {
      return currentState.conversations;
    }

    // Wait for conversations to load
    subscription = _conversationsBloc.stream.listen(
      (state) {
        if (state.status == ConversationsStatus.success) {
          if (!completer.isCompleted) {
            completer.complete(state.conversations);
          }
          subscription?.cancel();
          timer?.cancel();
        } else if (state.status == ConversationsStatus.error) {
          if (!completer.isCompleted) {
            completer.complete(const []);
          }
          subscription?.cancel();
          timer?.cancel();
        }
      },
      onError: (e) {
        // Guard: Handle stream errors (e.g., bloc closed)
        if (!completer.isCompleted) {
          _logger.w('Stream error while waiting for conversations: $e');
          completer.complete(const []);
        }
        subscription?.cancel();
        timer?.cancel();
      },
      onDone: () {
        // Guard: Handle stream closed (bloc disposed)
        if (!completer.isCompleted) {
          _logger.w('Stream closed while waiting for conversations');
          completer.complete(const []);
        }
        timer?.cancel();
      },
    );

    // Timeout fallback
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _logger.w('Timed out waiting for conversations');
        completer.complete(currentState.conversations);
      }
      subscription?.cancel();
    });

    return completer.future;
  }

  /// Select which conversations to preload based on priority.
  ///
  /// Priority order:
  /// 1. Most recent conversations (sorted by lastMessageAt)
  /// 2. Capped at [maxPreloadCount]
  List<Conversation> _selectConversationsToPreload(
    List<Conversation> conversations,
    String userId,
  ) {
    // Sort by most recent activity
    final sorted = conversations.toList()
      ..sort((a, b) => (b.lastMessageAt ?? DateTime(0))
          .compareTo(a.lastMessageAt ?? DateTime(0)));

    // Return top N conversations
    return sorted.take(maxPreloadCount).toList();
  }

  /// Preload messages for selected conversations.
  Future<void> _preloadConversations(List<Conversation> conversations) async {
    // Preload in parallel with concurrency limit
    const maxConcurrency = 3;
    final chunks = <List<Conversation>>[];

    for (var i = 0; i < conversations.length; i += maxConcurrency) {
      chunks.add(conversations.sublist(
        i,
        i + maxConcurrency > conversations.length
            ? conversations.length
            : i + maxConcurrency,
      ));
    }

    for (final chunk in chunks) {
      await Future.wait(
        chunk.map((c) => _preloadSingleConversation(c.id)),
        eagerError: false, // Continue even if some fail
      );
    }
  }

  /// Preload a single conversation's messages.
  Future<void> _preloadSingleConversation(String conversationId) async {
    // Skip if already cached with valid TTL
    if (_cacheService.hasValidCache(
      conversationId,
      ttl: ChatCacheService.defaultTtl,
    )) {
      _logger.d('Skipping preload for $conversationId: already cached');
      _preloadedConversations.add(conversationId);
      return;
    }

    try {
      final messages = await _chatService.getMessagesOnce(
        conversationId,
        limit: messagesPerChat,
      );

      if (messages.isNotEmpty) {
        _cacheService.updateCache(
          conversationId: conversationId,
          messages: messages,
          hasMore: messages.length >= messagesPerChat,
          isPreload: true,
        );
        _preloadedConversations.add(conversationId);
        _logger.d('Preloaded ${messages.length} messages for $conversationId');
      }
    } catch (e) {
      _logger.d('Failed to preload $conversationId: $e');
      // Individual failures don't stop other preloads
    }
  }

  /// Preload a specific conversation (e.g., on long-press).
  /// Returns true if preload was successful.
  Future<bool> preloadConversation(String conversationId) async {
    if (_cacheService.hasCache(conversationId)) {
      return true; // Already cached
    }

    try {
      await _preloadSingleConversation(conversationId);
      return _cacheService.hasCache(conversationId);
    } catch (e) {
      return false;
    }
  }

  /// Clear preload tracking (e.g., on logout).
  void clear() {
    _preloadedConversations.clear();
    _isPreloading = false;
  }
}
