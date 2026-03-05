import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/chat_service.dart';
import '../../domain/entities/conversation.dart';

part 'conversations_event.dart';
part 'conversations_state.dart';

/// BLoC for managing the conversations list.
///
/// Maintains a persistent Firestore stream for real-time updates.
/// The stream is initialized once on first load and remains active
/// throughout the app lifecycle, ensuring instant navigation and
/// live data updates without repeated loading states.
class ConversationsBloc extends Bloc<ConversationsEvent, ConversationsState> {
  final ChatService _chatService;
  final Logger _logger = Logger();

  StreamSubscription<List<Conversation>>? _conversationsSubscription;

  ConversationsBloc({required ChatService chatService})
      : _chatService = chatService,
        super(const ConversationsState()) {
    on<ConversationsLoad>(_onLoad);
    on<ConversationsRefresh>(_onRefresh);
    on<ConversationsMarkAsRead>(_onMarkAsRead);
    on<ConversationsSetActiveChat>(_onSetActiveChat);
    on<ConversationsArchive>(_onArchive);
    on<ConversationsDelete>(_onDelete);
    on<ConversationsClear>(_onClear);
    on<ConversationsMuteToggle>(_onMuteToggle);
    on<ConversationsReset>(_onReset);
    on<_ConversationsUpdated>(_onUpdated);
  }

  Future<void> _onLoad(
    ConversationsLoad event,
    Emitter<ConversationsState> emit,
  ) async {
    // Handle user switching - if different user, force reload
    final isDifferentUser = state.currentUserId != null && 
        state.currentUserId != event.userId;
    
    // If already loading or loaded for the same user, don't reload.
    // This prevents redundant loads when navigating between pages.
    // NOTE: The Firestore stream remains active and continues to emit
    // real-time updates - new messages will appear automatically!
    if (!isDifferentUser &&
        state.currentUserId == event.userId &&
        (state.status == ConversationsStatus.loading ||
         state.status == ConversationsStatus.success)) {
      _logger.i('Conversations already loaded/loading for user ${event.userId}, skipping reload');
      _logger.i('Real-time stream remains active - new messages will appear automatically');
      return;
    }

    // If switching users, cancel existing subscription first and clear old data
    if (isDifferentUser) {
      _logger.i('User changed from ${state.currentUserId} to ${event.userId}, reloading');
      await _conversationsSubscription?.cancel();
      _conversationsSubscription = null;
      emit(state.copyWith(
        status: ConversationsStatus.loading,
        currentUserId: event.userId,
        conversations: const [], // Clear old user's data
      ));
    } else if (state.conversations.isEmpty) {
      // Only show loading state if we have no cached data
      // This provides instant UI for returning users
      emit(state.copyWith(
        status: ConversationsStatus.loading,
        currentUserId: event.userId,
      ));
    } else {
      // Keep showing existing data while refreshing in background
      emit(state.copyWith(
        currentUserId: event.userId,
      ));
    }

    await _conversationsSubscription?.cancel();

    _conversationsSubscription =
        _chatService.getConversationsStream(event.userId).listen(
              (conversations) {
                // Guard against events after bloc is closed
                if (!isClosed) {
                  add(_ConversationsUpdated(conversations));
                }
              },
              onError: (error) {
                _logger.e('Error in conversations stream', error: error);
                // Only show error if we have no cached data and bloc is still open
                if (!isClosed && state.conversations.isEmpty) {
                  emit(state.copyWith(
                    status: ConversationsStatus.error,
                    errorMessage: error.toString(),
                  ));
                }
              },
            );
  }

  Future<void> _onRefresh(
    ConversationsRefresh event,
    Emitter<ConversationsState> emit,
  ) async {
    // For explicit refresh, force a reload by temporarily clearing state
    if (state.currentUserId != null) {
      final userId = state.currentUserId!;
      // Cancel existing subscription to force a fresh one
      await _conversationsSubscription?.cancel();
      _conversationsSubscription = null;
      // Reset to initial status to allow reload
      emit(state.copyWith(status: ConversationsStatus.initial));
      // Now trigger the load
      add(ConversationsLoad(userId: userId));
    }
  }

  void _onUpdated(
    _ConversationsUpdated event,
    Emitter<ConversationsState> emit,
  ) {
    // Filter out archived conversations unless showing archive
    final filtered = state.showArchived
        ? event.conversations
            .where(
              (c) => c.isArchivedBy(state.currentUserId ?? ''),
            )
            .toList()
        : event.conversations
            .where(
              (c) => !c.isArchivedBy(state.currentUserId ?? ''),
            )
            .toList();

    final userId = state.currentUserId ?? '';

    // CRITICAL FIX: Optimistically zero-out the unread count for the
    // conversation the user is currently viewing. Without this, a race
    // between the sender's FieldValue.increment(1) and the viewer's
    // markConversationAsRead can leave a stale unread count in the list.
    // When the user later leaves the chat (SetActiveChat(null)), the
    // recalculated totalUnreadCount would briefly flash the stale value.
    final processed = (state.activeConversationId != null && userId.isNotEmpty)
        ? filtered.map((conversation) {
            if (conversation.id == state.activeConversationId &&
                conversation.getUnreadCount(userId) > 0) {
              final updated =
                  Map<String, int>.from(conversation.unreadCounts);
              updated[userId] = 0;
              return conversation.copyWith(unreadCounts: updated);
            }
            return conversation;
          }).toList()
        : filtered;

    // Calculate total unread count across all conversations,
    // excluding the conversation the user is currently viewing.
    final totalUnread = processed.fold<int>(
      0,
      (sum, conversation) {
        if (conversation.id == state.activeConversationId) return sum;
        return sum + conversation.getUnreadCount(userId);
      },
    );

    emit(state.copyWith(
      status: ConversationsStatus.success,
      conversations: processed,
      totalUnreadCount: totalUnread,
    ));
  }

  Future<void> _onMarkAsRead(
    ConversationsMarkAsRead event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    // Optimistic update: Reset unread count locally for immediate UI response
    final updatedConversations = state.conversations.map((conversation) {
      if (conversation.id == event.conversationId) {
        // Create updated unread counts with current user's count set to 0
        final updatedUnreadCounts = Map<String, int>.from(conversation.unreadCounts);
        updatedUnreadCounts[state.currentUserId!] = 0;
        return conversation.copyWith(unreadCounts: updatedUnreadCounts);
      }
      return conversation;
    }).toList();

    // Recalculate total unread count, excluding active chat
    final totalUnread = updatedConversations.fold<int>(
      0,
      (sum, conversation) {
        if (conversation.id == state.activeConversationId) return sum;
        return sum + conversation.getUnreadCount(state.currentUserId!);
      },
    );

    // Emit optimistic update immediately
    emit(state.copyWith(
      conversations: updatedConversations,
      totalUnreadCount: totalUnread,
    ));

    // Then persist to Firestore (stream will confirm the update)
    try {
      await _chatService.markConversationAsRead(
        conversationId: event.conversationId,
        userId: state.currentUserId!,
      );
      _logger.d('Marked conversation ${event.conversationId} as read');
    } catch (e) {
      _logger.w('Failed to mark conversation as read: $e');
      // Non-critical error - the stream may still update from server
    }
  }

  /// Sets the currently viewed conversation.
  /// While a conversation is active, its unread count is excluded from
  /// totalUnreadCount so the nav badge doesn't flash as messages arrive.
  void _onSetActiveChat(
    ConversationsSetActiveChat event,
    Emitter<ConversationsState> emit,
  ) {
    final bool clearing = event.conversationId == null;
    final userId = state.currentUserId ?? '';

    // CRITICAL FIX: When opening a chat, optimistically reset the unread
    // count for that conversation. This prevents a badge flash when the user
    // quickly navigates back before markConversationAsRead propagates to
    // Firestore. The stream will later confirm the reset.
    List<Conversation> updatedConversations;
    if (!clearing && userId.isNotEmpty) {
      updatedConversations = state.conversations.map((conversation) {
        if (conversation.id == event.conversationId &&
            conversation.getUnreadCount(userId) > 0) {
          final updated =
              Map<String, int>.from(conversation.unreadCounts);
          updated[userId] = 0;
          return conversation.copyWith(unreadCounts: updated);
        }
        return conversation;
      }).toList();
    } else {
      updatedConversations = state.conversations;
    }

    // Recalculate total unread count with the new active chat
    final totalUnread = updatedConversations.fold<int>(
      0,
      (sum, conversation) {
        if (!clearing && conversation.id == event.conversationId) return sum;
        return sum + conversation.getUnreadCount(userId);
      },
    );

    emit(clearing
        ? state.copyWith(
            clearActiveConversationId: true,
            totalUnreadCount: totalUnread,
            conversations: updatedConversations,
          )
        : state.copyWith(
            activeConversationId: event.conversationId,
            totalUnreadCount: totalUnread,
            conversations: updatedConversations,
          ));
  }

  Future<void> _onArchive(
    ConversationsArchive event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    // Optimistic removal — remove from list immediately for snappy UX.
    // The Firestore stream will confirm the change shortly after.
    final optimisticConversations = state.conversations
        .where((c) => c.id != event.conversationId)
        .toList();
    emit(state.copyWith(conversations: optimisticConversations));

    try {
      await _chatService.archiveConversation(
        event.conversationId,
        state.currentUserId!,
        archive: event.archive,
      );
    } catch (e) {
      // Revert — stream will restore the correct state, but show error
      emit(state.copyWith(
        errorMessage: 'Failed to archive conversation',
      ));
    }
  }

  Future<void> _onDelete(
    ConversationsDelete event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    // Optimistic removal — remove from list immediately.
    final optimisticConversations = state.conversations
        .where((c) => c.id != event.conversationId)
        .toList();
    emit(state.copyWith(conversations: optimisticConversations));

    try {
      await _chatService.deleteConversation(
        event.conversationId,
        state.currentUserId!,
      );
    } catch (e) {
      // Revert — stream will restore the correct state, but show error
      emit(state.copyWith(
        errorMessage: 'Failed to delete conversation',
      ));
    }
  }

  Future<void> _onClear(
    ConversationsClear event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    try {
      await _chatService.clearMessages(
        event.conversationId,
        state.currentUserId!,
      );
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to clear conversation',
      ));
    }
  }

  Future<void> _onMuteToggle(
    ConversationsMuteToggle event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    try {
      await _chatService.muteConversation(
        event.conversationId,
        state.currentUserId!,
        mute: event.mute,
      );
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to update mute settings',
      ));
    }
  }

  Future<void> _onReset(
    ConversationsReset event,
    Emitter<ConversationsState> emit,
  ) async {
    await _conversationsSubscription?.cancel();
    _conversationsSubscription = null;
    emit(const ConversationsState());
  }

  @override
  Future<void> close() async {
    await _conversationsSubscription?.cancel();
    _conversationsSubscription = null;
    return super.close();
  }
}
