import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../data/group_chat_cache_service.dart';
import '../../data/group_chat_service.dart';
import '../../domain/entities/group_message.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';

const _uuid = Uuid();

/// BLoC for managing group chat messages with strict membership access control.
///
/// ## Security Model
///
/// This BLoC enforces a **membership-gated access control** model:
///
/// 1. **Membership verification is MANDATORY** before any content is shown.
///    The `membershipVerified` flag in [GroupChatState] gates ALL access.
///
/// 2. **No cached content before verification**: Unlike typical instant-load
///    patterns, we DO NOT show cached messages until membership is confirmed.
///    This prevents privacy leaks from stale cache or URL manipulation.
///
/// 3. **Defense in depth**: This client-side check complements Firestore
///    security rules that also enforce `isGroupMember()` for read/write.
///
/// ## Access Flow
///
/// 1. [OpenGroupChat] → Start loading, `membershipVerified = false`
/// 2. Check `isActiveMember()` → If false, show error and block access
/// 3. If member, set `membershipVerified = true` → NOW show cached/streamed messages
/// 4. [SendGroupMessage] → Blocked if `membershipVerified == false`
///
/// ## Edge Cases Handled
///
/// - User opens chat before data loads → Shows "Verifying access..." spinner
/// - Stale cached membership → Server check overrides cache
/// - User leaves group while chat is open → Stream error revokes access
/// - Direct URL navigation by non-member → Verified check blocks access
/// - Network loss during verification → Error state, access blocked
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final GroupChatService _chatService;
  final GroupChatCacheService _cacheService;
  final Logger _logger;

  StreamSubscription<List<GroupMessage>>? _messagesSubscription;

  GroupChatBloc({
    required GroupChatService chatService,
    required GroupChatCacheService cacheService,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _logger = logger ?? Logger(),
        super(const GroupChatState()) {
    on<OpenGroupChat>(_onOpenGroupChat);
    on<CloseGroupChat>(_onCloseGroupChat);
    on<SendGroupMessage>(_onSendGroupMessage);
    on<LoadMoreGroupMessages>(_onLoadMoreGroupMessages);
    on<ResyncGroupChat>(_onResyncGroupChat);
    on<_GroupMessagesReceived>(_onGroupMessagesReceived);
    on<_GroupChatStreamError>(_onGroupChatStreamError);
    on<DeleteGroupMessage>(_onDeleteGroupMessage);
  }

  Future<void> _onOpenGroupChat(
    OpenGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Opening group chat: ${event.groupId}');

    // Cancel any existing subscription
    await _messagesSubscription?.cancel();

    // ========================================================================
    // CRITICAL SECURITY FIX: Verify membership BEFORE showing ANY content
    // Do NOT show cached messages until membership is confirmed.
    // This prevents privacy leaks from stale cache or URL manipulation.
    // ========================================================================
    
    // Always start with loading state and unverified membership
    emit(state.copyWith(
      status: GroupChatStatus.loading,
      groupId: event.groupId,
      currentUserId: event.currentUserId,
      currentUserName: event.currentUserName,
      currentUserPhotoUrl: event.currentUserPhotoUrl,
      messages: const [], // SECURITY: Don't show cached messages until verified
      hasMore: true,
      errorMessage: null,
      membershipVerified: false, // CRITICAL: Block access until verified
    ));

    try {
      // ======================================================================
      // STEP 1: Verify membership FIRST (security gate)
      // ======================================================================
      final canRead = await _chatService.isActiveMember(
        groupId: event.groupId,
        userId: event.currentUserId,
      );
      
      if (!canRead) {
        _logger.w('Access denied: User ${event.currentUserId} is not a member of group ${event.groupId}');
        // Clear any cached messages for this group to prevent stale data display
        _cacheService.clearGroup(event.groupId);
        emit(state.copyWith(
          status: GroupChatStatus.error,
          errorMessage: 'You are not a member of this group.',
          membershipVerified: false,
          messages: const [],
        ));
        return;
      }

      // ======================================================================
      // STEP 2: Membership verified - NOW we can show cached messages
      // ======================================================================
      _logger.i('Membership verified for user ${event.currentUserId} in group ${event.groupId}');
      
      final cachedMessages = _cacheService.getMessages(event.groupId);
      final hasCache = cachedMessages.isNotEmpty;
      final cachedEntry = _cacheService.getCache(event.groupId);

      if (hasCache) {
        // Show cached messages now that membership is confirmed
        _logger.i('Cache hit for group ${event.groupId}: ${cachedMessages.length} messages');
        emit(state.copyWith(
          status: GroupChatStatus.loaded,
          messages: cachedMessages,
          hasMore: cachedEntry?.hasMore ?? true,
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
      _messagesSubscription = _chatService
          .watchMessages(event.groupId, limit: 50)
          .listen(
            (messages) {
              if (!isClosed) {
                add(_GroupMessagesReceived(messages));
              }
            },
            onError: (error) {
              _logger.e('Error watching messages: $error');
              if (isClosed) return;

              if (error is FirebaseException && error.code == 'permission-denied') {
                add(const _GroupChatStreamError('You no longer have access to this group chat.'));
                return;
              }

              add(const _GroupChatStreamError('Failed to load messages.'));
            },
          );

      // Fetch and set the first unread message ID for showing divider
      try {
        final firstUnreadId = await _chatService.getFirstUnreadMessageId(
          groupId: event.groupId,
          userId: event.currentUserId,
        );
        
        if (firstUnreadId != null && !isClosed) {
          _logger.i('First unread message ID: $firstUnreadId');
          emit(state.copyWith(firstUnreadMessageId: firstUnreadId));
        }
      } catch (e) {
        _logger.w('Failed to get first unread message ID: $e');
        // Continue without unread divider - not critical
      }

      // Mark group as read after a brief delay to ensure messages are loaded
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!isClosed && state.groupId == event.groupId) {
          _chatService.markGroupAsRead(
            groupId: event.groupId,
            userId: event.currentUserId,
          );
          _logger.d('Marked group as read: ${event.groupId}');
        }
      });
    } catch (e, stack) {
      _logger.e('Error opening group chat', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'Failed to load messages',
        membershipVerified: false,
      ));
    }
  }

  Future<void> _onGroupChatStreamError(
    _GroupChatStreamError event,
    Emitter<GroupChatState> emit,
  ) async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    // SECURITY: On access error, revoke membership verification
    // This handles the case where user was removed while viewing chat
    emit(state.copyWith(
      status: GroupChatStatus.error,
      errorMessage: event.message,
      messages: const [],
      hasMore: false,
      membershipVerified: false, // Revoke access on error
    ));
  }

  Future<void> _onCloseGroupChat(
    CloseGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Closing group chat');
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    // Preserve messages for instant display on revisit
    // Only clear the subscription, not the cached data
    emit(state.copyWith(errorMessage: null));
  }

  Future<void> _onSendGroupMessage(
    SendGroupMessage event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) {
      _logger.w('Cannot send message: chat not open');
      return;
    }

    // SECURITY: Verify membership is confirmed before allowing send
    if (!state.membershipVerified) {
      _logger.w('Cannot send message: membership not verified');
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'You must be a member to send messages.',
      ));
      return;
    }

    final text = event.text.trim();
    if (text.isEmpty) return;

    _logger.d('Sending message: ${text.substring(0, text.length.clamp(0, 20))}...');

    // ========================================================================
    // OPTIMISTIC UPDATE: Show message immediately in UI for instant feedback
    // This creates a WhatsApp-like experience where your message appears
    // instantly, then gets confirmed when the server responds.
    // ========================================================================
    final localId = _uuid.v4();
    final optimisticMessage = GroupMessage(
      id: localId, // Temporary ID until server assigns real one
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: text,
      sentAt: DateTime.now(),
      localId: localId,
    );

    // Add optimistic message to the front of the list
    final updatedMessages = [optimisticMessage, ...state.messages];
    emit(state.copyWith(
      status: GroupChatStatus.sending,
      messages: updatedMessages,
    ));

    try {
      await _chatService.sendMessage(
        groupId: state.groupId!,
        senderId: state.currentUserId!,
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: text,
      );

      // Success: The Firestore stream will automatically update with the real
      // message (with server-assigned ID). The optimistic message will be
      // replaced when _onGroupMessagesReceived merges the new data.
      emit(state.copyWith(status: GroupChatStatus.loaded));
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);

      // Remove the failed optimistic message and show error
      final messagesWithoutFailed = state.messages
          .where((m) => m.localId != localId)
          .toList();

      // Provide helpful error messages based on error type
      String errorMessage = 'Failed to send message. Please try again.';
      if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          errorMessage = 'Unable to send message. This may happen if you just joined. Please wait a moment and try again.';
        } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          errorMessage = 'Network error. Please check your connection and try again.';
        }
      }

      // Don't revoke membership verification for send errors - membership
      // was already verified when chat opened. A send error is just a
      // temporary issue (network, permissions, etc.) and shouldn't kick user out.
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: errorMessage,
        messages: messagesWithoutFailed,
      ));
    }
  }

  Future<void> _onLoadMoreGroupMessages(
    LoadMoreGroupMessages event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || !state.hasMore || state.isLoading) {
      return;
    }

    if (state.messages.isEmpty) return;

    _logger.d('Loading more messages');

    final oldestMessage = state.messages.last;

    try {
      final olderMessages = await _chatService.loadMoreMessages(
        state.groupId!,
        beforeTimestamp: oldestMessage.sentAt,
        limit: 30,
      );

      final hasMore = olderMessages.length >= 30;
      
      // Deduplicate: ensure no overlap with existing messages
      final existingIds = state.messages.map((m) => m.id).toSet();
      final uniqueOlderMessages = olderMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();
      
      final allMessages = [...state.messages, ...uniqueOlderMessages];

      // Update the cache with paginated messages
      _cacheService.addPaginatedMessages(
        groupId: state.groupId!,
        olderMessages: olderMessages,
        hasMore: hasMore,
      );

      emit(state.copyWith(
        messages: allMessages,
        hasMore: hasMore,
      ));
    } catch (e, stack) {
      _logger.e('Error loading more messages', error: e, stackTrace: stack);
      // Don't show error for pagination, just stop loading more
      emit(state.copyWith(hasMore: false));
    }
  }

  void _onGroupMessagesReceived(
    _GroupMessagesReceived event,
    Emitter<GroupChatState> emit,
  ) {
    _logger.d('Received ${event.messages.length} messages');

    const pageSize = 50;

    // CRITICAL FIX: Deduplicate messages by ID to prevent double display
    // Create a Set of IDs from newly received messages for O(1) lookup
    final newMessageIds = event.messages.map((m) => m.id).toSet();
    
    // Merge with any older messages we've loaded via pagination
    // Filter out:
    // 1. Duplicates (same ID as incoming messages)
    // 2. Optimistic messages (have localId) - they'll be replaced by real ones
    // 3. Messages newer than the stream batch (unless they're pending optimistic)
    final currentOldMessages = state.messages.where((m) {
      // Skip if message is already in the new batch (prevents duplicates)
      if (newMessageIds.contains(m.id)) return false;
      
      // Remove optimistic messages - they should be replaced by the real
      // server-confirmed messages from the stream
      if (m.localId != null) {
        return false;
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
    if (state.groupId != null) {
      _cacheService.updateCache(
        groupId: state.groupId!,
        messages: allMessages,
        hasMore: hasMore,
      );
    }

    // Always set status to loaded when we receive messages to clear loading state
    emit(state.copyWith(
      status: GroupChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
    ));

    if (state.groupId != null && state.currentUserId != null) {
      unawaited(_chatService.markGroupAsRead(
        groupId: state.groupId!,
        userId: state.currentUserId!,
      ));
    }
  }

  Future<void> _onDeleteGroupMessage(
    DeleteGroupMessage event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null) return;

    _logger.d('Deleting message: ${event.messageId}');

    try {
      await _chatService.deleteMessage(state.groupId!, event.messageId);
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
  Future<void> _onResyncGroupChat(
    ResyncGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) {
      _logger.d('Resync skipped: no active group chat');
      return;
    }

    if (!state.membershipVerified) {
      _logger.d('Resync skipped: membership not verified');
      return;
    }

    _logger.i('Resync requested for group ${state.groupId}');

    // Cancel existing subscription and resubscribe
    await _messagesSubscription?.cancel();

    _messagesSubscription = _chatService
        .watchMessages(state.groupId!, limit: 50)
        .listen(
          (messages) {
            if (!isClosed) {
              add(_GroupMessagesReceived(messages));
            }
          },
          onError: (error) {
            _logger.e('Error watching messages on resync: $error');
            if (isClosed) return;

            if (error is FirebaseException && error.code == 'permission-denied') {
              add(const _GroupChatStreamError('You no longer have access to this group chat.'));
              return;
            }

            add(const _GroupChatStreamError('Failed to load messages.'));
          },
        );
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
