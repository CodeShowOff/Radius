import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/chat_service.dart';
import '../../domain/entities/conversation.dart';

part 'conversations_event.dart';
part 'conversations_state.dart';

/// BLoC for managing the conversations list.
class ConversationsBloc extends Bloc<ConversationsEvent, ConversationsState> {
  final ChatService _chatService;

  StreamSubscription<List<Conversation>>? _conversationsSubscription;

  ConversationsBloc({required ChatService chatService})
      : _chatService = chatService,
        super(const ConversationsState()) {
    on<ConversationsLoad>(_onLoad);
    on<ConversationsRefresh>(_onRefresh);
    on<ConversationsMarkAsRead>(_onMarkAsRead);
    on<ConversationsArchive>(_onArchive);
    on<ConversationsDelete>(_onDelete);
    on<ConversationsMuteToggle>(_onMuteToggle);
    on<_ConversationsUpdated>(_onUpdated);
  }

  Future<void> _onLoad(
    ConversationsLoad event,
    Emitter<ConversationsState> emit,
  ) async {
    emit(state.copyWith(
      status: ConversationsStatus.loading,
      currentUserId: event.userId,
    ));

    await _conversationsSubscription?.cancel();

    _conversationsSubscription =
        _chatService.getConversationsStream(event.userId).listen(
              (conversations) => add(_ConversationsUpdated(conversations)),
              onError: (error) => emit(state.copyWith(
                status: ConversationsStatus.error,
                errorMessage: error.toString(),
              )),
            );
  }

  Future<void> _onRefresh(
    ConversationsRefresh event,
    Emitter<ConversationsState> emit,
  ) async {
    if (state.currentUserId != null) {
      add(ConversationsLoad(userId: state.currentUserId!));
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
