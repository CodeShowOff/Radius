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
import '../../data/message_retry_service.dart';
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
  final MessageRetryService _retryService;
  final Logger _logger = Logger();

  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Conversation?>? _conversationSubscription;
  StreamSubscription<bool>? _typingSubscription;

  Timer? _typingDebounce;

  /// Loading timeout: if the Firestore stream hasn't emitted within this
  /// duration after subscribing, we show an error with retry instead of
  /// keeping the user stuck on an infinite loading spinner.
  /// This mirrors v_chat_sdk's reconnect-and-refetch pattern.
  Timer? _loadingTimeoutTimer;
  static const Duration _loadingTimeout = Duration(seconds: 12);

  /// The user's lastReadAt timestamp captured BEFORE marking conversation as read.
  /// Used to compute firstUnreadMessageId client-side.
  DateTime? _lastReadBeforeOpen;

  /// Whether we've already computed firstUnreadMessageId for the current session.
  /// Prevents recomputation on subsequent stream updates.
  bool _firstUnreadComputed = false;

  /// Track the number of stream subscription retries for new conversations
  /// that may hit permission-denied before Firestore rules propagate.
  int _streamRetryCount = 0;
  static const int _maxStreamRetries = 2;

  ChatBloc({
    required ChatService chatService,
    required MediaUploadService mediaUploadService,
    required ChatCacheService cacheService,
    required MessageRetryService retryService,
  })  : _chatService = chatService,
        _mediaUploadService = mediaUploadService,
        _cacheService = cacheService,
        _retryService = retryService,
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
    on<_ChatMediaUploadProgress>(_onMediaUploadProgress);
    on<_ChatMediaUploadFailed>(_onMediaUploadFailed);
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

    // ========================================================================
    // STARTUP RECOVERY (v_chat_sdk `prepareMessages` pattern):
    // Recover any pending/error messages from previous session.
    // Messages stuck in "sending" are marked as "error" for manual retry.
    // ========================================================================
    final recoveredPending = _cacheService.recoverPendingMessages(event.conversationId);

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
        pendingMessages: recoveredPending,
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
        pendingMessages: recoveredPending,
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
    // Save pending messages to cache so they survive screen navigation.
    // This is the v_chat_sdk pattern: pending messages persist across sessions.
    if (state.conversationId != null && state.pendingMessages.isNotEmpty) {
      _cacheService.savePendingMessages(
        state.conversationId!,
        state.pendingMessages,
      );
    } else if (state.conversationId != null) {
      // All messages confirmed — clear pending cache
      _cacheService.clearPendingMessages(state.conversationId!);
    }

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
      status: MessageStatus.pending,
      sentAt: DateTime.now(),
      localId: localId,
    );

    // Add to pending messages IMMEDIATELY - UI will show it right away
    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: pending));

    // ========================================================================
    // SEND TO SERVER: Transition to 'sending' status
    // ========================================================================
    final sendingPending = Map<String, Message>.from(state.pendingMessages);
    sendingPending[localId] = optimisticMessage.copyWith(status: MessageStatus.sending);
    emit(state.copyWith(pendingMessages: sendingPending));

    try {
      await _chatService.sendMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        text: event.text,
        recipientId: state.otherUserId,
        localId: localId,
      );
      // Message sent successfully — Firestore stream will confirm & remove from pending
    } catch (e) {
      _logger.e('Error sending message', error: e);
      // Mark as error with reason — keeps message visible for manual retry
      final errorPending = Map<String, Message>.from(state.pendingMessages);
      errorPending[localId] = optimisticMessage.copyWith(
        status: MessageStatus.error,
        errorReason: 'Failed to send. Tap to retry.',
        retryCount: 1,
      );
      emit(state.copyWith(
        pendingMessages: errorPending,
        errorMessage: 'Failed to send message',
      ));

      // Enqueue for automatic retry
      _retryService.enqueueTextMessage(
        message: errorPending[localId]!,
        recipientId: state.otherUserId,
      );
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
    final localId = failedMessage.localId ?? failedMessage.id;

    // Cancel any automatic retry for this message
    _retryService.removeFromQueue(localId);

    if (failedMessage.isMediaMessage) {
      // Media messages can't be retried — user must re-send
      final pending = Map<String, Message>.from(state.pendingMessages);
      pending.remove(localId);
      emit(state.copyWith(
        pendingMessages: pending,
        errorMessage: 'Cannot retry media messages. Please send again.',
      ));
      return;
    }

    // Transition to 'sending' status
    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = failedMessage.copyWith(
      status: MessageStatus.sending,
      errorReason: null,
    );
    emit(state.copyWith(pendingMessages: pending));

    try {
      await _chatService.sendMessage(
        conversationId: state.conversationId!,
        senderId: state.currentUserId!,
        text: failedMessage.text,
        recipientId: state.otherUserId,
        localId: localId,
      );
      // Success — Firestore stream will confirm & remove from pending
    } catch (e) {
      _logger.e('Error retrying message', error: e);
      // Mark as error again with incremented retry count
      final errorPending = Map<String, Message>.from(state.pendingMessages);
      errorPending[localId] = failedMessage.copyWith(
        status: MessageStatus.error,
        errorReason: 'Retry failed. Tap to try again.',
        retryCount: failedMessage.retryCount + 1,
      );
      emit(state.copyWith(
        pendingMessages: errorPending,
        errorMessage: 'Failed to retry message',
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

    // Create optimistic pending message IMMEDIATELY for instant display
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimisticMessage = Message(
      id: localId,
      conversationId: state.conversationId!,
      senderId: state.currentUserId!,
      text: event.caption ?? '',
      type: MessageType.image,
      status: MessageStatus.pending,
      sentAt: DateTime.now(),
      localId: localId,
      uploadProgress: 0.0,
    );

    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: pending));

    // Capture state values before async operation
    final conversationId = state.conversationId!;
    final senderId = state.currentUserId!;
    final otherUserId = state.otherUserId;
    final caption = event.caption ?? '';

    // Fire-and-forget: start upload in background (doesn't block event queue)
    var lastReportedProgress = -1.0;
    unawaited(_performMediaUpload(
      localId: localId,
      conversationId: conversationId,
      senderId: senderId,
      otherUserId: otherUserId,
      type: MessageType.image,
      text: caption,
      upload: () => _mediaUploadService.uploadImage(
        file: event.file,
        conversationId: conversationId,
        senderId: senderId,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_ChatMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
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

    // Create optimistic pending message IMMEDIATELY for instant display
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimisticMessage = Message(
      id: localId,
      conversationId: state.conversationId!,
      senderId: state.currentUserId!,
      text: '',
      type: MessageType.audio,
      status: MessageStatus.pending,
      duration: event.duration,
      sentAt: DateTime.now(),
      localId: localId,
      uploadProgress: 0.0,
    );

    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: pending));

    // Capture state values before async operation
    final conversationId = state.conversationId!;
    final senderId = state.currentUserId!;
    final otherUserId = state.otherUserId;
    final duration = event.duration;

    // Fire-and-forget: start upload in background (doesn't block event queue)
    var lastReportedProgress = -1.0;
    unawaited(_performMediaUpload(
      localId: localId,
      conversationId: conversationId,
      senderId: senderId,
      otherUserId: otherUserId,
      type: MessageType.audio,
      duration: duration,
      upload: () => _mediaUploadService.uploadAudio(
        file: event.file,
        conversationId: conversationId,
        senderId: senderId,
        duration: duration,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_ChatMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
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

    // Create optimistic pending message IMMEDIATELY for instant display
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = event.file.path.split(Platform.pathSeparator).last;
    final optimisticMessage = Message(
      id: localId,
      conversationId: state.conversationId!,
      senderId: state.currentUserId!,
      text: event.caption ?? '',
      type: MessageType.document,
      status: MessageStatus.pending,
      mediaFileName: fileName,
      sentAt: DateTime.now(),
      localId: localId,
      uploadProgress: 0.0,
    );

    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: pending));

    // Capture state values before async operation
    final conversationId = state.conversationId!;
    final senderId = state.currentUserId!;
    final otherUserId = state.otherUserId;
    final caption = event.caption ?? '';

    // Fire-and-forget: start upload in background (doesn't block event queue)
    var lastReportedProgress = -1.0;
    unawaited(_performMediaUpload(
      localId: localId,
      conversationId: conversationId,
      senderId: senderId,
      otherUserId: otherUserId,
      type: MessageType.document,
      text: caption,
      upload: () => _mediaUploadService.uploadDocument(
        file: event.file,
        conversationId: conversationId,
        senderId: senderId,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_ChatMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
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

    // Create optimistic pending message IMMEDIATELY for instant display
    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimisticMessage = Message(
      id: localId,
      conversationId: state.conversationId!,
      senderId: state.currentUserId!,
      text: '',
      type: MessageType.sticker,
      status: MessageStatus.pending,
      sentAt: DateTime.now(),
      localId: localId,
      uploadProgress: 0.0,
    );

    final pending = Map<String, Message>.from(state.pendingMessages);
    pending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: pending));

    // Capture state values before async operation
    final conversationId = state.conversationId!;
    final senderId = state.currentUserId!;
    final otherUserId = state.otherUserId;

    // Fire-and-forget: start upload in background (doesn't block event queue)
    var lastReportedProgress = -1.0;
    unawaited(_performMediaUpload(
      localId: localId,
      conversationId: conversationId,
      senderId: senderId,
      otherUserId: otherUserId,
      type: MessageType.sticker,
      upload: () => _mediaUploadService.uploadSticker(
        file: event.file,
        conversationId: conversationId,
        senderId: senderId,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_ChatMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
  }

  /// Performs the actual media upload and sends the message to Firestore.
  /// Runs as fire-and-forget to avoid blocking the bloc's event queue,
  /// allowing other events (messages from stream, typing, etc.) to process.
  Future<void> _performMediaUpload({
    required String localId,
    required String conversationId,
    required String senderId,
    required String? otherUserId,
    required MessageType type,
    required Future<UploadResult> Function() upload,
    String text = '',
    int? duration,
  }) async {
    try {
      // Transition to sending status
      _safeAdd(_ChatMediaUploadProgress(localId: localId, progress: 0.0));

      final uploadResult = await upload();
      if (isClosed) return;

      await _chatService.sendMediaMessage(
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        mediaUrl: uploadResult.downloadUrl,
        mediaFileName: uploadResult.fileName,
        mediaFileSize: uploadResult.fileSize,
        text: text,
        duration: duration,
        recipientId: otherUserId,
        localId: localId,
      );
      // Stream-based deduplication will remove the pending message
    } catch (e) {
      _logger.e('Media upload/send failed', error: e);
      _safeAdd(_ChatMediaUploadFailed(localId: localId, error: 'Failed to send media: $e'));
    }
  }

  void _onMediaUploadProgress(
    _ChatMediaUploadProgress event,
    Emitter<ChatState> emit,
  ) {
    final currentPending = Map<String, Message>.from(state.pendingMessages);
    final existingMsg = currentPending[event.localId];
    if (existingMsg != null) {
      currentPending[event.localId] = existingMsg.copyWith(
        uploadProgress: event.progress,
        status: MessageStatus.sending,
      );
      emit(state.copyWith(pendingMessages: currentPending));
    }
  }

  void _onMediaUploadFailed(
    _ChatMediaUploadFailed event,
    Emitter<ChatState> emit,
  ) {
    // Keep the failed message visible with error status for user feedback.
    // Unlike the old approach (which removed it), this lets users see what failed.
    final currentPending = Map<String, Message>.from(state.pendingMessages);
    final existingMsg = currentPending[event.localId];
    if (existingMsg != null) {
      currentPending[event.localId] = existingMsg.copyWith(
        status: MessageStatus.error,
        errorReason: event.error,
        uploadProgress: null,
      );
    } else {
      currentPending.remove(event.localId);
    }
    emit(state.copyWith(
      pendingMessages: currentPending,
      errorMessage: event.error,
    ));
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

    // CRITICAL: Handle pending messages that don't exist in Firestore yet.
    // If the message ID matches a pending message, just remove it locally.
    final pending = Map<String, Message>.from(state.pendingMessages);
    if (pending.containsKey(event.messageId)) {
      pending.remove(event.messageId);
      _retryService.removeFromQueue(event.messageId);
      emit(state.copyWith(pendingMessages: pending));
      return;
    }

    // Also check if any pending message has a localId matching the messageId
    final pendingKey = pending.keys.cast<String?>().firstWhere(
      (key) => pending[key]?.localId == event.messageId,
      orElse: () => null,
    );
    if (pendingKey != null) {
      pending.remove(pendingKey);
      _retryService.removeFromQueue(pendingKey);
      emit(state.copyWith(pendingMessages: pending));
      return;
    }

    // For confirmed messages, delete via Firestore
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

    // Clear messages from local state immediately for instant feedback
    _logger.d('Clearing all local chat messages');
    emit(state.copyWith(
      messages: const [],
      pendingMessages: const {},
      hasMore: false,
      clearFirstUnreadMessageId: true,
    ));

    // Clear messages from cache
    _cacheService.clearConversation(state.conversationId!);

    try {
      // Clear messages from backend (will also trigger stream update)
      await _chatService.clearMessages(
        state.conversationId!,
        state.currentUserId!,
      );
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
    // Guard: state may have been reset by ChatClose before this event processed
    if (isClosed || state.conversationId == null) return;

    const pageSize = 50;
    // Remove confirmed messages from pending
    final pending = Map<String, Message>.from(state.pendingMessages);

    for (final message in event.messages) {
      // Remove from pending by localId match ONLY.
      // This mirrors v_chat_sdk's approach: localId is the universal dedup key.
      // Fuzzy matching (sender + text + time) was removed because it causes
      // false positives when the same text is sent twice rapidly.
      pending.removeWhere((key, pendingMsg) {
        // Direct key match (pending key IS the localId)
        if (key == message.id) return true;
        
        // LocalId match — this is the primary dedup mechanism.
        // ChatService stores localId in Firestore, so confirmed messages
        // arriving via the stream carry the same localId.
        if (pendingMsg.localId != null &&
            pendingMsg.localId!.isNotEmpty &&
            message.localId != null &&
            message.localId == pendingMsg.localId) {
          return true;
        }
        
        return false;
      });
    }

    // Sync pending message cache: save current pending state or clear if empty.
    if (state.conversationId != null) {
      if (pending.isEmpty) {
        _cacheService.clearPendingMessages(state.conversationId!);
      } else {
        _cacheService.savePendingMessages(state.conversationId!, pending);
      }
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
    // Guard: state may have been reset by ChatClose before this event processed
    if (isClosed || state.conversationId == null) return;

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
      final conversationId = state.conversationId;
      if (conversationId == null) return;
      _typingSubscription = _chatService
          .getTypingStream(conversationId, derivedOtherUserId)
          .listen(
            (isTyping) {
              _safeAdd(_ChatTypingUpdated(isTyping));
            },
            onError: (error) {
              _safeAdd(_ChatErrorOccurred(error.toString()));
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
    if (isClosed || state.conversationId == null) return;
    emit(state.copyWith(isOtherUserTyping: event.isOtherUserTyping));
  }

  void _onErrorOccurred(
    _ChatErrorOccurred event,
    Emitter<ChatState> emit,
  ) {
    if (isClosed || state.conversationId == null) return;
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
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
  }

  /// Safely adds an event to the bloc, suppressing errors if the bloc
  /// has already been closed. This prevents the "Cannot add new events
  /// after calling close" crash from stream callbacks that fire during
  /// the brief window between close() and subscription cancellation.
  void _safeAdd(ChatEvent event) {
    if (!isClosed) {
      try {
        add(event);
      } catch (_) {
        // Bloc was closed between the isClosed check and add() call.
        // This is expected during teardown race conditions.
      }
    }
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
                // Stream delivered data — cancel loading timeout
                _loadingTimeoutTimer?.cancel();
                _loadingTimeoutTimer = null;
                _streamRetryCount = 0;
                _safeAdd(_ChatMessagesUpdated(messages));
              },
              onError: (error) {
                _logger.e('Messages stream error: $error');
                _loadingTimeoutTimer?.cancel();
                _loadingTimeoutTimer = null;
                if (!isClosed) {
                  final errorStr = error.toString();
                  final isPermissionDenied =
                      errorStr.contains('permission-denied') ||
                      errorStr.contains('PERMISSION_DENIED');

                  // Auto-retry for new conversations that may hit permission-denied
                  // before Firestore security rules propagate the new doc.
                  if (isPermissionDenied && _streamRetryCount < _maxStreamRetries) {
                    _streamRetryCount++;
                    _logger.i('Stream permission-denied, auto-retry $_streamRetryCount/$_maxStreamRetries');
                    Future.delayed(
                      Duration(milliseconds: 500 * _streamRetryCount),
                      () {
                        if (!isClosed && state.conversationId != null) {
                          _subscribeToStreams(event, isResync: true);
                        }
                      },
                    );
                    return;
                  }

                  String errorMessage = errorStr;
                  if (isPermissionDenied) {
                    errorMessage = 'Unable to access messages. The conversation may still be initializing. Please wait a moment and try again.';
                  }
                  _safeAdd(_ChatErrorOccurred(errorMessage));
                }
              },
            );

    // Start loading timeout — if stream hasn't emitted within _loadingTimeout,
    // show an error with retry instead of infinite loading spinner.
    // Only start if we're currently in loading state (cache miss) and not resync.
    if (!isResync && state.status == ChatStatus.loading) {
      _loadingTimeoutTimer?.cancel();
      _loadingTimeoutTimer = Timer(_loadingTimeout, () {
        if (!isClosed && state.status == ChatStatus.loading) {
          _logger.w('Loading timeout reached for ${event.conversationId}');
          _safeAdd(const _ChatErrorOccurred(
            'Messages are taking too long to load. Please check your internet connection and try again.',
          ));
        }
      });
    }

    // Subscribe to conversation updates
    _conversationSubscription =
        _chatService.getConversationStream(event.conversationId).listen(
              (conversation) {
                _safeAdd(_ChatConversationUpdated(conversation));
              },
              onError: (error) {
                _safeAdd(_ChatErrorOccurred(error.toString()));
              },
            );

    // Subscribe to typing indicator when we know the other participant
    if (event.otherUserId.trim().isNotEmpty) {
      _typingSubscription = _chatService
          .getTypingStream(event.conversationId, event.otherUserId)
          .listen(
            (isTyping) {
              _safeAdd(_ChatTypingUpdated(isTyping));
            },
            onError: (error) {
              _safeAdd(_ChatErrorOccurred(error.toString()));
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
  Future<void> close() async {
    // Save pending messages to cache before destroying the BLoC.
    // This ensures pending/error messages survive screen changes.
    if (state.conversationId != null && state.pendingMessages.isNotEmpty) {
      _cacheService.savePendingMessages(
        state.conversationId!,
        state.pendingMessages,
      );
    }

    // CRITICAL: Await subscription cancellation to prevent stream callbacks
    // from firing after close, which causes "Cannot add new events after
    // calling close" crashes.
    await _cancelSubscriptions();
    _typingDebounce?.cancel();
    _retryService.clearAll();
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
