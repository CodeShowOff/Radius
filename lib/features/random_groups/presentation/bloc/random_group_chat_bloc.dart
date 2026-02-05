import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../data/random_group_chat_cache_service.dart';
import '../../data/random_group_chat_service.dart';
import '../../domain/entities/random_group_message.dart';

part 'random_group_chat_event.dart';
part 'random_group_chat_state.dart';

const _uuid = Uuid();

/// BLoC for managing random group chat messages with strict membership access control.
///
/// ## Security Model
///
/// This BLoC enforces a **membership-gated access control** model:
///
/// 1. **Membership verification is MANDATORY** before any content is shown.
///    The `membershipVerified` flag in [RandomGroupChatState] gates ALL access.
///
/// 2. **No cached content before verification**: Unlike typical instant-load
///    patterns, we DO NOT show cached messages until membership is confirmed.
///    This prevents privacy leaks from stale cache or URL manipulation.
///
/// 3. **Defense in depth**: This client-side check complements Firestore
///    security rules that also enforce membership for read/write.
///
/// ## Access Flow
///
/// 1. [OpenRandomGroupChat] → Start loading, `membershipVerified = false`
/// 2. Check `isActiveMember()` → If false, show error and block access
/// 3. If member, set `membershipVerified = true` → NOW show cached/streamed messages
/// 4. [SendRandomGroupMessage] → Blocked if `membershipVerified == false`
class RandomGroupChatBloc
    extends Bloc<RandomGroupChatEvent, RandomGroupChatState> {
  final RandomGroupChatService _chatService;
  final RandomGroupChatCacheService _cacheService;
  final Logger _logger;

  StreamSubscription<List<RandomGroupMessage>>? _messagesSubscription;

  /// CRITICAL: Track if subscriptions are actually active.
  /// This prevents the bug where state.status == loaded but subscriptions are null.
  bool _hasActiveSubscriptions = false;

  /// Cache for verified memberships: Map<"userId:groupId", DateTime>
  /// This prevents repeated Firestore calls when navigating between groups.
  /// TTL: 5 minutes - balances performance with security (catching removals).
  static final Map<String, DateTime> _membershipCache = {};
  static const Duration _membershipCacheTtl = Duration(minutes: 5);

  RandomGroupChatBloc({
    required RandomGroupChatService chatService,
    required RandomGroupChatCacheService cacheService,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _logger = logger ?? Logger(),
        super(const RandomGroupChatState()) {
    on<OpenRandomGroupChat>(_onOpenRandomGroupChat);
    on<CloseRandomGroupChat>(_onCloseRandomGroupChat);
    on<SendRandomGroupMessage>(_onSendRandomGroupMessage);
    on<LoadMoreRandomGroupMessages>(_onLoadMoreRandomGroupMessages);
    on<ResyncRandomGroupChat>(_onResyncRandomGroupChat);
    on<PreloadRandomGroupChat>(_onPreloadRandomGroupChat);
    on<_MessagesReceived>(_onMessagesReceived);
    on<_ChatStreamError>(_onChatStreamError);
    on<DeleteRandomGroupMessage>(_onDeleteRandomGroupMessage);
  }

  /// Check if membership is cached and still valid.
  bool _isMembershipCached(String userId, String groupId) {
    final key = '$userId:$groupId';
    final cachedAt = _membershipCache[key];
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < _membershipCacheTtl;
  }

  /// Cache a verified membership.
  void _cacheMembership(String userId, String groupId) {
    final key = '$userId:$groupId';
    _membershipCache[key] = DateTime.now();
    _logger.d('Cached membership for $key');
  }

  /// Invalidate membership cache for a user/group (e.g., on error or removal).
  void _invalidateMembershipCache(String userId, String groupId) {
    final key = '$userId:$groupId';
    _membershipCache.remove(key);
    _logger.d('Invalidated membership cache for $key');
  }

  /// Whether the bloc has active Firestore subscriptions.
  /// Used by UI to determine if resync is needed on app resume.
  bool get hasActiveSubscriptions => _hasActiveSubscriptions;

  Future<void> _onOpenRandomGroupChat(
    OpenRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    _logger.d('Opening random group chat: ${event.groupId}');

    // ========================================================================
    // CRITICAL FIX: Check BOTH state AND actual subscription status.
    // Previously, this only checked state.status which could be 'loaded' even
    // when subscriptions were cancelled by CloseRandomGroupChat. This caused messages
    // sent while user was away to never be received.
    // ========================================================================
    final bool isSameGroup = state.currentGroupId == event.groupId &&
        state.currentUserId == event.userId;
    final bool isAlreadyLoaded = state.status == RandomGroupChatStatus.loaded ||
        state.status == RandomGroupChatStatus.sending;
    final bool isMembershipVerified = state.membershipVerified;

    // OPTIMIZATION: Only skip full reload if we have ACTIVE subscriptions AND verified membership
    if (isSameGroup &&
        isAlreadyLoaded &&
        _hasActiveSubscriptions &&
        isMembershipVerified) {
      _logger.i(
          'Random group chat already loaded with active streams for ${event.groupId}, skipping reload');

      // Just update user info if changed (photo/name updates)
      if (state.currentUserName != event.userName ||
          state.currentUserPhotoUrl != event.userPhotoUrl) {
        emit(state.copyWith(
          currentUserName: event.userName,
          currentUserPhotoUrl: event.userPhotoUrl,
        ));
      }

      return;
    }

    // CRITICAL: If same group but no active subscriptions, we need to resubscribe!
    // This happens when user left and returned to the same chat.
    if (isSameGroup &&
        isAlreadyLoaded &&
        !_hasActiveSubscriptions &&
        isMembershipVerified) {
      _logger.i(
          'Same group ${event.groupId} but subscriptions inactive, resubscribing...');
      // Don't reset state - keep cached messages visible, just resubscribe
      await _subscribeToMessages(event.groupId);
      return;
    }

    // Cancel any existing subscription
    await _cancelSubscriptions();

    // ========================================================================
    // CRITICAL SECURITY FIX: Verify membership BEFORE showing ANY content
    // Do NOT show cached messages until membership is confirmed.
    // This prevents privacy leaks from stale cache or URL manipulation.
    // ========================================================================

    // Check if we have a cached membership verification (optimization)
    final hasCachedMembership =
        _isMembershipCached(event.userId, event.groupId);
    final cachedMessages = _cacheService.getMessages(event.groupId);
    final hasCache = cachedMessages.isNotEmpty;

    if (hasCachedMembership && hasCache) {
      // FAST PATH: Membership was recently verified, show cached messages immediately
      _logger.i(
          'Using cached membership for ${event.groupId} - skipping Firestore check');
      final cachedEntry = _cacheService.getCache(event.groupId);

      emit(state.copyWith(
        status: RandomGroupChatStatus.loaded,
        currentGroupId: event.groupId,
        currentUserId: event.userId,
        currentUserUsername: event.username,
        currentUserName: event.userName,
        currentUserPhotoUrl: event.userPhotoUrl,
        messages: cachedMessages,
        hasMore: cachedEntry?.hasMore ?? true,
        clearError: true,
        membershipVerified: true,
      ));

      // Start listening to messages (already verified)
      await _subscribeToMessages(event.groupId);
      return;
    }

    // Always start with loading state and unverified membership
    emit(state.copyWith(
      status: RandomGroupChatStatus.loading,
      currentGroupId: event.groupId,
      currentUserId: event.userId,
      currentUserUsername: event.username,
      currentUserName: event.userName,
      currentUserPhotoUrl: event.userPhotoUrl,
      messages: const [], // SECURITY: Don't show cached messages until verified
      hasMore: true,
      clearError: true,
      membershipVerified: false, // CRITICAL: Block access until verified
    ));

    try {
      // ======================================================================
      // STEP 1: Verify membership FIRST (security gate)
      // ======================================================================
      final canRead = await _chatService.isActiveMember(
        groupId: event.groupId,
        userId: event.userId,
      );

      if (!canRead) {
        _logger.w(
            'Access denied: User ${event.userId} is not a member of random group ${event.groupId}');
        // Invalidate any cached membership
        _invalidateMembershipCache(event.userId, event.groupId);
        // Clear any cached messages for this group to prevent stale data display
        _cacheService.clearCache(event.groupId);
        emit(state.copyWith(
          status: RandomGroupChatStatus.error,
          errorMessage: 'You are not a member of this group.',
          membershipVerified: false,
          messages: const [],
        ));
        return;
      }

      // ======================================================================
      // STEP 2: Membership verified - cache it and show messages
      // ======================================================================
      _cacheMembership(event.userId, event.groupId);
      _logger.i(
          'Membership verified for user ${event.userId} in random group ${event.groupId}');

      final cachedMessagesAfterVerify =
          _cacheService.getMessages(event.groupId);
      final hasCacheAfterVerify = cachedMessagesAfterVerify.isNotEmpty;
      final cachedEntryAfterVerify = _cacheService.getCache(event.groupId);

      if (hasCacheAfterVerify) {
        // Show cached messages now that membership is confirmed
        _logger.i(
            'Cache hit for random group ${event.groupId}: ${cachedMessagesAfterVerify.length} messages');
        emit(state.copyWith(
          status: RandomGroupChatStatus.loaded,
          messages: cachedMessagesAfterVerify,
          hasMore: cachedEntryAfterVerify?.hasMore ?? true,
          membershipVerified: true, // CRITICAL: Enable access
        ));
      } else {
        // No cache - mark as verified but keep loading for stream
        emit(state.copyWith(
          membershipVerified: true,
        ));
      }

      // ======================================================================
      // STEP 3: Start listening to messages (membership already verified)
      // ======================================================================
      await _subscribeToMessages(event.groupId);

      // Mark group as read after a brief delay to ensure messages are loaded
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!isClosed && state.currentGroupId == event.groupId) {
          _chatService.markGroupAsRead(
            groupId: event.groupId,
            userId: event.userId,
          );
          _logger.d('Marked random group as read: ${event.groupId}');
        }
      });
    } catch (e, stack) {
      _logger.e('Error opening random group chat', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: RandomGroupChatStatus.error,
        errorMessage: 'Failed to load messages',
        membershipVerified: false,
      ));
      // Invalidate membership cache on error
      _invalidateMembershipCache(event.userId, event.groupId);
    }
  }

  Future<void> _onChatStreamError(
    _ChatStreamError event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    await _cancelSubscriptions();

    // Invalidate membership cache when stream errors (likely permission denied)
    if (state.currentUserId != null && state.currentGroupId != null) {
      _invalidateMembershipCache(state.currentUserId!, state.currentGroupId!);
    }

    // SECURITY: On access error, revoke membership verification
    // This handles the case where user was removed while viewing chat
    emit(state.copyWith(
      status: RandomGroupChatStatus.error,
      errorMessage: event.message,
      messages: const [],
      hasMore: false,
      membershipVerified: false, // Revoke access on error
    ));
  }

  Future<void> _onCloseRandomGroupChat(
    CloseRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    _logger.d('Closing random group chat');
    await _cancelSubscriptions();

    // Preserve messages for instant display on revisit
    // Only clear the subscription, not the cached data
    emit(state.copyWith(clearError: true));
  }

  Future<void> _onSendRandomGroupMessage(
    SendRandomGroupMessage event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    if (state.currentGroupId == null || state.currentUserId == null) {
      _logger.w('Cannot send message: chat not open');
      return;
    }

    // SECURITY: Verify membership is confirmed before allowing send
    if (!state.membershipVerified) {
      _logger.w('Cannot send message: membership not verified');
      emit(state.copyWith(
        status: RandomGroupChatStatus.error,
        errorMessage: 'You must be a member to send messages.',
      ));
      return;
    }

    final text = event.text.trim();
    if (text.isEmpty) return;

    _logger.d(
        'Sending message: ${text.substring(0, text.length.clamp(0, 20))}...');

    // ========================================================================
    // OPTIMISTIC UPDATE: Show message immediately in UI for instant feedback
    // This creates a WhatsApp-like experience where your message appears
    // instantly, then gets confirmed when the server responds.
    // ========================================================================
    final localId = _uuid.v4();
    final optimisticMessage = RandomGroupMessage(
      id: localId, // Temporary ID until server assigns real one
      groupId: state.currentGroupId!,
      senderId: state.currentUserId!,
      senderUsername: state.currentUserUsername,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: text,
      type: RandomGroupMessageType.text,
      sentAt: DateTime.now(),
    );

    // Add optimistic message to the front of the list
    final updatedMessages = [optimisticMessage, ...state.messages];
    emit(state.copyWith(
      status: RandomGroupChatStatus.sending,
      messages: updatedMessages,
    ));

    try {
      await _chatService.sendMessage(
        groupId: state.currentGroupId!,
        senderId: state.currentUserId!,
        senderUsername: state.currentUserUsername ?? 'Unknown',
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: text,
      );

      // Success: The Firestore stream will automatically update with the real
      // message (with server-assigned ID). The optimistic message will be
      // replaced when _onMessagesReceived merges the new data.
      emit(state.copyWith(status: RandomGroupChatStatus.loaded));
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);

      // Remove the failed optimistic message and show error
      final messagesWithoutFailed =
          state.messages.where((m) => m.id != localId).toList();

      // Provide helpful error messages based on error type
      String errorMessage = 'Failed to send message. Please try again.';
      if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          errorMessage =
              'Unable to send message. This may happen if you just joined. Please wait a moment and try again.';
        } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          errorMessage =
              'Network error. Please check your connection and try again.';
        }
      }

      emit(state.copyWith(
        status: RandomGroupChatStatus.error,
        errorMessage: errorMessage,
        messages: messagesWithoutFailed,
      ));
    }
  }

  Future<void> _onLoadMoreRandomGroupMessages(
    LoadMoreRandomGroupMessages event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    if (state.currentGroupId == null || !state.hasMore || state.isLoading) {
      return;
    }

    if (state.messages.isEmpty) return;

    _logger.d('Loading more messages');

    emit(state.copyWith(isLoadingMore: true));

    final oldestMessage = state.messages.last;

    try {
      final olderMessages = await _chatService.loadMoreMessages(
        groupId: state.currentGroupId!,
        beforeTimestamp: oldestMessage.sentAt,
        limit: 30,
      );

      final hasMore = olderMessages.length >= 30;

      // Deduplicate: ensure no overlap with existing messages
      final existingIds = state.messages.map((m) => m.id).toSet();
      final uniqueOlderMessages =
          olderMessages.where((m) => !existingIds.contains(m.id)).toList();

      final allMessages = [...state.messages, ...uniqueOlderMessages];

      // Update the cache with paginated messages
      _cacheService.addPaginatedMessages(
        groupId: state.currentGroupId!,
        olderMessages: olderMessages,
        hasMore: hasMore,
      );

      emit(state.copyWith(
        messages: allMessages,
        hasMore: hasMore,
        isLoadingMore: false,
      ));
    } catch (e, stack) {
      _logger.e('Error loading more messages', error: e, stackTrace: stack);
      // Don't show error for pagination, just stop loading more
      emit(state.copyWith(hasMore: false, isLoadingMore: false));
    }
  }

  void _onMessagesReceived(
    _MessagesReceived event,
    Emitter<RandomGroupChatState> emit,
  ) {
    _logger.d('Received ${event.messages.length} messages');

    const pageSize = 50;

    // CRITICAL FIX: Deduplicate messages by ID to prevent double display
    // Create a Set of IDs from newly received messages for O(1) lookup
    final newMessageIds = event.messages.map((m) => m.id).toSet();

    // Filter out optimistic messages (those with local/temporary IDs that start with UUID pattern)
    // and messages that are duplicates of the incoming batch
    final currentOldMessages = state.messages.where((m) {
      // Skip if message is already in the new batch (prevents duplicates)
      if (newMessageIds.contains(m.id)) return false;

      // Filter out optimistic messages with temporary IDs (UUIDs)
      // Real Firestore IDs are typically 20 characters, UUIDs are 36
      // Check if this is an optimistic message that might have been replaced by a real one
      if (m.id.length == 36 && m.id.contains('-')) {
        // This looks like a temporary UUID - check if there's a matching real message
        final hasMatchingRealMessage = event.messages.any((newMsg) =>
            newMsg.senderId == m.senderId &&
            newMsg.text == m.text &&
            newMsg.sentAt.difference(m.sentAt).inSeconds.abs() < 5);

        if (hasMatchingRealMessage) {
          _logger.d(
              'Filtering out optimistic message ${m.id} as it has a matching real message');
          return false; // Filter out the optimistic message
        }
      }

      // Keep messages that are older than the oldest message in the new list
      if (event.messages.isEmpty) return true;
      return m.sentAt.isBefore(event.messages.last.sentAt);
    }).toList();

    final allMessages = [...event.messages, ...currentOldMessages];
    final hasMore = event.messages.length >= pageSize;

    // ========================================================================
    // CRITICAL: Update the global cache with new messages
    // This enables instant display when returning to this group later
    // ========================================================================
    if (state.currentGroupId != null) {
      _cacheService.updateCache(
        groupId: state.currentGroupId!,
        messages: allMessages,
        hasMore: hasMore,
      );
    }

    // Always set status to loaded when we receive messages to clear loading state
    emit(state.copyWith(
      status: RandomGroupChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
      isLoadingMore: false,
    ));

    if (state.currentGroupId != null && state.currentUserId != null) {
      unawaited(_chatService.markGroupAsRead(
        groupId: state.currentGroupId!,
        userId: state.currentUserId!,
      ));
    }
  }

  Future<void> _onDeleteRandomGroupMessage(
    DeleteRandomGroupMessage event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    if (state.currentGroupId == null || state.currentUserId == null) return;

    _logger.d('Deleting message: ${event.messageId}');

    try {
      await _chatService.deleteMessage(
        groupId: state.currentGroupId!,
        messageId: event.messageId,
        userId: state.currentUserId!,
      );
    } catch (e, stack) {
      _logger.e('Error deleting message', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to delete message',
      ));
    }
  }

  /// Handle resync request (app resume, network reconnect).
  ///
  /// This resubscribes to the Firestore stream without resetting state,
  /// ensuring any messages received while the app was backgrounded are fetched.
  /// This is critical for WhatsApp-like real-time messaging behavior.
  Future<void> _onResyncRandomGroupChat(
    ResyncRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    if (state.currentGroupId == null || state.currentUserId == null) {
      _logger.d('Resync skipped: no active random group chat');
      return;
    }

    if (!state.membershipVerified) {
      _logger.d('Resync skipped: membership not verified');
      return;
    }

    _logger.i('Resync requested for random group ${state.currentGroupId}');

    // Cancel existing subscription and resubscribe
    await _subscribeToMessages(state.currentGroupId!);
  }

  /// Preload group chat messages into cache without subscribing to streams.
  /// This is triggered on long-press of a group tile to warm the cache
  /// before navigation, making the chat open instantly even on cache miss.
  Future<void> _onPreloadRandomGroupChat(
    PreloadRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    // Skip if already cached with valid TTL
    if (_cacheService.hasValidCache(
      event.groupId,
      ttl: RandomGroupChatCacheService.defaultTtl,
    )) {
      _logger.d('Preload skipped: ${event.groupId} already cached');
      return;
    }

    // Skip if this is the currently open group
    if (state.currentGroupId == event.groupId) {
      _logger.d('Preload skipped: ${event.groupId} is currently open');
      return;
    }

    _logger.i('Preloading messages for random group ${event.groupId}');

    try {
      // Verify membership first before preloading (security)
      final canRead = await _chatService.isActiveMember(
        groupId: event.groupId,
        userId: event.userId,
      );

      if (!canRead) {
        _logger.d('Preload skipped: user not a member of ${event.groupId}');
        return;
      }

      // Fetch initial batch of messages (one-time read, no stream)
      final messages = await _chatService.getMessages(
        groupId: event.groupId,
        limit: 50,
      );

      if (messages.isNotEmpty) {
        // Warm the cache with these messages (mark as preload for TTL tracking)
        _cacheService.updateCache(
          groupId: event.groupId,
          messages: messages,
          hasMore: messages.length >= 50,
          isPreload: true,
        );
        _logger.i(
            'Preloaded ${messages.length} messages for random group ${event.groupId}');
      }
    } catch (e) {
      // Preload failures are silent - don't affect UX
      _logger.d('Preload failed for random group ${event.groupId}: $e');
    }
  }

  /// Cancels all Firestore stream subscriptions.
  /// CRITICAL: Also sets _hasActiveSubscriptions = false to track state properly.
  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _hasActiveSubscriptions = false;
    _logger.d('Subscriptions cancelled, _hasActiveSubscriptions = false');
  }

  /// Subscribes to Firestore messages stream for the current group.
  /// This is extracted to allow resubscription without full state reset.
  Future<void> _subscribeToMessages(String groupId) async {
    // Cancel any existing subscriptions first
    await _cancelSubscriptions();

    // Subscribe to messages stream with better error handling
    _messagesSubscription =
        _chatService.watchMessages(groupId, limit: 50).listen(
      (messages) {
        if (!isClosed) {
          add(_MessagesReceived(messages));
        }
      },
      onError: (error) {
        _logger.e('Error watching messages: $error');
        _hasActiveSubscriptions = false;
        if (isClosed) return;

        if (error is FirebaseException && error.code == 'permission-denied') {
          add(const _ChatStreamError(
              'You no longer have access to this group chat.'));
          return;
        }

        add(const _ChatStreamError('Failed to load messages.'));
      },
    );

    // CRITICAL: Mark subscriptions as active
    _hasActiveSubscriptions = true;
    _logger.i(
        'Message subscription created for random group $groupId, _hasActiveSubscriptions = true');
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    return super.close();
  }
}
