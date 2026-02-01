import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/random_group_chat_cache_service.dart';
import '../../data/random_group_chat_service.dart';
import '../../domain/entities/random_group_message.dart';

part 'random_group_chat_event.dart';
part 'random_group_chat_state.dart';

/// BLoC for managing random group chat messages.
///
/// Handles:
/// - Real-time message streaming
/// - Sending messages
/// - Message pagination
/// - Message caching
class RandomGroupChatBloc
    extends Bloc<RandomGroupChatEvent, RandomGroupChatState> {
  final RandomGroupChatService _chatService;
  final RandomGroupChatCacheService _cacheService;
  final Logger _logger;

  StreamSubscription<List<RandomGroupMessage>>? _messagesSubscription;

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
    on<_MessagesReceived>(_onMessagesReceived);
    on<_ChatStreamError>(_onChatStreamError);
  }

  Future<void> _onOpenRandomGroupChat(
    OpenRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    _logger.d('Opening random group chat: ${event.groupId}');

    // Cancel any existing subscription
    await _messagesSubscription?.cancel();

    // Check if user is a member
    final isMember = await _chatService.isMember(
      groupId: event.groupId,
      userId: event.userId,
    );

    // Load cached messages first for instant display
    final cachedMessages = _cacheService.getMessages(event.groupId);
    final hasCachedMessages = cachedMessages.isNotEmpty;

    emit(state.copyWith(
      status:
          hasCachedMessages ? RandomGroupChatStatus.loaded : RandomGroupChatStatus.loading,
      currentGroupId: event.groupId,
      messages: cachedMessages,
      isMember: isMember,
      clearError: true,
    ));

    // Start streaming messages
    _messagesSubscription = _chatService.watchMessages(event.groupId).listen(
      (messages) => add(_MessagesReceived(messages)),
      onError: (error) => add(_ChatStreamError(error.toString())),
    );
  }

  Future<void> _onCloseRandomGroupChat(
    CloseRandomGroupChat event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    _logger.d('Closing random group chat');

    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    emit(const RandomGroupChatState());
  }

  Future<void> _onSendRandomGroupMessage(
    SendRandomGroupMessage event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    _logger.d('Sending message to random group: ${event.groupId}');

    emit(state.copyWith(status: RandomGroupChatStatus.sending, clearError: true));

    try {
      final message = await _chatService.sendMessage(
        groupId: event.groupId,
        senderId: event.senderId,
        senderUsername: event.senderUsername,
        senderName: event.senderName,
        senderPhotoUrl: event.senderPhotoUrl,
        text: event.text,
      );

      // Optimistically add message to list
      final updatedMessages = [message, ...state.messages];

      emit(state.copyWith(
        status: RandomGroupChatStatus.loaded,
        messages: updatedMessages,
      ));

      // Update cache
      _cacheService.updateCache(
        groupId: event.groupId,
        messages: updatedMessages,
      );
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: RandomGroupChatStatus.error,
        errorMessage: 'Failed to send message',
      ));
    }
  }

  Future<void> _onLoadMoreRandomGroupMessages(
    LoadMoreRandomGroupMessages event,
    Emitter<RandomGroupChatState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) {
      return;
    }

    _logger.d('Loading more messages for: ${event.groupId}');

    emit(state.copyWith(isLoadingMore: true));

    try {
      final oldestMessage = state.messages.last;
      final olderMessages = await _chatService.loadMoreMessages(
        groupId: event.groupId,
        beforeTimestamp: oldestMessage.sentAt,
      );

      final hasMore = olderMessages.length >= 50;
      final allMessages = [...state.messages, ...olderMessages];

      emit(state.copyWith(
        messages: allMessages,
        hasMore: hasMore,
        isLoadingMore: false,
      ));

      // Update cache with paginated messages
      _cacheService.addPaginatedMessages(
        groupId: event.groupId,
        olderMessages: olderMessages,
        hasMore: hasMore,
      );
    } catch (e, stack) {
      _logger.e('Error loading more messages', error: e, stackTrace: stack);
      emit(state.copyWith(
        isLoadingMore: false,
        errorMessage: 'Failed to load more messages',
      ));
    }
  }

  void _onMessagesReceived(
    _MessagesReceived event,
    Emitter<RandomGroupChatState> emit,
  ) {
    _logger.d('Received ${event.messages.length} messages');

    // Merge with any older paginated messages in state
    final newMessageIds = event.messages.map((m) => m.id).toSet();
    final existingOlderMessages = state.messages
        .where((m) => !newMessageIds.contains(m.id))
        .where((m) => event.messages.isEmpty ||
            m.sentAt.isBefore(event.messages.last.sentAt))
        .toList();

    final mergedMessages = [...event.messages, ...existingOlderMessages];

    emit(state.copyWith(
      status: RandomGroupChatStatus.loaded,
      messages: mergedMessages,
    ));

    // Update cache
    if (state.currentGroupId != null) {
      _cacheService.updateCache(
        groupId: state.currentGroupId!,
        messages: mergedMessages,
      );
    }
  }

  void _onChatStreamError(
    _ChatStreamError event,
    Emitter<RandomGroupChatState> emit,
  ) {
    _logger.e('Chat stream error: ${event.message}');
    emit(state.copyWith(
      status: RandomGroupChatStatus.error,
      errorMessage: event.message,
    ));
  }

  @override
  Future<void> close() async {
    await _messagesSubscription?.cancel();
    return super.close();
  }
}
