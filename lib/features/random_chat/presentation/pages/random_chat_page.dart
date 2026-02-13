import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../domain/entities/random_chat_request.dart';
import '../../domain/entities/random_chat_user.dart';
import '../bloc/random_chat_bloc.dart';

/// Main Random Chat page showing daily user suggestions,
/// incoming requests, and active connection status.
class RandomChatPage extends StatefulWidget {
  const RandomChatPage({super.key});

  @override
  State<RandomChatPage> createState() => _RandomChatPageState();
}

class _RandomChatPageState extends State<RandomChatPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set up pulse animation for loading state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No account-switch detection needed here — full app data is cleared
    // on sign-out via AppDataClearer, so stale data cannot exist.
  }

  @override
  void dispose() {
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check for midnight reset when app resumes
      context.read<RandomChatBloc>().add(const RandomChatCheckDateChange());
    }
  }

  void _loadData() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final profileState = context.read<ProfileBloc>().state;
    String? gender;
    if (profileState is ProfileLoaded) {
      gender = profileState.profile.gender;
    }

    final bloc = context.read<RandomChatBloc>();

    // Always update current user info (may have changed since last visit)
    bloc.setCurrentUser(
      userId: authState.user.id,
      displayName: authState.user.displayName ?? 'Unknown',
      photoUrl: authState.user.avatarUrl,
      gender: gender,
    );

    // Check if already loaded with today's data
    final currentState = bloc.state;
    final todayKey = _getTodayKey();

    if (currentState is RandomChatLoaded &&
        currentState.dateKey == todayKey &&
        currentState.suggestions.isNotEmpty) {
      // Already loaded with valid data for today
      // Real-time listeners are already active, no need to reload
      return;
    }

    // Load data (first visit, different day, or empty suggestions)
    bloc.add(RandomChatLoadRequested(
      userId: authState.user.id,
      userGender: gender,
    ));
  }

  /// Returns today's date key in 'yyyy-MM-dd' format (UTC).
  /// MUST use UTC to match server-side Cloud Function timezone.
  String _getTodayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Random Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How it works',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: BlocConsumer<RandomChatBloc, RandomChatState>(
        listener: (context, state) {
          if (state is RandomChatError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        buildWhen: (previous, current) {
          // Always rebuild for non-error states
          if (current is! RandomChatError) return true;
          // For errors during initial load: show error UI with Retry button
          // For errors during actions (send/accept): keep Loaded state, error via snackbar
          return previous is RandomChatLoading || previous is RandomChatInitial;
        },
        builder: (context, state) {
          if (state is RandomChatLoading) {
            return _buildLoadingState(theme);
          }

          if (state is RandomChatLoaded) {
            return _buildLoadedContent(context, state, theme);
          }

          if (state is RandomChatError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return _buildLoadingState(theme);
        },
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    RandomChatLoaded state,
    ThemeData theme,
  ) {
    // If there's an active connection, use Column with Spacer to pin it at bottom
    if (state.hasActiveConnection) {
      return Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Incoming requests section
                  if (state.incomingRequests.isNotEmpty) ...[
                    _buildSectionHeader(
                      theme,
                      'Incoming Requests',
                      Icons.mail,
                      badge: state.incomingRequests.length.toString(),
                    ),
                    const SizedBox(height: 8),
                    ...state.incomingRequests.map(
                        (r) => _buildIncomingRequestCard(context, r, state, theme)),
                    const SizedBox(height: 20),
                  ],

                  // Daily suggestions
                  _buildSectionHeader(
                    theme,
                    'Today\'s Suggestions',
                    Icons.people_alt,
                    subtitle: state.suggestions.isEmpty
                        ? 'No users available right now'
                        : '${state.suggestions.length} users discovered',
                  ),
                  const SizedBox(height: 8),

                  if (state.suggestions.isEmpty)
                    _buildEmptyState(theme)
                  else
                    ...state.suggestions.map(
                      (user) => _buildSuggestionCard(context, user, state, theme),
                    ),
                ],
              ),
            ),
          ),

          // Pinned active connection card at bottom
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surface.withValues(alpha: 0.0),
                    theme.colorScheme.surface.withValues(alpha: 0.95),
                    theme.colorScheme.surface,
                  ],
                  stops: const [0.0, 0.3, 0.5],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: _buildActiveConnectionCard(context, state, theme),
            ),
          ),
        ],
      );
    }

    // No active connection - regular scrollable layout
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Incoming requests section
          if (state.incomingRequests.isNotEmpty) ...[
            _buildSectionHeader(
              theme,
              'Incoming Requests',
              Icons.mail,
              badge: state.incomingRequests.length.toString(),
            ),
            const SizedBox(height: 8),
            ...state.incomingRequests.map(
                (r) => _buildIncomingRequestCard(context, r, state, theme)),
            const SizedBox(height: 20),
          ],

          // Daily suggestions
          _buildSectionHeader(
            theme,
            'Today\'s Suggestions',
            Icons.people_alt,
            subtitle: state.suggestions.isEmpty
                ? 'No users available right now'
                : '${state.suggestions.length} users discovered',
          ),
          const SizedBox(height: 8),

          if (state.suggestions.isEmpty)
            _buildEmptyState(theme)
          else
            ...state.suggestions.map(
              (user) => _buildSuggestionCard(context, user, state, theme),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated pulsing icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Opacity(
                  opacity: 1.0 - ((_pulseAnimation.value - 0.8) / 0.4 * 0.4),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                    ),
                    child: Icon(
                      Icons.people_alt_rounded,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // Rotating dots indicator
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Fetching users...',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Finding people to connect with',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String title,
    IconData icon, {
    String? subtitle,
    String? badge,
  }) {
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (subtitle != null)
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              badge,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveConnectionCard(
    BuildContext context,
    RandomChatLoaded state,
    ThemeData theme,
  ) {
    final connection = state.activeConnection!;
    final authState = context.read<AuthBloc>().state;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';

    final otherName = connection.getOtherUserName(currentUserId);
    final otherPhoto = connection.getOtherUserPhotoUrl(currentUserId);
    final otherUserId = connection.getOtherUserId(currentUserId);

    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: CachedAvatar(
                    imageUrl: otherPhoto,
                    name: otherName,
                    radius: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connected with $otherName!',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        'Your Random Chat for today',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final conversationId = Conversation.createConversationId(
                          currentUserId, otherUserId);
                      context.push(
                        Routes.chatWith(conversationId),
                        extra: {
                          'currentUserId': currentUserId,
                          'otherUserId': otherUserId,
                          'otherUserName': otherName,
                          'otherUserPhotoUrl': otherPhoto,
                        },
                      );
                    },
                    icon: const Icon(Icons.chat),
                    label: const Text('Start Chat'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      context.push(
                        Routes.userProfileWith(otherUserId),
                        extra: {
                          'displayName': otherName,
                          'photoUrl': otherPhoto,
                        },
                      );
                    },
                    icon: const Icon(Icons.person),
                    label: const Text('Profile'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRequestCard(
    BuildContext context,
    RandomChatRequest request,
    RandomChatLoaded state,
    ThemeData theme,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          context.push(
            Routes.userProfileWith(request.senderId),
            extra: {
              'displayName': request.senderDisplayName,
              'photoUrl': request.senderPhotoUrl,
            },
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CachedAvatar(
                imageUrl: request.senderPhotoUrl,
                name: request.senderDisplayName,
                radius: 28,
              ),
              const SizedBox(width: 14),
              // User info - takes available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.senderDisplayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Wants to chat with you',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Accept button
                  IconButton.filled(
                    onPressed: state.hasActiveConnection
                        ? null
                        : () {
                            context.read<RandomChatBloc>().add(
                                  RandomChatAcceptRequest(
                                      requestId: request.id),
                                );
                          },
                    icon: const Icon(Icons.check, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.all(10),
                    ),
                    tooltip: 'Accept',
                  ),
                  const SizedBox(width: 8),
                  // Reject button
                  IconButton.outlined(
                    onPressed: () {
                      context.read<RandomChatBloc>().add(
                            RandomChatRejectRequest(requestId: request.id),
                          );
                    },
                    icon: const Icon(Icons.close, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                          color:
                              theme.colorScheme.error.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.all(10),
                    ),
                    tooltip: 'Reject',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(
    BuildContext context,
    RandomChatUser user,
    RandomChatLoaded state,
    ThemeData theme,
  ) {
    final alreadySent = state.sentRequestUserIds.contains(user.userId);
    final isProcessing = state.processingUserIds.contains(user.userId);
    final hasConnection = state.hasActiveConnection;
    final canSend = !alreadySent &&
        !isProcessing &&
        !hasConnection &&
        user.canReceiveRequests;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          context.push(
            Routes.userProfileWith(user.userId),
            extra: {
              'displayName': user.displayName,
              'photoUrl': user.photoUrl,
            },
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CachedAvatar(
                imageUrl: user.photoUrl,
                name: user.displayName,
                radius: 28,
              ),
              const SizedBox(width: 14),
              // User info - takes available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user.mood != null && user.mood!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        user.mood!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (user.bio != null && user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.bio!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Action button - fixed width
              if (alreadySent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Sent',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (!user.canReceiveRequests)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Full',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: canSend
                      ? () {
                          context.read<RandomChatBloc>().add(
                                RandomChatSendRequest(
                                  receiverId: user.userId,
                                  receiverDisplayName: user.displayName,
                                  receiverPhotoUrl: user.photoUrl,
                                ),
                              );
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: isProcessing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(
                    'Send',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No users available right now',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later — new users join every day!',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('How Random Chat works'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoDialogRow(theme, 'You get up to 10 new random users each day'),
            _infoDialogRow(theme, 'Send requests to start a conversation'),
            _infoDialogRow(theme, 'You can receive up to 10 requests per day'),
            _infoDialogRow(theme, 'Everything resets at midnight'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _infoDialogRow(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: TextStyle(color: theme.colorScheme.primary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
