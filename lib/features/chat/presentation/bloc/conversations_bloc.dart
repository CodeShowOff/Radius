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
    on<ConversationsArchive>(_onArchive);
    on<ConversationsDelete>(_onDelete);
    on<ConversationsClear>(_onClear);
    on<ConversationsMuteToggle>(_onMuteToggle);
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
        totalUnreadCount: 0,
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

    // Calculate total unread
    int totalUnread = 0;
    for (final conv in filtered) {
      totalUnread += conv.getUnreadCount(state.currentUserId ?? '');
    }

    emit(state.copyWith(
      status: ConversationsStatus.success,
      conversations: filtered,
      totalUnreadCount: totalUnread,
    ));
  }

  Future<void> _onMarkAsRead(
    ConversationsMarkAsRead event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    try {
      await _chatService.markConversationAsRead(
        event.conversationId,
        state.currentUserId!,
      );
    } catch (e) {
      emit(state.copyWith(
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onArchive(
    ConversationsArchive event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId == null) return;

    try {
      await _chatService.archiveConversation(
        event.conversationId,
        state.currentUserId!,
        archive: event.archive,
      );
    } catch (e) {
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

    try {
      await _chatService.deleteConversation(
        event.conversationId,
        state.currentUserId!,
      );
    } catch (e) {
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

  @override
  Future<void> close() {
    _conversationsSubscription?.cancel();
    return super.close();
  }
}
