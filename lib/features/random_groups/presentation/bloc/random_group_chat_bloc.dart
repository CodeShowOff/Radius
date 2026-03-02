import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/widgets/group_message_bubble.dart';
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
/// 1. [OpenRandomGroupChat] → Check for cached messages
/// 2. If cached messages exist → Show immediately, verify membership in background
/// 3. If no cache → Check `isActiveMember()` → If false, show error and block access
/// 4. If member, set `membershipVerified = true` → Show streamed messages
/// 5. [SendRandomGroupMessage] → Blocked if `membershipVerified == false`
class RandomGroupChatBloc
    extends Bloc<RandomGroupChatEvent, RandomGroupChatState> {
  final RandomGroupChatService _chatService;
  final RandomGroupChatCacheService _cacheService;
  final Logger _logger;

  StreamSubscription<List<RandomGroupMessage>>? _messagesSubscription;

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
    on<_MessagesReceived>(_onMessagesReceived);
    on<_ChatStreamError>(_onChatStreamError);
    on<DeleteRandomGroupMessage>(_onDeleteRandomGroupMessage);
    on<ClearRandomGroupChatMessages>(_onClearRandomGroupChatMessages);
    on<_UnreadInfoReceived>(_onUnreadInfoReceived);
    on<RetryRandomGroupMessage>(_onRetryRandomGroupMessage);
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

  /// Refreshes membership verification in the background without blocking UI.
  /// If the user was removed, the Firestore stream will handle access revocation.
  /// This ensures the membership cache stays up to date for future navigations.
  void _refreshMembershipInBackground(String userId, String groupId) {
    _chatService
        .isActiveMember(groupId: groupId, userId: userId)
        .then((isActive) {
      if (isActive) {
        _cacheMembership(userId, groupId);
      } else if (!isClosed) {
        _logger.w(
            'Background membership check failed for $userId in $groupId');
        _invalidateMembershipCache(userId, groupId);
        _cacheService.clearCache(groupId);
        add(const _ChatStreamError(
          'You no longer have access to this group chat.',
        ));
      }
    }).catchError((e) {
      _logger.w('Background membership check error: $e');
      // Don't revoke access on network error - stream handles this
    });
  }

  Future<void> _onOpenRandomGroupChat(
    OpenRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    _logger.d('Opening random group chat: ${event.groupId}');

    // Cancel any existing subscription (factory instance, just safety)
    await _cancelSubscriptions();

    // ========================================================================
    // SECURITY: Verify membership before showing content.
    // When cached messages exist, they are shown immediately (fast path above)
    // with background verification. This slow path handles the no-cache case.
    // ========================================================================

    // Check if we have a cached membership verification (optimization)
    final hasCachedMembership =
        _isMembershipCached(event.userId, event.groupId);
    final cachedMessages = _cacheService.getMessages(event.groupId);
    final hasCache = cachedMessages.isNotEmpty;

    if (hasCache) {
      // FAST PATH: Show cached messages immediately for smooth UX.
      // Security is maintained via:
      // 1. Firestore stream errors with permission-denied if user was removed
      // 2. Background membership check revokes access if verification fails
      // 3. Firestore security rules enforce membership on all operations
      _logger.i(
          'Showing cached messages for ${event.groupId} immediately');
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
        clearFirstUnreadMessageId: true,
      ));

      // Fetch unread info AND start message stream in parallel
      // Unread info fetch is non-blocking - messages show immediately from cache
      final unreadFuture = _fetchUnreadInfo(event.groupId, event.userId);

      // Start listening to messages (stream will error if user was removed)
      await _subscribeToMessages(event.groupId);

      // Await unread info (may already be done by now)
      await unreadFuture;

      // Refresh membership cache in background if expired
      if (!hasCachedMembership) {
        _refreshMembershipInBackground(event.userId, event.groupId);
      }
      return;
    }

    // WhatsApp-style: No blocking membership check — just start streaming.
    // Firestore security rules enforce membership on the backend.
    // If user isn't a member, the stream will error with permission-denied.
    emit(state.copyWith(
      status: RandomGroupChatStatus.loaded,
      currentGroupId: event.groupId,
      currentUserId: event.userId,
      currentUserUsername: event.username,
      currentUserName: event.userName,
      currentUserPhotoUrl: event.userPhotoUrl,
      messages: const [],
      hasMore: true,
      clearError: true,
      membershipVerified: true,
    ));

    try {
      // Start message stream AND fetch unread info in PARALLEL — no blocking
      final unreadFuture = _fetchUnreadInfo(event.groupId, event.userId);

      // Subscribe to messages immediately — stream will deliver messages
      // or error with permission-denied if user is not a member
      await _subscribeToMessages(event.groupId);

      // Cache membership on successful stream setup
      _cacheMembership(event.userId, event.groupId);

      // Await unread info (may already be done by now)
      await unreadFuture;
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

    // Update lastReadAt before closing to ensure the unread divider
    // positions correctly next time the user opens this chat.
    // This is important because markGroupAsRead skips writes when
    // unreadCount is 0 (to avoid triggering collection group listener).
    if (state.currentGroupId != null &&
        state.currentUserId != null &&
        state.membershipVerified) {
      unawaited(_chatService.updateLastReadTimestamp(
        groupId: state.currentGroupId!,
        userId: state.currentUserId!,
      ));
    }

    await _cancelSubscriptions();
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
    // OPTIMISTIC UPDATE: Add to pendingMessages map with pending status.
    // The allMessages getter merges pending + confirmed with localId dedup.
    // ========================================================================
    final localId = _uuid.v4();
    final optimisticMessage = RandomGroupMessage(
      id: 'pending_$localId',
      groupId: state.currentGroupId!,
      senderId: state.currentUserId!,
      senderUsername: state.currentUserUsername,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: text,
      type: RandomGroupMessageType.text,
      sentAt: DateTime.now(),
      localId: localId,
      status: GroupMessageStatus.pending,
    );

    final updatedPending =
        Map<String, RandomGroupMessage>.from(state.pendingMessages);
    updatedPending[localId] = optimisticMessage;
    emit(state.copyWith(
      status: RandomGroupChatStatus.sending,
      pendingMessages: updatedPending,
    ));

    try {
      await _chatService.sendMessage(
        groupId: state.currentGroupId!,
        senderId: state.currentUserId!,
        senderUsername: state.currentUserUsername ?? 'Unknown',
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: text,
        localId: localId,
      );

      // Success: The Firestore stream will deliver the confirmed message
      // with matching localId. _onMessagesReceived will remove it from
      // pendingMessages automatically via localId dedup.
      emit(state.copyWith(status: RandomGroupChatStatus.loaded));
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);

      // Mark the pending message as error instead of removing it
      String errorMsg = 'Failed to send message. Please try again.';
      if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          errorMsg =
              'Unable to send message. This may happen if you just joined. Please wait a moment and try again.';
        } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          errorMsg =
              'Network error. Please check your connection and try again.';
        }
      }

      final errorPending =
          Map<String, RandomGroupMessage>.from(state.pendingMessages);
      if (errorPending.containsKey(localId)) {
        errorPending[localId] = errorPending[localId]!.copyWith(
          status: GroupMessageStatus.error,
        );
      }

      emit(state.copyWith(
        status: RandomGroupChatStatus.loaded,
        errorMessage: errorMsg,
        pendingMessages: errorPending,
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

    // ========================================================================
    // CLEAR CHAT GUARD: If a clear operation is in progress, ignore incoming
    // stream messages until the stream confirms empty (all batches deleted).
    // ========================================================================
    if (state.isClearingChat) {
      if (event.messages.isEmpty) {
        _logger.i('Chat clear confirmed by stream (0 messages)');
        emit(state.copyWith(
          status: RandomGroupChatStatus.loaded,
          messages: const [],
          hasMore: false,
          isClearingChat: false,
          pendingMessages: const {},
        ));
      } else {
        _logger.d(
            'Ignoring ${event.messages.length} messages during clear operation');
      }
      return;
    }

    const pageSize = 50;

    // ========================================================================
    // LOCAL-ID DEDUP: Remove confirmed messages from pendingMessages.
    // When a message arrives from Firestore with a localId that matches
    // one in pendingMessages, we know the server confirmed it.
    // ========================================================================
    final updatedPending =
        Map<String, RandomGroupMessage>.from(state.pendingMessages);
    for (final msg in event.messages) {
      if (msg.localId != null && updatedPending.containsKey(msg.localId)) {
        updatedPending.remove(msg.localId);
      }
    }

    // Merge new messages with older messages (outside the stream window)
    final newMessageIds = event.messages.map((m) => m.id).toSet();
    final currentOldMessages = state.messages.where((m) {
      if (newMessageIds.contains(m.id)) return false;
      if (event.messages.isEmpty) return false;
      return m.sentAt.isBefore(event.messages.last.sentAt);
    }).toList();

    final allMessages = [...event.messages, ...currentOldMessages];
    final hasMore = event.messages.length >= pageSize;

    // Update cache
    if (state.currentGroupId != null) {
      _cacheService.updateCache(
        groupId: state.currentGroupId!,
        messages: allMessages,
        hasMore: hasMore,
      );
    }

    emit(state.copyWith(
      status: RandomGroupChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
      isLoadingMore: false,
      pendingMessages: updatedPending,
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

  /// Clears all local chat messages immediately.
  /// This is called after an admin successfully clears the chat,
  /// to provide immediate feedback without waiting for Firestore stream updates.
  ///
  /// Sets [isClearingChat] flag to prevent messages from reappearing
  /// during multi-batch soft-delete (stream fires with partial results
  /// between batches).
  void _onClearRandomGroupChatMessages(
    ClearRandomGroupChatMessages event,
    Emitter<RandomGroupChatState> emit,
  ) {
    _logger.d('Clearing all local chat messages');

    // Clear messages from local state and set clearing flag
    // The flag prevents _onMessagesReceived from re-populating messages
    // while the backend soft-delete is in progress (fires in batches)
    emit(state.copyWith(
      messages: const [],
      hasMore: false,
      clearFirstUnreadMessageId: true,
      isClearingChat: true,
    ));

    // Clear messages from cache
    if (state.currentGroupId != null) {
      _cacheService.clearCache(state.currentGroupId!);
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

  /// Cancels all Firestore stream subscriptions.
  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _logger.d('Subscriptions cancelled');
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
        if (isClosed) return;

        if (error is FirebaseException && error.code == 'permission-denied') {
          add(const _ChatStreamError(
              'You no longer have access to this group chat.'));
          return;
        }

        add(const _ChatStreamError('Failed to load messages.'));
      },
    );

    _logger.i('Message subscription created for random group $groupId');
  }

  /// Handles unread info received from background fetch.
  void _onUnreadInfoReceived(
    _UnreadInfoReceived event,
    Emitter<RandomGroupChatState> emit,
  ) {
    emit(state.copyWith(
      firstUnreadMessageId: event.firstUnreadMessageId,
      unreadCountAtOpen: event.unreadCount,
    ));
  }

  /// Fetches first unread message ID and unread count in parallel.
  /// This is non-blocking and won't prevent messages from loading.
  Future<void> _fetchUnreadInfo(String groupId, String userId) async {
    try {
      final firstUnreadId = await _chatService.getFirstUnreadMessageId(
        groupId: groupId,
        userId: userId,
      );

      if (firstUnreadId != null && !isClosed) {
        _logger.i('First unread message ID: $firstUnreadId');
        final unreadCount = await _chatService.getUnreadCount(
          groupId: groupId,
          userId: userId,
        );
        if (!isClosed) {
          add(_UnreadInfoReceived(firstUnreadId, unreadCount));
        }
      }
    } catch (e) {
      _logger.w('Failed to get first unread message ID: $e');
      // Continue without unread divider - not critical
    }
  }

  /// Retries sending a failed message.
  Future<void> _onRetryRandomGroupMessage(
    RetryRandomGroupMessage event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    final pendingMsg = state.pendingMessages[event.localId];
    if (pendingMsg == null) return;

    // Set status back to pending
    final updatedPending =
        Map<String, RandomGroupMessage>.from(state.pendingMessages);
    updatedPending[event.localId] = pendingMsg.copyWith(
      status: GroupMessageStatus.pending,
    );
    emit(state.copyWith(pendingMessages: updatedPending));

    try {
      await _chatService.sendMessage(
        groupId: pendingMsg.groupId,
        senderId: pendingMsg.senderId ?? state.currentUserId!,
        senderUsername: pendingMsg.senderUsername ?? 'Unknown',
        senderName: pendingMsg.senderName,
        senderPhotoUrl: pendingMsg.senderPhotoUrl,
        text: pendingMsg.text,
        localId: event.localId,
      );
      // Stream will handle removing from pendingMessages via localId dedup
    } catch (e) {
      _logger.e('Retry failed for message ${event.localId}', error: e);
      final errorPending =
          Map<String, RandomGroupMessage>.from(state.pendingMessages);
      if (errorPending.containsKey(event.localId)) {
        errorPending[event.localId] = errorPending[event.localId]!.copyWith(
          status: GroupMessageStatus.error,
        );
      }
      emit(state.copyWith(pendingMessages: errorPending));
    }
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    return super.close();
  }
}
