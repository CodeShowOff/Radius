import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/nearby_group_chat_cache_service.dart';
import '../../data/nearby_group_chat_service.dart';
import '../../domain/entities/nearby_group_message.dart';

part 'nearby_group_chat_event.dart';
part 'nearby_group_chat_state.dart';

/// BLoC for managing nearby group chat messages.
///
/// Key behaviors:
/// - Verifies membership before showing messages
/// - Real-time message streaming
/// - Caching for instant load on revisit
/// - No approval required - auto-joined via Bluetooth
class NearbyGroupChatBloc
    extends Bloc<NearbyGroupChatEvent, NearbyGroupChatState> {
  final NearbyGroupChatService _chatService;
  final NearbyGroupChatCacheService _cacheService;
  final Logger _logger;

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

    // Check if already loaded with active subscriptions
    final isSameGroup = state.groupId == event.groupId &&
        state.currentUserId == event.currentUserId;
    final isAlreadyLoaded = state.status == NearbyGroupChatStatus.loaded ||
        state.status == NearbyGroupChatStatus.sending;

    if (isSameGroup && isAlreadyLoaded && _hasActiveSubscriptions) {
      _logger.i('Chat already loaded with active streams, skipping reload');
      return;
    }

    // Cancel existing subscriptions
    await _cancelSubscriptions();

    // Start loading
    emit(state.copyWith(
      status: NearbyGroupChatStatus.loading,
      groupId: event.groupId,
      currentUserId: event.currentUserId,
      currentUsername: event.currentUsername,
      currentUserName: event.currentUserName,
      currentUserPhotoUrl: event.currentUserPhotoUrl,
      messages: const [],
      hasMore: true,
      membershipVerified: false,
      clearError: true,
    ));

    try {
      // Verify membership
      final isMember = await _chatService.isMember(
        groupId: event.groupId,
        userId: event.currentUserId,
      );

      if (!isMember) {
        _logger.w('User ${event.currentUserId} is not a member of group ${event.groupId}');
        emit(state.copyWith(
          status: NearbyGroupChatStatus.error,
          errorMessage: 'You are not currently in this group. Move closer to the group creator.',
          membershipVerified: false,
        ));
        return;
      }

      // Membership verified - show cached messages if available
      emit(state.copyWith(membershipVerified: true));

      if (_cacheService.hasCache(event.groupId)) {
        final cachedMessages = _cacheService.getMessages(event.groupId);
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

    _hasActiveSubscriptions = true;
    _logger.d('Subscribed to messages for group: $groupId');
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

    emit(state.copyWith(status: NearbyGroupChatStatus.sending));

    try {
      await _chatService.sendMessage(
        groupId: state.groupId!,
        senderId: state.currentUserId!,
        senderUsername: state.currentUsername!,
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: event.text,
      );

      emit(state.copyWith(status: NearbyGroupChatStatus.loaded));
    } catch (e) {
      _logger.e('Failed to send message', error: e);
      emit(state.copyWith(
        status: NearbyGroupChatStatus.error,
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

    _logger.d('Loading more messages for group: ${state.groupId}');

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
    _logger.d('Received ${event.messages.length} messages');

    // Update cache
    if (state.groupId != null) {
      _cacheService.updateCache(
        groupId: state.groupId!,
        messages: event.messages,
      );
    }

    // Merge with existing paginated messages
    final existingOlderMessages = state.messages
        .where((m) => !event.messages.any((newM) => newM.id == m.id))
        .where((m) =>
            event.messages.isEmpty ||
            m.sentAt.isBefore(event.messages.last.sentAt))
        .toList();

    final allMessages = [...event.messages, ...existingOlderMessages];

    emit(state.copyWith(
      status: NearbyGroupChatStatus.loaded,
      messages: allMessages,
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
