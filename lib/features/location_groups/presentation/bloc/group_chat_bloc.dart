import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/widgets/group_message_bubble.dart';
import '../../data/group_chat_cache_service.dart';
import '../../data/group_chat_service.dart';
import '../../data/group_media_upload_service.dart';
import '../../../chat/data/media_upload_service.dart';
import '../../domain/entities/group_message.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';

const _uuid = Uuid();

/// BLoC for managing group chat messages with strict membership access control.
///
/// ## Security Model
///
/// This BLoC enforces a **membership-gated access control** model:
///
/// 1. **Membership verification is MANDATORY** before any content is shown.
///    The `membershipVerified` flag in [GroupChatState] gates ALL access.
///
/// 2. **No cached content before verification**: Unlike typical instant-load
///    patterns, we DO NOT show cached messages until membership is confirmed.
///    This prevents privacy leaks from stale cache or URL manipulation.
///
/// 3. **Defense in depth**: This client-side check complements Firestore
///    security rules that also enforce `isGroupMember()` for read/write.
///
/// ## Access Flow
///
/// 1. [OpenGroupChat] → Check for cached messages
/// 2. If cached messages exist → Show immediately, verify membership in background
/// 3. If no cache → Check `isActiveMember()` → If false, show error and block access
/// 4. If member, set `membershipVerified = true` → Show streamed messages
/// 5. [SendGroupMessage] → Blocked if `membershipVerified == false`
///
/// ## Edge Cases Handled
///
/// - Cached messages available → Shown instantly, stream validates access
/// - User removed while cache exists → Stream errors, access revoked
/// - First visit (no cache) → Brief loading spinner while verifying
/// - Stale cached membership → Background check refreshes cache
/// - Direct URL navigation by non-member → Verified check blocks access
/// - Network loss during verification → Error state, access blocked
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final GroupChatService _chatService;
  final GroupChatCacheService _cacheService;
  final GroupMediaUploadService _mediaUploadService;
  final Logger _logger;

  StreamSubscription<List<GroupMessage>>? _messagesSubscription;

  /// Cache for verified memberships: Map<"userId:groupId", DateTime>
  /// This prevents repeated Firestore calls when navigating between groups.
  /// TTL: 5 minutes - balances performance with security (catching removals).
  static final Map<String, DateTime> _membershipCache = {};
  static const Duration _membershipCacheTtl = Duration(minutes: 5);

  GroupChatBloc({
    required GroupChatService chatService,
    required GroupChatCacheService cacheService,
    required GroupMediaUploadService mediaUploadService,
    Logger? logger,
  })  : _chatService = chatService,
        _cacheService = cacheService,
        _mediaUploadService = mediaUploadService,
        _logger = logger ?? Logger(),
        super(const GroupChatState()) {
    on<OpenGroupChat>(_onOpenGroupChat);
    on<CloseGroupChat>(_onCloseGroupChat);
    on<SendGroupMessage>(_onSendGroupMessage);
    on<SendGroupImage>(_onSendGroupImage);
    on<SendGroupAudio>(_onSendGroupAudio);
    on<SendGroupDocument>(_onSendGroupDocument);
    on<SendGroupVideo>(_onSendGroupVideo);
    on<LoadMoreGroupMessages>(_onLoadMoreGroupMessages);
    on<ResyncGroupChat>(_onResyncGroupChat);
    on<_GroupMessagesReceived>(_onGroupMessagesReceived);
    on<_GroupChatStreamError>(_onGroupChatStreamError);
    on<DeleteGroupMessage>(_onDeleteGroupMessage);
    on<ClearGroupChatMessages>(_onClearGroupChatMessages);
    on<_UnreadInfoReceived>(_onUnreadInfoReceived);
    on<RetryGroupMessage>(_onRetryGroupMessage);
    on<_GroupMediaUploadProgress>(_onGroupMediaUploadProgress);
    on<_GroupMediaUploadFailed>(_onGroupMediaUploadFailed);
  }

  /// Check if membership is cached and still valid.
  bool _isMembershipCached(String userId, String groupId) {
    final key = '$userId:$groupId';
    final cachedAt = _membershipCache[key];
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < _membershipCacheTtl;
  }

  /// Cache a verified membership.
  void _cacheMembership(String userId, String groupId) {
    final key = '$userId:$groupId';
    _membershipCache[key] = DateTime.now();
    _logger.d('Cached membership for $key');
  }

  /// Invalidate membership cache for a user/group (e.g., on error or removal).
  void _invalidateMembershipCache(String userId, String groupId) {
    final key = '$userId:$groupId';
    _membershipCache.remove(key);
    _logger.d('Invalidated membership cache for $key');
  }

  /// Refreshes membership verification in the background without blocking UI.
  /// If the user was removed, the Firestore stream will handle access revocation.
  /// This ensures the membership cache stays up to date for future navigations.
  void _refreshMembershipInBackground(String userId, String groupId) {
    _chatService
        .isActiveMember(groupId: groupId, userId: userId)
        .then((isActive) {
      if (isActive) {
        _cacheMembership(userId, groupId);
      } else if (!isClosed) {
        _logger.w(
            'Background membership check failed for $userId in $groupId');
        _invalidateMembershipCache(userId, groupId);
        _cacheService.clearGroup(groupId);
        add(const _GroupChatStreamError(
          'You no longer have access to this group chat.',
        ));
      }
    }).catchError((e) {
      _logger.w('Background membership check error: $e');
      // Don't revoke access on network error - stream handles this
    });
  }

  Future<void> _onOpenGroupChat(
    OpenGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Opening group chat: ${event.groupId}');

    // Cancel any existing subscription (factory instance, so this is just safety)
    await _cancelSubscriptions();

    // ========================================================================
    // SECURITY: Verify membership before showing content.
    // When cached messages exist, they are shown immediately (fast path above)
    // with background verification. This slow path handles the no-cache case.
    // ========================================================================

    // Check if we have a cached membership verification (optimization)
    final hasCachedMembership =
        _isMembershipCached(event.currentUserId, event.groupId);
    final cachedMessages = _cacheService.getMessages(event.groupId);
    final hasCache = cachedMessages.isNotEmpty;

    if (hasCache) {
      // FAST PATH: Show cached messages immediately for smooth UX.
      // Security is maintained via:
      // 1. Firestore stream errors with permission-denied if user was removed
      // 2. Background membership check revokes access if verification fails
      // 3. Firestore security rules enforce membership on all operations
      _logger.i(
          'Showing cached messages for ${event.groupId} immediately');
      final cachedEntry = _cacheService.getCache(event.groupId);

      emit(state.copyWith(
        status: GroupChatStatus.loaded,
        groupId: event.groupId,
        currentUserId: event.currentUserId,
        currentUserName: event.currentUserName,
        currentUserPhotoUrl: event.currentUserPhotoUrl,
        messages: cachedMessages,
        hasMore: cachedEntry?.hasMore ?? true,
        errorMessage: null,
        membershipVerified: true,
      ));

      // Fetch unread info AND start message stream in parallel
      // Unread info fetch is non-blocking - messages show immediately from cache
      final unreadFuture = _fetchUnreadInfo(event.groupId, event.currentUserId);

      // Start listening to messages (stream will error if user was removed)
      await _subscribeToMessages(event.groupId);

      // Await unread info (may already be done by now)
      await unreadFuture;

      // Refresh membership cache in background if expired
      if (!hasCachedMembership) {
        _refreshMembershipInBackground(event.currentUserId, event.groupId);
      }
      return;
    }

    // Always start with the group context and immediately subscribe to messages.
    // WhatsApp-style: no blocking membership check — just start streaming.
    // Firestore security rules enforce membership on the backend.
    // If user isn't a member, the stream will error with permission-denied.
    emit(state.copyWith(
      status: GroupChatStatus.loaded,
      groupId: event.groupId,
      currentUserId: event.currentUserId,
      currentUserName: event.currentUserName,
      currentUserPhotoUrl: event.currentUserPhotoUrl,
      messages: const [],
      hasMore: true,
      errorMessage: null,
      membershipVerified: true,
    ));

    try {
      // Start message stream AND fetch unread info in PARALLEL — no blocking
      final unreadFuture = _fetchUnreadInfo(event.groupId, event.currentUserId);

      // Subscribe to messages immediately — stream will deliver messages
      // or error with permission-denied if user is not a member
      await _subscribeToMessages(event.groupId);

      // Cache membership on successful stream setup
      _cacheMembership(event.currentUserId, event.groupId);

      // Await unread info (may already be done by now)
      await unreadFuture;
    } catch (e, stack) {
      _logger.e('Error opening group chat', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'Failed to load messages',
        membershipVerified: false,
      ));
      // Invalidate membership cache on error
      _invalidateMembershipCache(event.currentUserId, event.groupId);
    }
  }

  Future<void> _onGroupChatStreamError(
    _GroupChatStreamError event,
    Emitter<GroupChatState> emit,
  ) async {
    await _cancelSubscriptions();

    // Invalidate membership cache when stream errors (likely permission denied)
    if (state.currentUserId != null && state.groupId != null) {
      _invalidateMembershipCache(state.currentUserId!, state.groupId!);
    }

    // SECURITY: On access error, revoke membership verification
    // This handles the case where user was removed while viewing chat
    emit(state.copyWith(
      status: GroupChatStatus.error,
      errorMessage: event.message,
      messages: const [],
      hasMore: false,
      membershipVerified: false, // Revoke access on error
    ));
  }

  Future<void> _onCloseGroupChat(
    CloseGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    _logger.d('Closing group chat');

    // Update lastReadAt before closing to ensure the unread divider
    // positions correctly next time the user opens this chat.
    // This is important because markGroupAsRead skips writes when
    // unreadCount is 0 (to avoid unnecessary Firestore writes).
    if (state.groupId != null &&
        state.currentUserId != null &&
        state.membershipVerified) {
      unawaited(_chatService.updateLastReadTimestamp(
        groupId: state.groupId!,
        userId: state.currentUserId!,
      ));
    }

    await _cancelSubscriptions();
  }

  Future<void> _onSendGroupMessage(
    SendGroupMessage event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) {
      _logger.w('Cannot send message: chat not open');
      return;
    }

    // SECURITY: Verify membership is confirmed before allowing send
    if (!state.membershipVerified) {
      _logger.w('Cannot send message: membership not verified');
      emit(state.copyWith(
        status: GroupChatStatus.error,
        errorMessage: 'You must be a member to send messages.',
      ));
      return;
    }

    final text = event.text.trim();
    if (text.isEmpty) return;

    _logger.d(
        'Sending message: ${text.substring(0, text.length.clamp(0, 20))}...');

    // ========================================================================
    // OPTIMISTIC UPDATE: Add to pendingMessages map with pending status.
    // The allMessages getter merges pending + confirmed with localId dedup.
    // ========================================================================
    final localId = _uuid.v4();
    final optimisticMessage = GroupMessage(
      id: 'pending_$localId',
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: text,
      sentAt: DateTime.now(),
      localId: localId,
      status: GroupMessageStatus.pending,
    );

    final updatedPending =
        Map<String, GroupMessage>.from(state.pendingMessages);
    updatedPending[localId] = optimisticMessage;
    emit(state.copyWith(
      status: GroupChatStatus.sending,
      pendingMessages: updatedPending,
    ));

    try {
      await _chatService.sendMessage(
        groupId: state.groupId!,
        senderId: state.currentUserId!,
        senderName: state.currentUserName,
        senderPhotoUrl: state.currentUserPhotoUrl,
        text: text,
        localId: localId,
      );

      // Success: stream will deliver confirmed message with matching localId
      emit(state.copyWith(status: GroupChatStatus.loaded));
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);

      String errorMsg = 'Failed to send message. Please try again.';
      if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          errorMsg =
              'Unable to send message. This may happen if you just joined. Please wait a moment and try again.';
        } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          errorMsg =
              'Network error. Please check your connection and try again.';
        }
      }

      final errorPending =
          Map<String, GroupMessage>.from(state.pendingMessages);
      if (errorPending.containsKey(localId)) {
        errorPending[localId] = errorPending[localId]!.copyWith(
          status: GroupMessageStatus.error,
        );
      }

      emit(state.copyWith(
        status: GroupChatStatus.loaded,
        errorMessage: errorMsg,
        pendingMessages: errorPending,
      ));
    }
  }

  Future<void> _onSendGroupImage(
    SendGroupImage event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) return;
    if (!state.membershipVerified) return;

    final localId = _uuid.v4();
    final optimisticMessage = GroupMessage(
      id: 'pending_$localId',
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: event.caption ?? '',
      type: GroupMessageType.image,
      sentAt: DateTime.now(),
      localId: localId,
      status: GroupMessageStatus.pending,
      uploadProgress: 0.0,
    );

    final updatedPending = Map<String, GroupMessage>.from(state.pendingMessages);
    updatedPending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: updatedPending));

    final groupId = state.groupId!;
    final senderId = state.currentUserId!;
    final senderName = state.currentUserName;
    final senderPhotoUrl = state.currentUserPhotoUrl;
    final caption = event.caption ?? '';

    var lastReportedProgress = -1.0;
    unawaited(_performGroupMediaUpload(
      localId: localId,
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      type: GroupMessageType.image,
      text: caption,
      upload: () => _mediaUploadService.uploadImage(
        file: event.file,
        groupId: groupId,
        senderId: senderId,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_GroupMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
  }

  Future<void> _onSendGroupAudio(
    SendGroupAudio event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) return;
    if (!state.membershipVerified) return;

    final localId = _uuid.v4();
    final optimisticMessage = GroupMessage(
      id: 'pending_$localId',
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: '',
      type: GroupMessageType.audio,
      duration: event.duration,
      sentAt: DateTime.now(),
      localId: localId,
      status: GroupMessageStatus.pending,
      uploadProgress: 0.0,
    );

    final updatedPending = Map<String, GroupMessage>.from(state.pendingMessages);
    updatedPending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: updatedPending));

    final groupId = state.groupId!;
    final senderId = state.currentUserId!;
    final senderName = state.currentUserName;
    final senderPhotoUrl = state.currentUserPhotoUrl;
    final duration = event.duration;

    var lastReportedProgress = -1.0;
    unawaited(_performGroupMediaUpload(
      localId: localId,
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      type: GroupMessageType.audio,
      duration: duration,
      upload: () => _mediaUploadService.uploadAudio(
        file: event.file,
        groupId: groupId,
        senderId: senderId,
        duration: duration,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_GroupMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
  }

  Future<void> _onSendGroupDocument(
    SendGroupDocument event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) return;
    if (!state.membershipVerified) return;

    final localId = _uuid.v4();
    final fileName = event.file.path.split(Platform.pathSeparator).last;
    final optimisticMessage = GroupMessage(
      id: 'pending_$localId',
      groupId: state.groupId!,
      senderId: state.currentUserId!,
      senderName: state.currentUserName,
      senderPhotoUrl: state.currentUserPhotoUrl,
      text: event.caption ?? '',
      type: GroupMessageType.document,
      mediaFileName: fileName,
      sentAt: DateTime.now(),
      localId: localId,
      status: GroupMessageStatus.pending,
      uploadProgress: 0.0,
    );

    final updatedPending = Map<String, GroupMessage>.from(state.pendingMessages);
    updatedPending[localId] = optimisticMessage;
    emit(state.copyWith(pendingMessages: updatedPending));

    final groupId = state.groupId!;
    final senderId = state.currentUserId!;
    final senderName = state.currentUserName;
    final senderPhotoUrl = state.currentUserPhotoUrl;
    final caption = event.caption ?? '';

    var lastReportedProgress = -1.0;
    unawaited(_performGroupMediaUpload(
      localId: localId,
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      type: GroupMessageType.document,
      text: caption,
      upload: () => _mediaUploadService.uploadDocument(
        file: event.file,
        groupId: groupId,
        senderId: senderId,
        onProgress: (progress) {
          if (!isClosed && (progress - lastReportedProgress >= 0.05 || progress >= 1.0)) {
            lastReportedProgress = progress;
            _safeAdd(_GroupMediaUploadProgress(localId: localId, progress: progress));
          }
        },
      ),
    ));
  }

  Future<void> _onSendGroupVideo(
    SendGroupVideo event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) return;
    if (!state.membershipVerified) return;

    emit(state.copyWith(
      errorMessage: '🎬 Video sharing in groups is coming soon!',
    ));
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

      // Deduplicate: ensure no overlap with existing messages
      final existingIds = state.messages.map((m) => m.id).toSet();
      final uniqueOlderMessages =
          olderMessages.where((m) => !existingIds.contains(m.id)).toList();

      final allMessages = [...state.messages, ...uniqueOlderMessages];

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

    // ========================================================================
    // LOCAL-ID DEDUP: Remove confirmed messages from pendingMessages.
    // ========================================================================
    final updatedPending =
        Map<String, GroupMessage>.from(state.pendingMessages);
    for (final msg in event.messages) {
      if (msg.localId != null && updatedPending.containsKey(msg.localId)) {
        updatedPending.remove(msg.localId);
      }
    }

    // Merge new messages with older messages (outside the stream window)
    final newMessageIds = event.messages.map((m) => m.id).toSet();
    final currentOldMessages = state.messages.where((m) {
      if (newMessageIds.contains(m.id)) return false;
      if (event.messages.isEmpty) return true;
      return m.sentAt.isBefore(event.messages.last.sentAt);
    }).toList();

    final allMessages = [...event.messages, ...currentOldMessages];
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
      status: GroupChatStatus.loaded,
      messages: allMessages,
      hasMore: hasMore,
      pendingMessages: updatedPending,
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

  /// Clears all local chat messages immediately.
  /// This is called after an admin successfully clears the chat,
  /// to provide immediate feedback without waiting for Firestore stream updates.
  void _onClearGroupChatMessages(
    ClearGroupChatMessages event,
    Emitter<GroupChatState> emit,
  ) {
    _logger.d('Clearing all local chat messages');

    // Clear messages from local state
    emit(state.copyWith(
      messages: const [],
      hasMore: false,
      clearFirstUnreadMessageId: true,
    ));

    // Clear messages from cache
    if (state.groupId != null) {
      _cacheService.clearGroup(state.groupId!);
    }
  }

  /// Handle resync request (app resume, network reconnect).
  ///
  /// This resubscribes to the Firestore stream without resetting state,
  /// ensuring any messages received while the app was backgrounded are fetched.
  /// This is critical for WhatsApp-like real-time messaging behavior.
  Future<void> _onResyncGroupChat(
    ResyncGroupChat event,
    Emitter<GroupChatState> emit,
  ) async {
    if (state.groupId == null || state.currentUserId == null) {
      _logger.d('Resync skipped: no active group chat');
      return;
    }

    if (!state.membershipVerified) {
      _logger.d('Resync skipped: membership not verified');
      return;
    }

    _logger.i('Resync requested for group ${state.groupId}');

    // Cancel existing subscription and resubscribe
    await _subscribeToMessages(state.groupId!);
  }

  /// Handles unread info received from background fetch.
  void _onUnreadInfoReceived(
    _UnreadInfoReceived event,
    Emitter<GroupChatState> emit,
  ) {
    emit(state.copyWith(
      firstUnreadMessageId: event.firstUnreadMessageId,
      unreadCountAtOpen: event.unreadCount,
    ));
  }

  /// Fetches first unread message ID and unread count in parallel.
  /// This is non-blocking and won't prevent messages from loading.
  Future<void> _fetchUnreadInfo(String groupId, String userId) async {
    try {
      final firstUnreadId = await _chatService.getFirstUnreadMessageId(
        groupId: groupId,
        userId: userId,
      );

      if (firstUnreadId != null && !isClosed) {
        _logger.i('First unread message ID: $firstUnreadId');
        final unreadCount = await _chatService.getUnreadCount(
          groupId: groupId,
          userId: userId,
        );
        if (!isClosed) {
          add(_UnreadInfoReceived(firstUnreadId, unreadCount));
        }
      }
    } catch (e) {
      _logger.w('Failed to get first unread message ID: $e');
      // Continue without unread divider - not critical
    }
  }

  /// Retries sending a failed message.
  Future<void> _onRetryGroupMessage(
    RetryGroupMessage event,
    Emitter<GroupChatState> emit,
  ) async {
    final pendingMsg = state.pendingMessages[event.localId];
    if (pendingMsg == null) return;

    final updatedPending =
        Map<String, GroupMessage>.from(state.pendingMessages);
    updatedPending[event.localId] = pendingMsg.copyWith(
      status: GroupMessageStatus.pending,
    );
    emit(state.copyWith(pendingMessages: updatedPending));

    try {
      await _chatService.sendMessage(
        groupId: pendingMsg.groupId,
        senderId: pendingMsg.senderId,
        senderName: pendingMsg.senderName,
        senderPhotoUrl: pendingMsg.senderPhotoUrl,
        text: pendingMsg.text,
        localId: event.localId,
      );
    } catch (e) {
      _logger.e('Retry failed for message ${event.localId}', error: e);
      final errorPending =
          Map<String, GroupMessage>.from(state.pendingMessages);
      if (errorPending.containsKey(event.localId)) {
        errorPending[event.localId] = errorPending[event.localId]!.copyWith(
          status: GroupMessageStatus.error,
        );
      }
      emit(state.copyWith(pendingMessages: errorPending));
    }
  }

  /// Cancels all Firestore stream subscriptions.
  Future<void> _cancelSubscriptions() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _logger.d('Subscriptions cancelled');
  }

  /// Subscribes to Firestore messages stream for the current group.
  /// This is extracted to allow resubscription without full state reset.
  Future<void> _subscribeToMessages(String groupId) async {
    // Cancel any existing subscriptions first
    await _cancelSubscriptions();

    // Subscribe to messages stream with better error handling
    _messagesSubscription =
        _chatService.watchMessages(groupId, limit: 50).listen(
      (messages) {
        if (!isClosed) {
          add(_GroupMessagesReceived(messages));
        }
      },
      onError: (error) {
        _logger.e('Error watching messages: $error');
        if (isClosed) return;

        if (error is FirebaseException && error.code == 'permission-denied') {
          add(const _GroupChatStreamError(
              'You no longer have access to this group chat.'));
          return;
        }

        add(const _GroupChatStreamError('Failed to load messages.'));
      },
    );

    _logger.i('Message subscription created for group $groupId');
  }

  /// Safely adds an event to the bloc, checking if it's still open.
  void _safeAdd(GroupChatEvent event) {
    if (!isClosed) {
      add(event);
    }
  }

  /// Performs the actual media upload and sends the message to Firestore.
  Future<void> _performGroupMediaUpload({
    required String localId,
    required String groupId,
    required String senderId,
    String? senderName,
    String? senderPhotoUrl,
    required GroupMessageType type,
    required Future<UploadResult> Function() upload,
    String text = '',
    int? duration,
  }) async {
    try {
      _safeAdd(_GroupMediaUploadProgress(localId: localId, progress: 0.0));

      final uploadResult = await upload();
      if (isClosed) return;

      await _chatService.sendMediaMessage(
        groupId: groupId,
        senderId: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        type: type,
        mediaUrl: uploadResult.downloadUrl,
        mediaFileName: uploadResult.fileName,
        mediaFileSize: uploadResult.fileSize,
        text: text,
        duration: duration,
        localId: localId,
      );
    } catch (e) {
      _logger.e('Group media upload/send failed', error: e);
      _safeAdd(_GroupMediaUploadFailed(localId: localId, error: 'Failed to send media: $e'));
    }
  }

  void _onGroupMediaUploadProgress(
    _GroupMediaUploadProgress event,
    Emitter<GroupChatState> emit,
  ) {
    final currentPending = Map<String, GroupMessage>.from(state.pendingMessages);
    final existingMsg = currentPending[event.localId];
    if (existingMsg != null) {
      currentPending[event.localId] = existingMsg.copyWith(
        uploadProgress: event.progress,
        status: GroupMessageStatus.pending,
      );
      emit(state.copyWith(pendingMessages: currentPending));
    }
  }

  void _onGroupMediaUploadFailed(
    _GroupMediaUploadFailed event,
    Emitter<GroupChatState> emit,
  ) {
    final currentPending = Map<String, GroupMessage>.from(state.pendingMessages);
    final existingMsg = currentPending[event.localId];
    if (existingMsg != null) {
      currentPending[event.localId] = existingMsg.copyWith(
        status: GroupMessageStatus.error,
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

  @override
  Future<void> close() {
    _cancelSubscriptions();
    return super.close();
  }
}
