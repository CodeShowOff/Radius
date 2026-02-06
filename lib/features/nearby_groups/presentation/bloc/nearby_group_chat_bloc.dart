import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../data/nearby_group_chat_cache_service.dart';
import '../../data/nearby_group_chat_service.dart';
import '../../domain/entities/nearby_group_message.dart';

part 'nearby_group_chat_event.dart';
part 'nearby_group_chat_state.dart';

/// BLoC for managing nearby group chat messages.
///
/// Key behaviors:
/// - SECURITY: Verifies membership before showing any messages
/// - Real-time message streaming with optimistic updates
/// - Caching for instant load on revisit
/// - No approval required - auto-joined via Bluetooth proximity
class NearbyGroupChatBloc
    extends Bloc<NearbyGroupChatEvent, NearbyGroupChatState> {
  final NearbyGroupChatService _chatService;
  final NearbyGroupChatCacheService _cacheService;
  final Logger _logger;
  final Uuid _uuid = const Uuid();

  StreamSubscription<List<NearbyGroupMessage>>? _messagesSubscription;
  bool _hasActiveSubscriptions = false;

  NearbyGroupChatBloc({
    required NearbyGroupChatService chatService,
    required NearbyGroupChatCacheService cacheService,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _logger = logger ?? Logger(),
        super(const NearbyGroupChatState()) {
    on<OpenNearbyGroupChat>(_onOpenNearbyGroupChat);
    on<CloseNearbyGroupChat>(_onCloseNearbyGroupChat);
    on<SendNearbyGroupMessage>(_onSendNearbyGroupMessage);
    on<LoadMoreNearbyGroupMessages>(_onLoadMoreNearbyGroupMessages);
    on<ResyncNearbyGroupChat>(_onResyncNearbyGroupChat);
    on<PreloadNearbyGroupChat>(_onPreloadNearbyGroupChat);
    on<DeleteNearbyGroupMessage>(_onDeleteNearbyGroupMessage);
    on<_NearbyGroupMessagesReceived>(_onNearbyGroupMessagesReceived);
    on<_NearbyGroupChatStreamError>(_onNearbyGroupChatStreamError);
  }

  /// Whether the bloc has active Firestore subscriptions.
  bool get hasActiveSubscriptions => _hasActiveSubscriptions;

  Future<void> _onOpenNearbyGroupChat(
    OpenNearbyGroupChat event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    _logger.d('Opening nearby group chat: ${event.groupId}');

    // Check if already loaded with active subscriptions for the same group
    final isSameGroup = state.groupId == event.groupId &&
        state.currentUserId == event.currentUserId;
    final isAlreadyLoaded = state.status == NearbyGroupChatStatus.loaded ||
        state.status == NearbyGroupChatStatus.sending;

    if (isSameGroup && isAlreadyLoaded && _hasActiveSubscriptions && state.membershipVerified) {
      _logger.i('Chat already loaded with active streams, skipping reload');
      return;
    }

    // Cancel existing subscriptions
    await _cancelSubscriptions();

    // Start loading - DO NOT show any content until membership verified
    emit(state.copyWith(
      status: NearbyGroupChatStatus.loading,
      groupId: event.groupId,
      currentUserId: event.currentUserId,
      currentUsername: event.currentUsername,
      currentUserName: event.currentUserName,
      currentUserPhotoUrl: event.currentUserPhotoUrl,
      messages: const [],
      hasMore: false,
      membershipVerified: false,
      clearError: true,
    ));

    try {
      // ================================================================
      // SECURITY: Verify membership FIRST, before showing any content
      // ================================================================
      final isMember = await _chatService.isMember(
        groupId: event.groupId,
        userId: event.currentUserId,
      );

      if (!isMember) {
        _logger.w('User ${event.currentUserId} is not a member of nearby group ${event.groupId}');
        emit(state.copyWith(
          status: NearbyGroupChatStatus.error,
          errorMessage: 'You are not currently in this group. Move closer to the group creator.',
          membershipVerified: false,
        ));
        return;
      }

      // ================================================================
      // Membership verified - NOW safe to show cached messages
      // Mark as loaded even if no messages yet
      // ================================================================
      emit(state.copyWith(
        membershipVerified: true,
        status: NearbyGroupChatStatus.loaded,
      ));

      if (_cacheService.hasCache(event.groupId)) {
        final cachedMessages = _cacheService.getMessages(event.groupId);
        _logger.d('Showing ${cachedMessages.length} cached messages');
        emit(state.copyWith(
          status: NearbyGroupChatStatus.loaded,
          messages: cachedMessages,
        ));
      }

      // Start listening to real-time messages
      await _subscribeToMessages(event.groupId);

      // Mark group as read
      await _chatService.markGroupAsRead(
        groupId: event.groupId,
        userId: event.currentUserId,
      );
    } catch (e) {
      _logger.e('Error opening nearby group chat', error: e);
      emit(state.copyWith(
        status: NearbyGroupChatStatus.error,
        errorMessage: 'Failed to load chat: $e',
      ));
    }
  }

  Future<void> _subscribeToMessages(String groupId) async {
    await _messagesSubscription?.cancel();

    _messagesSubscription = _chatService.watchMessages(groupId).listen(
      (messages) => add(_NearbyGroupMessagesReceived(messages)),
      onError: (error) => add(_NearbyGroupChatStreamError(error.toString())),
    );

    _hasActiveSubscriptions = true;
    _logger.d('Subscribed to messages for nearby group: $groupId');
  }

  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _hasActiveSubscriptions = false;
  }

  Future<void> _onCloseNearbyGroupChat(
    CloseNearbyGroupChat event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    _logger.d('Closing nearby group chat');
    await _cancelSubscriptions();
    // Don't clear state - keep cache for quick reload
  }

  Future<void> _onSendNearbyGroupMessage(
    SendNearbyGroupMessage event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    if (state.groupId == null ||
        state.currentUserId == null ||
        state.currentUsername == null) {
      _logger.w('Cannot send message: missing group or user info');
      return;
    }

    if (!state.membershipVerified) {
      _logger.w('Cannot send message: membership not verified');
      emit(state.copyWith(
        errorMessage: 'You must be in the group to send messages.',
      ));
      return;
    }

    _logger.d('Sending message to nearby group: ${state.groupId}');

    // ================================================================
    // OPTIMISTIC UPDATE: Show message immediately with local ID
    // ================================================================
    final localId = 'local_${_uuid.v4()}';
    final optimisticMessage = NearbyGroupMessage(
      id: localId,
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderUsername: state.currentUsername!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: event.text.trim(),
      type: NearbyGroupMessageType.text,
      sentAt: DateTime.now(),
    );

    // Add optimistic message to the beginning of the list
    final optimisticMessages = [optimisticMessage, ...state.messages];
    emit(state.copyWith(
      status: NearbyGroupChatStatus.sending,
      messages: optimisticMessages,
    ));

    try {
      await _chatService.sendMessage(
        groupId: state.groupId!,
        senderId: state.currentUserId!,
        senderUsername: state.currentUsername!,
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: event.text,
      );

      // Message sent - keep the optimistic message until stream updates
      // The stream handler will filter out the optimistic message when real message arrives
      emit(state.copyWith(
        status: NearbyGroupChatStatus.loaded,
      ));
    } catch (e) {
      _logger.e('Failed to send message', error: e);

      // Remove the optimistic message on failure
      final updatedMessages = state.messages
          .where((m) => m.id != localId)
          .toList();

      emit(state.copyWith(
        status: NearbyGroupChatStatus.error,
        messages: updatedMessages,
        errorMessage: 'Failed to send message: $e',
      ));
    }
  }

  Future<void> _onLoadMoreNearbyGroupMessages(
    LoadMoreNearbyGroupMessages event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    if (state.groupId == null || state.messages.isEmpty || !state.hasMore) {
      return;
    }

    _logger.d('Loading more messages for nearby group: ${state.groupId}');

    try {
      final oldestMessage = state.messages.last;
      final olderMessages = await _chatService.loadMoreMessages(
        groupId: state.groupId!,
        beforeTimestamp: oldestMessage.sentAt,
      );

      final hasMore = olderMessages.length >= 50;

      // Update cache
      _cacheService.addPaginatedMessages(
        groupId: state.groupId!,
        olderMessages: olderMessages,
        hasMore: hasMore,
      );

      // Merge with existing messages
      final allMessages = [...state.messages, ...olderMessages];

      emit(state.copyWith(
        messages: allMessages,
        hasMore: hasMore,
      ));
    } catch (e) {
      _logger.e('Failed to load more messages', error: e);
    }
  }

  Future<void> _onResyncNearbyGroupChat(
    ResyncNearbyGroupChat event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) return;

    _logger.d('Resyncing nearby group chat');

    // Re-verify membership
    final isMember = await _chatService.isMember(
      groupId: state.groupId!,
      userId: state.currentUserId!,
    );

    if (!isMember) {
      emit(state.copyWith(
        status: NearbyGroupChatStatus.error,
        errorMessage: 'You are no longer in this group.',
        membershipVerified: false,
      ));
      await _cancelSubscriptions();
      return;
    }

    // Resubscribe if needed
    if (!_hasActiveSubscriptions) {
      await _subscribeToMessages(state.groupId!);
    }
  }

  Future<void> _onPreloadNearbyGroupChat(
    PreloadNearbyGroupChat event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    // Skip if already cached
    if (_cacheService.hasValidCache(event.groupId)) {
      _logger.d('Nearby group ${event.groupId} already cached, skipping preload');
      return;
    }

    _logger.d('Preloading nearby group chat: ${event.groupId}');

    try {
      // Verify membership first
      final isMember = await _chatService.isMember(
        groupId: event.groupId,
        userId: event.userId,
      );

      if (!isMember) {
        _logger.d('User not a member of nearby group ${event.groupId}, skipping preload');
        return;
      }

      // Fetch messages and cache them
      final messages = await _chatService.getMessages(groupId: event.groupId);
      _cacheService.updateCache(
        groupId: event.groupId,
        messages: messages,
        hasMore: messages.length >= 50,
      );

      _logger.d('Preloaded ${messages.length} messages for nearby group ${event.groupId}');
    } catch (e) {
      _logger.w('Failed to preload nearby group chat', error: e);
    }
  }

  Future<void> _onDeleteNearbyGroupMessage(
    DeleteNearbyGroupMessage event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) return;

    _logger.d('Deleting message: ${event.messageId}');

    await _chatService.deleteMessage(
      groupId: state.groupId!,
      messageId: event.messageId,
      userId: state.currentUserId!,
    );
  }

  void _onNearbyGroupMessagesReceived(
    _NearbyGroupMessagesReceived event,
    Emitter<NearbyGroupChatState> emit,
  ) {
    _logger.d('Received ${event.messages.length} messages from stream');

    const pageSize = 50;

    // Filter out local/optimistic messages when merging
    final existingOlderMessages = state.messages
        .where((m) => !m.id.startsWith('local_'))
        .where((m) => !event.messages.any((newM) => newM.id == m.id))
        .where((m) =>
            event.messages.isEmpty ||
            m.sentAt.isBefore(event.messages.last.sentAt))
        .toList();

    final allMessages = [...event.messages, ...existingOlderMessages];

    // If we received fewer than pageSize messages, there are no more to load
    final hasMore = event.messages.length >= pageSize;

    // Update cache
    if (state.groupId != null) {
      _cacheService.updateCache(
        groupId: state.groupId!,
        messages: allMessages,
        hasMore: hasMore,
      );
    }

    emit(state.copyWith(
      status: NearbyGroupChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
    ));
  }

  void _onNearbyGroupChatStreamError(
    _NearbyGroupChatStreamError event,
    Emitter<NearbyGroupChatState> emit,
  ) {
    _logger.e('Chat stream error: ${event.error}');

    // Permission denied usually means user was removed from group
    if (event.error.contains('permission-denied')) {
      emit(state.copyWith(
        status: NearbyGroupChatStatus.error,
        errorMessage: 'You are no longer in this group.',
        membershipVerified: false,
      ));
    } else {
      emit(state.copyWith(
        status: NearbyGroupChatStatus.error,
        errorMessage: event.error,
      ));
    }
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    return super.close();
  }
}
