import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../data/chat_cache_service.dart';
import '../../data/chat_service.dart';
import '../../data/media_upload_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// BLoC for managing a single chat conversation.
///
/// CRITICAL: This is a singleton BLoC shared across navigation.
/// Subscriptions are managed carefully to ensure messages are always received:
/// - Subscriptions are created on ChatOpen
/// - Subscriptions are cancelled on ChatClose (when user leaves chat)
/// - ChatResync resubscribes without full reload (for app resume/reconnect)
/// - _hasActiveSubscriptions tracks actual subscription state
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatService _chatService;
  final MediaUploadService _mediaUploadService;
  final ChatCacheService _cacheService;
  final Logger _logger = Logger();

  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Conversation?>? _conversationSubscription;
  StreamSubscription<bool>? _typingSubscription;

  Timer? _typingDebounce;

  /// CRITICAL: Track if subscriptions are actually active.
  /// This prevents the bug where state.status == loaded but subscriptions are null.
  bool _hasActiveSubscriptions = false;

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
    on<ChatPreload>(_onPreload);
    on<ChatSetTyping>(_onSetTyping);
    on<ChatDeleteMessage>(_onDeleteMessage);
    on<ChatClear>(_onClear);
    on<_ChatMessagesUpdated>(_onMessagesUpdated);
    on<_ChatConversationUpdated>(_onConversationUpdated);
    on<_ChatTypingUpdated>(_onTypingUpdated);
    on<_ChatErrorOccurred>(_onErrorOccurred);
  }

  /// Whether the bloc has active Firestore subscriptions.
  /// Used by UI to determine if resync is needed on app resume.
  bool get hasActiveSubscriptions => _hasActiveSubscriptions;

  Future<void> _onOpen(
    ChatOpen event,
    Emitter<ChatState> emit,
  ) async {
    // CRITICAL FIX: Check BOTH state AND actual subscription status.
    // Previously, this only checked state.status which could be 'loaded' even
    // when subscriptions were cancelled by ChatClose. This caused messages
    // sent while user was away to never be received.
    final bool isSameConversation = state.conversationId == event.conversationId &&
        state.currentUserId == event.currentUserId;
    final bool isAlreadyLoaded = state.status == ChatStatus.loaded || 
        state.status == ChatStatus.loadingMore;
    
    // OPTIMIZATION: Only skip full reload if we have ACTIVE subscriptions
    if (isSameConversation && isAlreadyLoaded && _hasActiveSubscriptions) {
      _logger.i('Chat already loaded with active streams for ${event.conversationId}, skipping reload');
      
      // Just update user info if changed (photo/name updates)
      if (state.otherUserName != event.otherUserName ||
          state.otherUserPhotoUrl != event.otherUserPhotoUrl) {
        emit(state.copyWith(
          otherUserName: event.otherUserName,
          otherUserPhotoUrl: event.otherUserPhotoUrl,
        ));
      }
      
      return;
    }
    
    // CRITICAL: If same conversation but no active subscriptions, we need to resubscribe!
    // This happens when user left and returned to the same chat.
    if (isSameConversation && isAlreadyLoaded && !_hasActiveSubscriptions) {
      _logger.i('Same conversation ${event.conversationId} but subscriptions inactive, resubscribing...');
      // Don't reset state - keep cached messages visible, just resubscribe
      await _subscribeToStreams(event);
      return;
    }
    
    // If switching conversations, immediately update user details and cancel subscriptions
    // This prevents briefly showing the previous user's name/photo
    if (state.conversationId != null && 
        state.conversationId != event.conversationId) {
      _logger.i('Switching from conversation ${state.conversationId} to ${event.conversationId}');
      
      // CRITICAL: Immediately update to new user details to prevent visual glitch
      emit(state.copyWith(
        status: ChatStatus.loading,
        conversationId: event.conversationId,
        currentUserId: event.currentUserId,
        otherUserId: event.otherUserId,
        otherUserName: event.otherUserName,
        otherUserPhotoUrl: event.otherUserPhotoUrl,
        messages: const [],
        pendingMessages: const {},
        conversation: null,
        isOtherUserTyping: false,
      ));
      
      await _cancelSubscriptions();
    }

    // ========================================================================
    // CRITICAL: Load cached messages IMMEDIATELY for instant display
    // This is the key to WhatsApp/Telegram-level performance
    // ========================================================================
    final cachedMessages = _cacheService.getMessages(event.conversationId);
    final hasCache = cachedMessages.isNotEmpty;
    final cachedEntry = _cacheService.getCache(event.conversationId);
    
    // Check if cache is expired (TTL-based)
    // We still show expired cache for instant display, but will refresh via stream
    final isExpired = _cacheService.isCacheExpired(event.conversationId);
    if (isExpired && hasCache) {
      _logger.d('Cache expired for ${event.conversationId}, will refresh via stream');
    }

    if (hasCache) {
      // INSTANT DISPLAY: Show cached messages immediately, no loading spinner
      _logger.i('Cache hit for ${event.conversationId}: ${cachedMessages.length} messages (expired: $isExpired)');
      emit(state.copyWith(
        status: ChatStatus.loaded, // Already loaded from cache!
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
      // No cache - show loading (first time opening this chat)
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

    // Cancel existing subscriptions (safety - may already be cancelled above)
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
        // Use retry logic with exponential backoff for reliability on slow networks
        Conversation? conversation;
        int retryCount = 0;
        const maxRetries = 3;
        
        while (conversation == null && retryCount < maxRetries) {
          if (retryCount > 0) {
            // Exponential backoff: 300ms, 600ms, 1200ms
            final delay = Duration(milliseconds: 300 * (1 << (retryCount - 1)));
            _logger.d('Retrying conversation verification (attempt ${retryCount + 1}/$maxRetries) after ${delay.inMilliseconds}ms');
            await Future.delayed(delay);
          } else {
            // Initial delay of 800ms for first attempt (increased from 500ms)
            // This gives Firestore more time to propagate the write
            await Future.delayed(const Duration(milliseconds: 800));
          }
          
          try {
            conversation = await _chatService.getConversation(event.conversationId);
            if (conversation != null) {
              _logger.i('Conversation verified successfully on attempt ${retryCount + 1}');
            }
          } catch (e) {
            _logger.w('Failed to verify conversation (attempt ${retryCount + 1}/$maxRetries): $e');
            if (retryCount == maxRetries - 1) {
              rethrow; // Re-throw on final attempt
            }
          }
          retryCount++;
        }
        
        if (conversation == null) {
          throw const DatabaseException(
            message: 'Conversation not found after creation and retries',
            code: 'conversation-not-found',
          );
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

    // CRITICAL: Use centralized subscription method to ensure _hasActiveSubscriptions is set
    await _subscribeToStreams(event);

    // NOTE: Don't emit ChatStatus.loaded here!
    // Let _onMessagesUpdated set the status to loaded when first snapshot arrives.
    // This prevents the "No messages yet" flash before messages load.
    _logger.i('Chat streams subscribed, waiting for first message snapshot...');
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

    // IMPORTANT: Don't clear the state here!
    // Preserve messages in cache so that reopening the same chat is instant.
    // The state will be refreshed when ChatOpen is called for the same or different conversation.
    // Only clear typing status and unread divider to prevent stale indicators.
    emit(state.copyWith(
      isOtherUserTyping: false,
      clearFirstUnreadMessageId: true,
    ));
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
    final allMessages = [...olderMessages, ...state.messages];

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

  /// Preload chat messages into cache without subscribing to streams.
  /// This is triggered on long-press of a conversation tile to warm the cache
  /// before navigation, making the chat open instantly even on cache miss.
  Future<void> _onPreload(
    ChatPreload event,
    Emitter<ChatState> emit,
  ) async {
    // Skip if already cached with valid TTL
    if (_cacheService.hasValidCache(
      event.conversationId,
      ttl: ChatCacheService.defaultTtl,
    )) {
      _logger.d('Preload skipped: ${event.conversationId} already cached');
      return;
    }

    // Skip if this is the currently open conversation
    if (state.conversationId == event.conversationId) {
      _logger.d('Preload skipped: ${event.conversationId} is currently open');
      return;
    }

    _logger.i('Preloading messages for ${event.conversationId}');

    try {
      // Fetch initial batch of messages (one-time read, no stream)
      final snapshot = await _chatService.getMessagesOnce(event.conversationId);

      if (snapshot.isNotEmpty) {
        // Warm the cache with these messages (mark as preload for TTL tracking)
        _cacheService.updateCache(
          conversationId: event.conversationId,
          messages: snapshot,
          hasMore: snapshot.length >= 50,
          isPreload: true,
        );
        _logger.i('Preloaded ${snapshot.length} messages for ${event.conversationId}');
      }
    } catch (e) {
      // Preload failures are silent - don't affect UX
      _logger.d('Preload failed for ${event.conversationId}: $e');
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
      messages: event.messages,
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
  /// CRITICAL: Also sets _hasActiveSubscriptions = false to track state properly.
  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    await _conversationSubscription?.cancel();
    await _typingSubscription?.cancel();
    _messagesSubscription = null;
    _conversationSubscription = null;
    _typingSubscription = null;
    _hasActiveSubscriptions = false;
    _logger.d('Subscriptions cancelled, _hasActiveSubscriptions = false');
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

    // Subscribe to messages stream with better error handling
    _messagesSubscription =
        _chatService.getMessagesStream(event.conversationId).listen(
              (messages) {
                if (!isClosed) {
                  add(_ChatMessagesUpdated(messages));
                }
              },
              onError: (error) {
                _logger.e('Messages stream error: $error');
                _hasActiveSubscriptions = false;
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

    // CRITICAL: Mark subscriptions as active
    _hasActiveSubscriptions = true;
    _logger.i('Subscriptions created, _hasActiveSubscriptions = true');

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
    return super.close();
  }
}
