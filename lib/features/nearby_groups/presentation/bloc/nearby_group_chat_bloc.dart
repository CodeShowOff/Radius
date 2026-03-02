import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/widgets/group_message_bubble.dart';
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
    on<DeleteNearbyGroupMessage>(_onDeleteNearbyGroupMessage);
    on<_NearbyGroupMessagesReceived>(_onNearbyGroupMessagesReceived);
    on<_NearbyGroupChatStreamError>(_onNearbyGroupChatStreamError);
    on<RetryNearbyGroupMessage>(_onRetryNearbyGroupMessage);
  }

  Future<void> _onOpenNearbyGroupChat(
    OpenNearbyGroupChat event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    _logger.d('Opening nearby group chat: ${event.groupId}');

    // Cancel any existing subscriptions (factory instance, just safety)
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

    _logger.d('Subscribed to messages for nearby group: $groupId');
  }

  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
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
    // OPTIMISTIC UPDATE: Add to pendingMessages map with pending status.
    // The allMessages getter merges pending + confirmed with localId dedup.
    // ================================================================
    final localId = _uuid.v4();
    final optimisticMessage = NearbyGroupMessage(
      id: 'pending_$localId',
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderUsername: state.currentUsername!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: event.text.trim(),
      type: NearbyGroupMessageType.text,
      sentAt: DateTime.now(),
      localId: localId,
      status: GroupMessageStatus.pending,
    );

    final updatedPending =
        Map<String, NearbyGroupMessage>.from(state.pendingMessages);
    updatedPending[localId] = optimisticMessage;
    emit(state.copyWith(
      status: NearbyGroupChatStatus.sending,
      pendingMessages: updatedPending,
    ));

    try {
      await _chatService.sendMessage(
        groupId: state.groupId!,
        senderId: state.currentUserId!,
        senderUsername: state.currentUsername!,
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: event.text,
        localId: localId,
      );

      // Success: stream will deliver confirmed message with matching localId
      emit(state.copyWith(
        status: NearbyGroupChatStatus.loaded,
      ));
    } catch (e) {
      _logger.e('Failed to send message', error: e);

      // Mark the pending message as error instead of removing it
      final errorPending =
          Map<String, NearbyGroupMessage>.from(state.pendingMessages);
      if (errorPending.containsKey(localId)) {
        errorPending[localId] = errorPending[localId]!.copyWith(
          status: GroupMessageStatus.error,
        );
      }

      emit(state.copyWith(
        status: NearbyGroupChatStatus.loaded,
        errorMessage: 'Failed to send message',
        pendingMessages: errorPending,
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

    // Resubscribe
    await _subscribeToMessages(state.groupId!);
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

    // ========================================================================
    // LOCAL-ID DEDUP: Remove confirmed messages from pendingMessages.
    // ========================================================================
    final updatedPending =
        Map<String, NearbyGroupMessage>.from(state.pendingMessages);
    for (final msg in event.messages) {
      if (msg.localId != null && updatedPending.containsKey(msg.localId)) {
        updatedPending.remove(msg.localId);
      }
    }

    // Merge new messages with older messages (outside the stream window)
    final newMessageIds = event.messages.map((m) => m.id).toSet();
    final existingOlderMessages = state.messages
        .where((m) => !newMessageIds.contains(m.id))
        .where((m) =>
            event.messages.isEmpty ||
            m.sentAt.isBefore(event.messages.last.sentAt))
        .toList();

    final allMessages = [...event.messages, ...existingOlderMessages];
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
      pendingMessages: updatedPending,
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

  /// Retries sending a failed message.
  Future<void> _onRetryNearbyGroupMessage(
    RetryNearbyGroupMessage event,
    Emitter<NearbyGroupChatState> emit,
  ) async {
    final pendingMsg = state.pendingMessages[event.localId];
    if (pendingMsg == null) return;

    final updatedPending =
        Map<String, NearbyGroupMessage>.from(state.pendingMessages);
    updatedPending[event.localId] = pendingMsg.copyWith(
      status: GroupMessageStatus.pending,
    );
    emit(state.copyWith(pendingMessages: updatedPending));

    try {
      await _chatService.sendMessage(
        groupId: pendingMsg.groupId,
        senderId: pendingMsg.senderId ?? state.currentUserId!,
        senderUsername: pendingMsg.senderUsername ?? state.currentUsername ?? 'Unknown',
        senderName: pendingMsg.senderName,
        senderPhotoUrl: pendingMsg.senderPhotoUrl,
        text: pendingMsg.text,
        localId: event.localId,
      );
    } catch (e) {
      _logger.e('Retry failed for message ${event.localId}', error: e);
      final errorPending =
          Map<String, NearbyGroupMessage>.from(state.pendingMessages);
      if (errorPending.containsKey(event.localId)) {
        errorPending[event.localId] = errorPending[event.localId]!.copyWith(
          status: GroupMessageStatus.error,
        );
      }
      emit(state.copyWith(pendingMessages: errorPending));
    }
  }

  @override
  Future<void> close() {
    _cancelSubscriptions();
    return super.close();
  }
}
