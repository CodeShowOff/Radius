import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/chat_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// BLoC for managing a single chat conversation.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatService _chatService;

  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Conversation?>? _conversationSubscription;
  StreamSubscription<bool>? _typingSubscription;

  Timer? _typingDebounce;

  ChatBloc({required ChatService chatService})
      : _chatService = chatService,
        super(const ChatState()) {
    on<ChatOpen>(_onOpen);
    on<ChatClose>(_onClose);
    on<ChatSendMessage>(_onSendMessage);
    on<ChatLoadMore>(_onLoadMore);
    on<ChatMarkAsRead>(_onMarkAsRead);
    on<ChatSetTyping>(_onSetTyping);
    on<ChatDeleteMessage>(_onDeleteMessage);
    on<_ChatMessagesUpdated>(_onMessagesUpdated);
    on<_ChatConversationUpdated>(_onConversationUpdated);
    on<_ChatTypingUpdated>(_onTypingUpdated);
  }

  Future<void> _onOpen(
    ChatOpen event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(
      status: ChatStatus.loading,
      conversationId: event.conversationId,
      currentUserId: event.currentUserId,
      otherUserId: event.otherUserId,
      otherUserName: event.otherUserName,
      otherUserPhotoUrl: event.otherUserPhotoUrl,
    ));

    // Cancel existing subscriptions
    await _cancelSubscriptions();

    // Subscribe to messages stream
    _messagesSubscription = _chatService
        .getMessagesStream(event.conversationId)
        .listen((messages) => add(_ChatMessagesUpdated(messages)));

    // Subscribe to conversation updates
    _conversationSubscription = _chatService
        .getConversationStream(event.conversationId)
        .listen((conversation) => add(_ChatConversationUpdated(conversation)));

    // Subscribe to typing indicator
    _typingSubscription = _chatService
        .getTypingStream(event.conversationId, event.otherUserId)
        .listen((isTyping) => add(_ChatTypingUpdated(isTyping)));

    // Mark messages as delivered when opening chat
    await _chatService.markMessagesAsDelivered(
      conversationId: event.conversationId,
      userId: event.currentUserId,
    );

    emit(state.copyWith(status: ChatStatus.loaded));
  }

  Future<void> _onClose(
    ChatClose event,
    Emitter<ChatState> emit,
  ) async {
    // Clear typing indicator
    if (state.conversationId != null && state.currentUserId != null) {
      await _chatService.setTyping(
        conversationId: state.conversationId!,
        userId: state.currentUserId!,
        isTyping: false,
      );
    }

    await _cancelSubscriptions();
    _typingDebounce?.cancel();

    emit(const ChatState());
  }

  Future<void> _onSendMessage(
    ChatSendMessage event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null ||
        state.currentUserId == null ||
        event.text.trim().isEmpty) {
      return;
    }

    // Clear typing indicator
    _typingDebounce?.cancel();
    await _chatService.setTyping(
      conversationId: state.conversationId!,
      userId: state.currentUserId!,
      isTyping: false,
    );

    // Send message with optimistic update
    final sentMessage = await _chatService.sendMessage(
      conversationId: state.conversationId!,
      senderId: state.currentUserId!,
      text: event.text,
      recipientId: state.otherUserId,
    );

    // Add to pending messages for optimistic UI
    if (sentMessage.status == MessageStatus.sending ||
        sentMessage.status == MessageStatus.failed) {
      final pending = Map<String, Message>.from(state.pendingMessages);
      pending[sentMessage.localId ?? sentMessage.id] = sentMessage;
      emit(state.copyWith(pendingMessages: pending));
    }

    // Remove from pending if sent successfully
    if (sentMessage.status == MessageStatus.sent) {
      final pending = Map<String, Message>.from(state.pendingMessages);
      pending.remove(sentMessage.localId);
      emit(state.copyWith(pendingMessages: pending));
    }
  }

  Future<void> _onLoadMore(
    ChatLoadMore event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null ||
        !state.hasMore ||
        state.status == ChatStatus.loadingMore) {
      return;
    }

    final oldestTime = state.oldestMessageTime;
    if (oldestTime == null) return;

    emit(state.copyWith(status: ChatStatus.loadingMore));

    final olderMessages = await _chatService.loadMoreMessages(
      state.conversationId!,
      before: oldestTime,
    );

    emit(state.copyWith(
      status: ChatStatus.loaded,
      messages: [...olderMessages, ...state.messages],
      hasMore: olderMessages.length >= 50,
    ));
  }

  Future<void> _onMarkAsRead(
    ChatMarkAsRead event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    await _chatService.markMessagesAsRead(
      conversationId: state.conversationId!,
      userId: state.currentUserId!,
    );
  }

  Future<void> _onSetTyping(
    ChatSetTyping event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    // Debounce typing indicator to avoid too many writes
    _typingDebounce?.cancel();

    if (event.isTyping) {
      await _chatService.setTyping(
        conversationId: state.conversationId!,
        userId: state.currentUserId!,
        isTyping: true,
      );

      // Auto-clear typing after 3 seconds of no activity
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        _chatService.setTyping(
          conversationId: state.conversationId!,
          userId: state.currentUserId!,
          isTyping: false,
        );
      });
    } else {
      await _chatService.setTyping(
        conversationId: state.conversationId!,
        userId: state.currentUserId!,
        isTyping: false,
      );
    }
  }

  Future<void> _onDeleteMessage(
    ChatDeleteMessage event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    await _chatService.deleteMessage(
      conversationId: state.conversationId!,
      messageId: event.messageId,
      userId: state.currentUserId!,
    );
  }

  void _onMessagesUpdated(
    _ChatMessagesUpdated event,
    Emitter<ChatState> emit,
  ) {
    // Remove confirmed messages from pending
    final pending = Map<String, Message>.from(state.pendingMessages);

    for (final message in event.messages) {
      // Check if this message matches a pending one
      pending.removeWhere((key, pendingMsg) =>
          pendingMsg.localId == message.localId ||
          (pendingMsg.text == message.text &&
              pendingMsg.senderId == message.senderId &&
              message.sentAt.difference(pendingMsg.sentAt).abs().inSeconds < 5));
    }

    emit(state.copyWith(
      messages: event.messages,
      pendingMessages: pending,
    ));
  }

  void _onConversationUpdated(
    _ChatConversationUpdated event,
    Emitter<ChatState> emit,
  ) {
    if (event.conversation == null) return;

    // Update other user info from conversation
    final otherInfo =
        event.conversation!.getOtherParticipantInfo(state.currentUserId ?? '');

    emit(state.copyWith(
      conversation: event.conversation,
      otherUserName: otherInfo?.displayName ?? state.otherUserName,
      otherUserPhotoUrl: otherInfo?.photoUrl ?? state.otherUserPhotoUrl,
    ));
  }

  void _onTypingUpdated(
    _ChatTypingUpdated event,
    Emitter<ChatState> emit,
  ) {
    emit(state.copyWith(isOtherUserTyping: event.isOtherUserTyping));
  }

  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    await _conversationSubscription?.cancel();
    await _typingSubscription?.cancel();
    _messagesSubscription = null;
    _conversationSubscription = null;
    _typingSubscription = null;
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    _typingDebounce?.cancel();
    return super.close();
  }
}
