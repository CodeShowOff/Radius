import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/chat_cache_service.dart';
import '../../data/chat_service.dart';
import '../../data/media_upload_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// BLoC for managing a single chat conversation.
///
/// Each chat screen gets its own ChatBloc instance (factory via DI).
/// This eliminates singleton race conditions when switching conversations.
/// Instant display is provided by the singleton ChatCacheService.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatService _chatService;
  final MediaUploadService _mediaUploadService;
  final ChatCacheService _cacheService;
  final Logger _logger = Logger();

  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Conversation?>? _conversationSubscription;
  StreamSubscription<bool>? _typingSubscription;

  Timer? _typingDebounce;

  /// The user's lastReadAt timestamp captured BEFORE marking conversation as read.
  /// Used to compute firstUnreadMessageId client-side.
  DateTime? _lastReadBeforeOpen;

  /// Whether we've already computed firstUnreadMessageId for the current session.
  /// Prevents recomputation on subsequent stream updates.
  bool _firstUnreadComputed = false;

  ChatBloc({
    required ChatService chatService,
    required MediaUploadService mediaUploadService,
    required ChatCacheService cacheService,
  })  : _chatService = chatService,
        _mediaUploadService = mediaUploadService,
        _cacheService = cacheService,
        super(const ChatState()) {
    on<ChatOpen>(_onOpen);
    on<ChatClose>(_onClose);
    on<ChatResync>(_onResync);
    on<ChatSendMessage>(_onSendMessage);
    on<ChatRetryMessage>(_onRetryMessage);
    on<ChatSendImage>(_onSendImage);
    on<ChatSendAudio>(_onSendAudio);
    on<ChatSendDocument>(_onSendDocument);
    on<ChatSendSticker>(_onSendSticker);
    on<ChatLoadMore>(_onLoadMore);
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
    // ========================================================================
    // Load cached messages IMMEDIATELY for instant display.
    // ChatCacheService is a singleton so cache persists across screen instances.
    // ========================================================================
    final cachedMessages = _cacheService.getMessages(event.conversationId);
    final hasCache = cachedMessages.isNotEmpty;
    final cachedEntry = _cacheService.getCache(event.conversationId);

    if (hasCache) {
      _logger.i('Cache hit for ${event.conversationId}: ${cachedMessages.length} messages');
      emit(state.copyWith(
        status: ChatStatus.loaded,
        conversationId: event.conversationId,
        currentUserId: event.currentUserId,
        otherUserId: event.otherUserId,
        otherUserName: event.otherUserName,
        otherUserPhotoUrl: event.otherUserPhotoUrl,
        messages: cachedMessages,
        hasMore: cachedEntry?.hasMore ?? true,
        pendingMessages: const {},
      ));
    } else {
      _logger.i('Cache miss for ${event.conversationId}, showing loading');
      emit(state.copyWith(
        status: ChatStatus.loading,
        conversationId: event.conversationId,
        currentUserId: event.currentUserId,
        otherUserId: event.otherUserId,
        otherUserName: event.otherUserName,
        otherUserPhotoUrl: event.otherUserPhotoUrl,
        messages: const [],
        pendingMessages: const {},
      ));
    }

    // Ensure the conversation doc exists before subscribing.
    // Skip when cache exists — a cache hit means the doc already exists.
    if (!hasCache &&
        event.currentUserId.trim().isNotEmpty &&
        event.otherUserId.trim().isNotEmpty) {
      try {
        final createdConversation = await _chatService.getOrCreateConversation(
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

        if (createdConversation.lastMessageAt == null) {
          _logger.d('New conversation created, brief delay for Firestore propagation');
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        _logger.e('Failed to open conversation: $e');
        emit(state.copyWith(
          status: ChatStatus.error,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    // Subscribe to real-time streams
    await _subscribeToStreams(event);
    _logger.i('Chat streams subscribed for ${event.conversationId}');
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
    _chatService.setTyping(
      conversationId: state.conversationId!,
      userId: state.currentUserId!,
      isTyping: false,
    ).catchError((e) => _logger.d('Failed to clear typing: $e'));

    // ========================================================================
    // OPTIMISTIC UI: Create and display message IMMEDIATELY
    // This is the industry-standard pattern used by WhatsApp, Telegram, Slack
    // ========================================================================
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimisticMessage = Message(
      id: localId,
      conversationId: state.conversationId!,
      senderId: state.currentUserId!,
      text: event.text.trim(),
      sentAt: DateTime.now(),
      localId: localId,
    );

    // Add to pending messages IMMEDIATELY - UI will show it right away
    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: pending));

    // ========================================================================
    // SEND TO SERVER: Now actually send the message
    // ========================================================================
    try {
      await _chatService.sendMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        text: event.text,
        recipientId: state.otherUserId,
        localId: localId, // Pass localId so Firestore message matches pending
      );

      // Message sent successfully
      // The Firestore stream will update the UI when the message arrives
    } catch (e) {
      _logger.e('Error sending message', error: e);
      // Keep the pending message as is - user can retry
      emit(state.copyWith(
        errorMessage: 'Failed to send message',
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

      if (failedMessage.isMediaMessage) {
        // For media messages, we can't retry from the failed message alone
        // since we don't have the file anymore
        emit(state.copyWith(
          errorMessage: 'Cannot retry media messages. Please send again.',
        ));
        return;
      } else {
        // Retry text message
        await _chatService.sendMessage(
          conversationId: state.conversationId!,
          senderId: state.currentUserId!,
          text: failedMessage.text,
          recipientId: state.otherUserId,
        );
      }

      // Message sent successfully - will be updated by stream
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

    final hasMore = olderMessages.length >= 50;
    // Messages are sorted descending (newest first).
    // Older messages must go at the END (higher indices = older).
    final allMessages = [...state.messages, ...olderMessages];

    // Update the cache with paginated messages
    _cacheService.addPaginatedMessages(
      conversationId: state.conversationId!,
      olderMessages: olderMessages,
      hasMore: hasMore,
    );

    emit(state.copyWith(
      status: ChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
    ));
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

    // ========================================================================
    // CRITICAL: Update the global cache with new messages
    // This enables instant display when returning to this chat later
    // ========================================================================
    if (state.conversationId != null) {
      _cacheService.updateCache(
        conversationId: state.conversationId!,
        messages: event.messages,
        hasMore: event.messages.length >= pageSize,
      );
    }

    // ========================================================================
    // Preserve paginated (older) messages that aren't in the stream's range.
    // The stream only returns the latest page (e.g., 50 messages). If the user
    // loaded more via pagination, those older messages would be lost without
    // this merge. We keep older messages that predate the stream's oldest.
    // ========================================================================
    List<Message> mergedMessages = event.messages;
    if (state.messages.length > event.messages.length) {
      final streamMessageIds = event.messages.map((m) => m.id).toSet();
      final oldestInStream = event.messages.isNotEmpty
          ? event.messages.last.sentAt
          : DateTime.now();
      final olderFromState = state.messages
          .where((m) =>
              !streamMessageIds.contains(m.id) &&
              m.sentAt.isBefore(oldestInStream))
          .toList();
      if (olderFromState.isNotEmpty) {
        mergedMessages = [...event.messages, ...olderFromState];
      }
    }

    // ========================================================================
    // Compute first unread message ID on initial message arrival.
    // This enables the "unread messages" divider and scroll-to-unread.
    // Only computed once per chat session (before markConversationAsRead fires).
    // ========================================================================
    String? computedFirstUnreadId;
    int computedUnreadCount = 0;
    if (!_firstUnreadComputed &&
        state.currentUserId != null &&
        event.messages.isNotEmpty) {
      _firstUnreadComputed = true;

      if (_lastReadBeforeOpen != null) {
        // Find oldest message from other user sent after lastReadAt.
        // Messages are sorted descending (newest first), so iterate from end.
        for (int i = event.messages.length - 1; i >= 0; i--) {
          final msg = event.messages[i];
          if (msg.senderId != state.currentUserId &&
              msg.sentAt.isAfter(_lastReadBeforeOpen!)) {
            computedFirstUnreadId = msg.id;
            break;
          }
        }
        // Count all unread messages from other user after lastReadAt
        if (computedFirstUnreadId != null) {
          for (final msg in event.messages) {
            if (msg.senderId != state.currentUserId &&
                msg.sentAt.isAfter(_lastReadBeforeOpen!)) {
              computedUnreadCount++;
            }
          }
        }
      } else {
        // No lastReadAt means user never read this chat.
        // Find oldest message from the other user (all are unread).
        for (int i = event.messages.length - 1; i >= 0; i--) {
          final msg = event.messages[i];
          if (msg.senderId != state.currentUserId) {
            computedFirstUnreadId = msg.id;
            break;
          }
        }
        // Count all messages from other user
        if (computedFirstUnreadId != null) {
          for (final msg in event.messages) {
            if (msg.senderId != state.currentUserId) {
              computedUnreadCount++;
            }
          }
        }
      }
    }

    // Ensure status is loaded when messages are received.
    // computedFirstUnreadId is null on subsequent calls, which preserves
    // the existing firstUnreadMessageId via copyWith semantics.
    final previousLatestId =
        state.messages.isNotEmpty ? state.messages.first.id : null;
    final conversationId = state.conversationId;
    final currentUserId = state.currentUserId;

    emit(state.copyWith(
      status: ChatStatus.loaded,
      messages: mergedMessages,
      hasMore: event.messages.length >= pageSize,
      pendingMessages: pending,
      firstUnreadMessageId: computedFirstUnreadId,
      unreadCountAtOpen: computedFirstUnreadId != null ? computedUnreadCount : null,
    ));

    // ========================================================================
    // CRITICAL FIX: Re-mark conversation as read when new messages arrive
    // from the other user while the chat is open.
    //
    // sendMessage() does FieldValue.increment(1) on unreadCounts.$recipientId.
    // Without this, the ConversationsBloc stream picks up the increment and
    // the nav badge incorrectly shows unread for the conversation being viewed.
    // This resets unreadCounts to 0 in Firestore so the stream corrects itself.
    // The write is idempotent (sets to 0) so redundant calls are harmless.
    // ========================================================================
    if (conversationId != null &&
        currentUserId != null &&
        event.messages.isNotEmpty) {
      final newLatest = event.messages.first;
      final isNewMessage = newLatest.id != previousLatestId;
      final isFromOtherUser = newLatest.senderId != currentUserId;

      if (isNewMessage && isFromOtherUser) {
        _chatService.markConversationAsRead(
          conversationId: conversationId,
          userId: currentUserId,
        );
      }
    }
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
            (isTyping) {
              if (!isClosed) {
                add(_ChatTypingUpdated(isTyping));
              }
            },
            onError: (error) {
              if (!isClosed) {
                add(_ChatErrorOccurred(error.toString()));
              }
            },
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

  /// Cancels all Firestore stream subscriptions.
  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    await _conversationSubscription?.cancel();
    await _typingSubscription?.cancel();
    _messagesSubscription = null;
    _conversationSubscription = null;
    _typingSubscription = null;
  }

  /// Subscribes to Firestore streams for the current conversation.
  /// This is extracted to allow resubscription without full state reset.
  /// [isResync] skips fetching lastReadAt to avoid recomputing the unread divider
  /// on app resume / network reconnect.
  Future<void> _subscribeToStreams(ChatOpen event, {bool isResync = false}) async {
    // Cancel any existing subscriptions first
    await _cancelSubscriptions();

    // Fetch lastReadAt BEFORE subscribing to streams and marking as read.
    // This is needed to compute the first unread message ID client-side.
    // Skip on resync since the user is already in the chat.
    if (!isResync) {
      _firstUnreadComputed = false;
      try {
        final conv = await _chatService.getConversation(event.conversationId);
        _lastReadBeforeOpen = conv?.getLastReadAt(event.currentUserId);
      } catch (_) {
        _lastReadBeforeOpen = null;
      }
    }

    // Subscribe to messages stream
    _messagesSubscription =
        _chatService.getMessagesStream(event.conversationId).listen(
              (messages) {
                if (!isClosed) {
                  add(_ChatMessagesUpdated(messages));
                }
              },
              onError: (error) {
                _logger.e('Messages stream error: $error');
                if (!isClosed) {
                  String errorMessage = error.toString();
                  if (errorMessage.contains('permission-denied') || 
                      errorMessage.contains('PERMISSION_DENIED')) {
                    errorMessage = 'Unable to access messages. The conversation may still be initializing. Please wait a moment and try again.';
                  }
                  add(_ChatErrorOccurred(errorMessage));
                }
              },
            );

    // Subscribe to conversation updates
    _conversationSubscription =
        _chatService.getConversationStream(event.conversationId).listen(
              (conversation) {
                if (!isClosed) {
                  add(_ChatConversationUpdated(conversation));
                }
              },
              onError: (error) {
                if (!isClosed) {
                  add(_ChatErrorOccurred(error.toString()));
                }
              },
            );

    // Subscribe to typing indicator when we know the other participant
    if (event.otherUserId.trim().isNotEmpty) {
      _typingSubscription = _chatService
          .getTypingStream(event.conversationId, event.otherUserId)
          .listen(
            (isTyping) {
              if (!isClosed) {
                add(_ChatTypingUpdated(isTyping));
              }
            },
            onError: (error) {
              if (!isClosed) {
                add(_ChatErrorOccurred(error.toString()));
              }
            },
          );
    }

    // Mark subscriptions as active
    _logger.i('Subscriptions created for ${event.conversationId}');

    // Mark conversation as read after a brief delay to ensure messages are loaded
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!isClosed && state.conversationId == event.conversationId) {
        _chatService.markConversationAsRead(
          conversationId: event.conversationId,
          userId: event.currentUserId,
        );
        _logger.d('Marked conversation as read: ${event.conversationId}');
      }
    });
  }

  /// Handle resync request (app resume, network reconnect).
  /// This resubscribes to streams without resetting state.
  Future<void> _onResync(
    ChatResync event,
    Emitter<ChatState> emit,
  ) async {
    if (state.conversationId == null || state.currentUserId == null) {
      _logger.d('Resync skipped: no active conversation');
      return;
    }

    _logger.i('Resync requested for ${state.conversationId}');

    // Create a ChatOpen event with current state info for resubscription
    final openEvent = ChatOpen(
      conversationId: state.conversationId!,
      currentUserId: state.currentUserId!,
      otherUserId: state.otherUserId ?? '',
      otherUserName: state.otherUserName,
      otherUserPhotoUrl: state.otherUserPhotoUrl,
    );

    // Cancel existing and resubscribe (skip unread computation on resync)
    await _subscribeToStreams(openEvent, isResync: true);
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    _typingDebounce?.cancel();
    // Clear typing indicator as a safety net
    if (state.conversationId != null && state.currentUserId != null) {
      _chatService.setTyping(
        conversationId: state.conversationId!,
        userId: state.currentUserId!,
        isTyping: false,
      ).catchError((_) {});
    }
    return super.close();
  }
}
