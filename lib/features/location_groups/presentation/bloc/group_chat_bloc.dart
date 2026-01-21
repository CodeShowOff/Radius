import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/group_chat_cache_service.dart';
import '../../data/group_chat_service.dart';
import '../../domain/entities/group_message.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';

/// BLoC for managing group chat messages.
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final GroupChatService _chatService;
  final GroupChatCacheService _cacheService;
  final Logger _logger;

  StreamSubscription<List<GroupMessage>>? _messagesSubscription;

  GroupChatBloc({
    required GroupChatService chatService,
    required GroupChatCacheService cacheService,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _logger = logger ?? Logger(),
        super(const GroupChatState()) {
    on<OpenGroupChat>(_onOpenGroupChat);
    on<CloseGroupChat>(_onCloseGroupChat);
    on<SendGroupMessage>(_onSendGroupMessage);
    on<LoadMoreGroupMessages>(_onLoadMoreGroupMessages);
    on<_GroupMessagesReceived>(_onGroupMessagesReceived);
    on<_GroupChatStreamError>(_onGroupChatStreamError);
    on<DeleteGroupMessage>(_onDeleteGroupMessage);
  }

  Future<void> _onOpenGroupChat(
    OpenGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Opening group chat: ${event.groupId}');

    // Cancel any existing subscription
    await _messagesSubscription?.cancel();

    // ========================================================================
    // CRITICAL: Load cached messages IMMEDIATELY for instant display
    // This is the key to WhatsApp/Telegram-level performance
    // ========================================================================
    final cachedMessages = _cacheService.getMessages(event.groupId);
    final hasCache = cachedMessages.isNotEmpty;
    final cachedEntry = _cacheService.getCache(event.groupId);

    if (hasCache) {
      // INSTANT DISPLAY: Show cached messages immediately, no loading spinner
      _logger.i('Cache hit for group ${event.groupId}: ${cachedMessages.length} messages');
      emit(state.copyWith(
        status: GroupChatStatus.loaded, // Already loaded from cache!
        groupId: event.groupId,
        currentUserId: event.currentUserId,
        currentUserName: event.currentUserName,
        currentUserPhotoUrl: event.currentUserPhotoUrl,
        messages: cachedMessages,
        hasMore: cachedEntry?.hasMore ?? true,
        errorMessage: null,
      ));
    } else {
      // No cache - show loading (first time opening this group)
      _logger.i('Cache miss for group ${event.groupId}, showing loading');
      emit(state.copyWith(
        status: GroupChatStatus.loading,
        groupId: event.groupId,
        currentUserId: event.currentUserId,
        currentUserName: event.currentUserName,
        currentUserPhotoUrl: event.currentUserPhotoUrl,
        messages: [],
        hasMore: true,
        errorMessage: null,
      ));
    }

    try {
      final canRead = await _chatService.isActiveMember(
        groupId: event.groupId,
        userId: event.currentUserId,
      );
      if (!canRead) {
        emit(state.copyWith(
          status: GroupChatStatus.error,
          errorMessage: 'You are not a member of this group.',
        ));
        return;
      }

      // Start listening to messages
      _messagesSubscription = _chatService
          .watchMessages(event.groupId, limit: 50)
          .listen(
            (messages) {
              if (!isClosed) {
                add(_GroupMessagesReceived(messages));
              }
            },
            onError: (error) {
              _logger.e('Error watching messages: $error');
              if (isClosed) return;

              if (error is FirebaseException && error.code == 'permission-denied') {
                add(const _GroupChatStreamError('You no longer have access to this group chat.'));
                return;
              }

              add(const _GroupChatStreamError('Failed to load messages.'));
            },
          );

      // Reset unread count when opening the chat
      unawaited(_chatService.markGroupAsRead(
        groupId: event.groupId,
        userId: event.currentUserId,
      ));
    } catch (e, stack) {
      _logger.e('Error opening group chat', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'Failed to load messages',
      ));
    }
  }

  Future<void> _onGroupChatStreamError(
    _GroupChatStreamError event,
    Emitter<GroupChatState> emit,
  ) async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    emit(state.copyWith(
      status: GroupChatStatus.error,
      errorMessage: event.message,
      messages: const [],
      hasMore: false,
    ));
  }

  Future<void> _onCloseGroupChat(
    CloseGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Closing group chat');
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    // Preserve messages for instant display on revisit
    // Only clear the subscription, not the cached data
    emit(state.copyWith(errorMessage: null));
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

      final hasMore = olderMessages.length >= 30;
      final allMessages = [...state.messages, ...olderMessages];

      // Update the cache with paginated messages
      _cacheService.addPaginatedMessages(
        groupId: state.groupId!,
        olderMessages: olderMessages,
        hasMore: hasMore,
      );

      emit(state.copyWith(
        messages: allMessages,
        hasMore: hasMore,
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

    const pageSize = 50;

    // Merge with any older messages we've loaded via pagination
    final currentOldMessages = state.messages.where((m) {
      // Keep messages that are older than the oldest message in the new list
      if (event.messages.isEmpty) return true;
      return m.sentAt.isBefore(event.messages.last.sentAt);
    }).toList();

    final allMessages = [...event.messages, ...currentOldMessages];
    final hasMore = event.messages.length >= pageSize;

    // ========================================================================
    // CRITICAL: Update the global cache with new messages
    // This enables instant display when returning to this group later
    // ========================================================================
    if (state.groupId != null) {
      _cacheService.updateCache(
        groupId: state.groupId!,
        messages: allMessages,
        hasMore: hasMore,
      );
    }

    // Always set status to loaded when we receive messages to clear loading state
    emit(state.copyWith(
      status: GroupChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
    ));

    if (state.groupId != null && state.currentUserId != null) {
      unawaited(_chatService.markGroupAsRead(
        groupId: state.groupId!,
        userId: state.currentUserId!,
      ));
    }
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
