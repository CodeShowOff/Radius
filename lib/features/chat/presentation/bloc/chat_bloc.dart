import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../data/chat_service.dart';
import '../../data/media_upload_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// BLoC for managing a single chat conversation.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatService _chatService;
  final MediaUploadService _mediaUploadService;
  final Logger _logger = Logger();

  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Conversation?>? _conversationSubscription;
  StreamSubscription<bool>? _typingSubscription;

  Timer? _typingDebounce;

  ChatBloc({
    required ChatService chatService,
    required MediaUploadService mediaUploadService,
  })  : _chatService = chatService,
        _mediaUploadService = mediaUploadService,
        super(const ChatState()) {
    on<ChatOpen>(_onOpen);
    on<ChatClose>(_onClose);
    on<ChatSendMessage>(_onSendMessage);
    on<ChatRetryMessage>(_onRetryMessage);
    on<ChatSendImage>(_onSendImage);
    on<ChatSendAudio>(_onSendAudio);
    on<ChatSendDocument>(_onSendDocument);
    on<ChatSendSticker>(_onSendSticker);
    on<ChatLoadMore>(_onLoadMore);
    on<ChatMarkAsRead>(_onMarkAsRead);
    on<ChatSetTyping>(_onSetTyping);
    on<ChatDeleteMessage>(_onDeleteMessage);
    on<ChatClear>(_onClear);
    on<_ChatMessagesUpdated>(_onMessagesUpdated);
    on<_ChatConversationUpdated>(_onConversationUpdated);
    on<_ChatTypingUpdated>(_onTypingUpdated);
    on<_ChatErrorOccurred>(_onErrorOccurred);
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

    // Ensure the conversation exists before subscribing.
    // If it doesn't exist yet (common when opening chat from Connections),
    // Firestore will deny reading a non-existent doc under our rules.
    if (event.currentUserId.trim().isNotEmpty &&
        event.otherUserId.trim().isNotEmpty) {
      try {
        await _chatService.getOrCreateConversation(
          currentUserId: event.currentUserId,
          otherUserId: event.otherUserId,
          currentUserName: (event.currentUserName?.trim().isNotEmpty == true)
              ? event.currentUserName!.trim()
              : 'Unknown',
          otherUserName: (event.otherUserName?.trim().isNotEmpty == true)
              ? event.otherUserName!.trim()
              : 'User',
          currentUserPhotoUrl: (event.currentUserPhotoUrl?.trim().isNotEmpty ==
                  true)
              ? event.currentUserPhotoUrl!.trim()
              : null,
          otherUserPhotoUrl: (event.otherUserPhotoUrl?.trim().isNotEmpty ==
                  true)
              ? event.otherUserPhotoUrl!.trim()
              : null,
        );
        
        // Delay to ensure Firestore propagates the conversation write
        // This prevents race conditions with security rules checking conversation existence
        // Increased to 200ms for better reliability on slow networks
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Verify conversation is readable before subscribing
        final conversation = await _chatService.getConversation(event.conversationId);
        if (conversation == null) {
          throw const DatabaseException(
            message: 'Conversation not found after creation',
            code: 'conversation-not-found',
          );
        }
      } catch (e) {
        emit(state.copyWith(
          status: ChatStatus.error,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    // Subscribe to messages stream
    _messagesSubscription =
        _chatService.getMessagesStream(event.conversationId).listen(
              (messages) => add(_ChatMessagesUpdated(messages)),
              onError: (error) => add(_ChatErrorOccurred(error.toString())),
            );

    // Subscribe to conversation updates
    _conversationSubscription =
        _chatService.getConversationStream(event.conversationId).listen(
              (conversation) => add(_ChatConversationUpdated(conversation)),
              onError: (error) => add(_ChatErrorOccurred(error.toString())),
            );

    // Subscribe to typing indicator when we know the other participant.
    // Deep links may open a chat without extra payload, so otherUserId can be
    // empty until the conversation stream yields participant data.
    if (event.otherUserId.trim().isNotEmpty) {
      _typingSubscription = _chatService
          .getTypingStream(event.conversationId, event.otherUserId)
          .listen(
            (isTyping) => add(_ChatTypingUpdated(isTyping)),
            onError: (error) => add(_ChatErrorOccurred(error.toString())),
          );
    }

    // Mark messages as delivered AND read when opening chat
    // This clears badges immediately (WhatsApp behavior)
    // Don't let this block the chat from opening
    _chatService.markMessagesAsDelivered(
      conversationId: event.conversationId,
      userId: event.currentUserId,
    ).catchError((e) {
      _logger.d('Failed to mark messages as delivered: $e');
    });

    // Mark as read immediately to clear badges everywhere
    _chatService.markMessagesAsRead(
      conversationId: event.conversationId,
      userId: event.currentUserId,
    ).catchError((e) {
      _logger.d('Failed to mark messages as read: $e');
    });

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

    try {
      // Send message - service returns optimistic message
      final sentMessage = await _chatService.sendMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        text: event.text,
        recipientId: state.otherUserId,
      );

      // Only add to pending if it failed (needs retry)
      if (sentMessage.status == MessageStatus.failed) {
        final pending = Map<String, Message>.from(state.pendingMessages);
        pending[sentMessage.localId ?? sentMessage.id] = sentMessage;
        emit(state.copyWith(pendingMessages: pending));
      }

      // The Firestore stream will automatically update with the real message
      // and _onMessagesUpdated will remove it from pending
    } catch (e) {
      _logger.e('Error sending message', error: e);
      emit(state.copyWith(
        errorMessage: 'Failed to send message: $e',
      ));
    }
  }

  Future<void> _onRetryMessage(
    ChatRetryMessage event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    final failedMessage = event.message;

    // Remove from pending
    final pending = Map<String, Message>.from(state.pendingMessages);
    pending.remove(failedMessage.localId ?? failedMessage.id);
    emit(state.copyWith(pendingMessages: pending));

    try {
      // Retry sending based on message type
      late Message sentMessage;

      if (failedMessage.isMediaMessage) {
        // For media messages, we can't retry from the failed message alone
        // since we don't have the file anymore
        emit(state.copyWith(
          errorMessage: 'Cannot retry media messages. Please send again.',
        ));
        return;
      } else {
        // Retry text message
        sentMessage = await _chatService.sendMessage(
          conversationId: state.conversationId!,
          senderId: state.currentUserId!,
          text: failedMessage.text,
          recipientId: state.otherUserId,
        );
      }

      // If it failed again, add back to pending
      if (sentMessage.status == MessageStatus.failed) {
        final updatedPending = Map<String, Message>.from(state.pendingMessages);
        updatedPending[sentMessage.localId ?? sentMessage.id] = sentMessage;
        emit(state.copyWith(pendingMessages: updatedPending));
      }
    } catch (e) {
      _logger.e('Error retrying message', error: e);
      // Add back to pending on error
      final updatedPending = Map<String, Message>.from(state.pendingMessages);
      updatedPending[failedMessage.localId ?? failedMessage.id] = failedMessage;
      emit(state.copyWith(
        pendingMessages: updatedPending,
        errorMessage: 'Failed to retry message: $e',
      ));
    }
  }

  Future<void> _onSendImage(
    ChatSendImage event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    // Check if media uploads are enabled
    if (!AppConstants.enableMediaUploads) {
      emit(state.copyWith(
        errorMessage:
            '📷 Photo sharing will be available very soon! We\'re setting up our servers.',
      ));
      return;
    }

    try {
      // Upload image
      final uploadResult = await _mediaUploadService.uploadImage(
        file: event.file,
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        onProgress: (progress) {
          // Could emit progress updates here if needed
        },
      );

      // Send media message
      await _chatService.sendMediaMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        type: MessageType.image,
        mediaUrl: uploadResult.downloadUrl,
        mediaFileName: uploadResult.fileName,
        mediaFileSize: uploadResult.fileSize,
        text: event.caption ?? '',
        recipientId: state.otherUserId,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to send image: $e'));
    }
  }

  Future<void> _onSendAudio(
    ChatSendAudio event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    // Check if media uploads are enabled
    if (!AppConstants.enableMediaUploads) {
      emit(state.copyWith(
        errorMessage:
            '🎤 Voice messages will be available very soon! We\'re setting up our servers.',
      ));
      return;
    }

    try {
      // Upload audio
      final uploadResult = await _mediaUploadService.uploadAudio(
        file: event.file,
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        duration: event.duration,
        onProgress: (progress) {
          // Could emit progress updates here if needed
        },
      );

      // Send media message
      await _chatService.sendMediaMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        type: MessageType.audio,
        mediaUrl: uploadResult.downloadUrl,
        mediaFileName: uploadResult.fileName,
        mediaFileSize: uploadResult.fileSize,
        duration: event.duration,
        recipientId: state.otherUserId,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to send voice message: $e'));
    }
  }

  Future<void> _onSendDocument(
    ChatSendDocument event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    // Check if media uploads are enabled
    if (!AppConstants.enableMediaUploads) {
      emit(state.copyWith(
        errorMessage:
            '📄 Document sharing will be available very soon! We\'re setting up our servers.',
      ));
      return;
    }

    try {
      // Upload document
      final uploadResult = await _mediaUploadService.uploadDocument(
        file: event.file,
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        onProgress: (progress) {
          // Could emit progress updates here if needed
        },
      );

      // Send media message
      await _chatService.sendMediaMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        type: MessageType.document,
        mediaUrl: uploadResult.downloadUrl,
        mediaFileName: uploadResult.fileName,
        mediaFileSize: uploadResult.fileSize,
        text: event.caption ?? '',
        recipientId: state.otherUserId,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to send document: $e'));
    }
  }

  Future<void> _onSendSticker(
    ChatSendSticker event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    // Check if media uploads are enabled
    if (!AppConstants.enableMediaUploads) {
      emit(state.copyWith(
        errorMessage:
            '😊 Stickers will be available very soon! We\'re setting up our servers.',
      ));
      return;
    }

    try {
      // Upload sticker
      final uploadResult = await _mediaUploadService.uploadSticker(
        file: event.file,
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        onProgress: (progress) {
          // Could emit progress updates here if needed
        },
      );

      // Send media message
      await _chatService.sendMediaMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        type: MessageType.sticker,
        mediaUrl: uploadResult.downloadUrl,
        mediaFileName: uploadResult.fileName,
        mediaFileSize: uploadResult.fileSize,
        recipientId: state.otherUserId,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to send sticker: $e'));
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

    List<Message> olderMessages;
    try {
      olderMessages = await _chatService.loadMoreMessages(
        state.conversationId!,
        before: oldestTime,
      );
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.loaded,
        errorMessage: e.toString(),
      ));
      return;
    }

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

    try {
      await _chatService.markMessagesAsRead(
        conversationId: state.conversationId!,
        userId: state.currentUserId!,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
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

    try {
      await _chatService.deleteMessage(
        conversationId: state.conversationId!,
        messageId: event.messageId,
        userId: state.currentUserId!,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onClear(
    ChatClear event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      return;
    }

    try {
      await _chatService.clearMessages(
        state.conversationId!,
        state.currentUserId!,
      );
      // Messages will be updated through the stream
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to clear chat: ${e.toString()}',
      ));
    }
  }

  void _onMessagesUpdated(
    _ChatMessagesUpdated event,
    Emitter<ChatState> emit,
  ) {
    const pageSize = 50;
    // Remove confirmed messages from pending
    final pending = Map<String, Message>.from(state.pendingMessages);

    for (final message in event.messages) {
      // Remove from pending by ID match or by localId match
      pending.removeWhere((key, pendingMsg) {
        // Direct ID match
        if (key == message.id) return true;
        
        // LocalId match (message from Firestore has the localId we set)
        if (pendingMsg.localId != null && message.localId == pendingMsg.localId) {
          return true;
        }
        
        // Fuzzy match: same sender, same text, sent within 5 seconds
        final isSameSender = pendingMsg.senderId == message.senderId;
        final isSameText = pendingMsg.text == message.text;
        final sentWithin5Seconds = 
            message.sentAt.difference(pendingMsg.sentAt).abs().inSeconds < 5;
        
        return isSameSender && isSameText && sentWithin5Seconds;
      });
    }

    // Ensure status is loaded when messages are received
    emit(state.copyWith(
      status: ChatStatus.loaded,
      messages: event.messages,
      hasMore: event.messages.length >= pageSize,
      pendingMessages: pending,
    ));
  }

  void _onConversationUpdated(
    _ChatConversationUpdated event,
    Emitter<ChatState> emit,
  ) {
    if (event.conversation == null) return;

    final currentUserId = state.currentUserId ?? '';
    final derivedOtherUserId =
        event.conversation!.getOtherParticipantId(currentUserId);

    // If the chat was opened without an explicit otherUserId, derive it now
    // and wire typing updates.
    final needsOtherUserId =
        (state.otherUserId == null || state.otherUserId!.trim().isEmpty) &&
            derivedOtherUserId.trim().isNotEmpty;

    if (needsOtherUserId) {
      _typingSubscription?.cancel();
      _typingSubscription = _chatService
          .getTypingStream(state.conversationId!, derivedOtherUserId)
          .listen(
            (isTyping) => add(_ChatTypingUpdated(isTyping)),
            onError: (error) => add(_ChatErrorOccurred(error.toString())),
          );
    }

    // Update other user info from conversation
    final otherInfo =
        event.conversation!.getOtherParticipantInfo(currentUserId);

    emit(state.copyWith(
      conversation: event.conversation,
      otherUserId: needsOtherUserId ? derivedOtherUserId : state.otherUserId,
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

  void _onErrorOccurred(
    _ChatErrorOccurred event,
    Emitter<ChatState> emit,
  ) {
    emit(state.copyWith(
      status: ChatStatus.error,
      errorMessage: event.message,
    ));
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
