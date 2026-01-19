import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/group_chat_service.dart';
import '../../domain/entities/group_message.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';

/// BLoC for managing group chat messages.
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final GroupChatService _chatService;
  final Logger _logger;

  StreamSubscription<List<GroupMessage>>? _messagesSubscription;

  GroupChatBloc({
    required GroupChatService chatService,
    Logger? logger,
  })  : _chatService = chatService,
        _logger = logger ?? Logger(),
        super(const GroupChatState()) {
    on<OpenGroupChat>(_onOpenGroupChat);
    on<CloseGroupChat>(_onCloseGroupChat);
    on<SendGroupMessage>(_onSendGroupMessage);
    on<LoadMoreGroupMessages>(_onLoadMoreGroupMessages);
    on<_GroupMessagesReceived>(_onGroupMessagesReceived);
    on<DeleteGroupMessage>(_onDeleteGroupMessage);
  }

  Future<void> _onOpenGroupChat(
    OpenGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Opening group chat: ${event.groupId}');

    // Cancel any existing subscription
    await _messagesSubscription?.cancel();

    emit(state.copyWith(
      status: GroupChatStatus.loading,
      groupId: event.groupId,
      currentUserId: event.currentUserId,
      currentUserName: event.currentUserName,
      currentUserPhotoUrl: event.currentUserPhotoUrl,
      messages: [],
      hasMore: true,
    ));

    try {
      // Start listening to messages
      _messagesSubscription = _chatService
          .watchMessages(event.groupId, limit: 50)
          .listen(
            (messages) => add(_GroupMessagesReceived(messages)),
            onError: (error) {
              _logger.e('Error watching messages: $error');
              add(const _GroupMessagesReceived([]));
            },
          );
    } catch (e, stack) {
      _logger.e('Error opening group chat', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'Failed to load messages',
      ));
    }
  }

  Future<void> _onCloseGroupChat(
    CloseGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Closing group chat');
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    emit(const GroupChatState());
  }

  Future<void> _onSendGroupMessage(
    SendGroupMessage event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) {
      _logger.w('Cannot send message: chat not open');
      return;
    }

    final text = event.text.trim();
    if (text.isEmpty) return;

    _logger.d('Sending message: ${text.substring(0, text.length.clamp(0, 20))}...');

    emit(state.copyWith(status: GroupChatStatus.sending));

    try {
      await _chatService.sendMessage(
        groupId: state.groupId!,
        senderId: state.currentUserId!,
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: text,
      );

      emit(state.copyWith(status: GroupChatStatus.loaded));
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'Failed to send message',
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

      emit(state.copyWith(
        messages: [...state.messages, ...olderMessages],
        hasMore: olderMessages.length >= 30,
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

    // Merge with any older messages we've loaded via pagination
    final currentOldMessages = state.messages.where((m) {
      // Keep messages that are older than the oldest message in the new list
      if (event.messages.isEmpty) return true;
      return m.sentAt.isBefore(event.messages.last.sentAt);
    }).toList();

    emit(state.copyWith(
      status: GroupChatStatus.loaded,
      messages: [...event.messages, ...currentOldMessages],
    ));
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

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
