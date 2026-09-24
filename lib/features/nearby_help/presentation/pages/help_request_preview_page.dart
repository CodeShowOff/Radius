import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/help_request.dart';
import '../../domain/entities/help_request_status.dart';
import '../bloc/nearby_help_bloc.dart';
import '../widgets/help_status_indicator.dart';

/// Page showing a help request preview for potential helpers.
///
/// Shows:
/// - Seeker info
/// - Help topic
/// - Approximate distance
/// - Request status
/// - Accept/Decline buttons
/// - Confirmation dialog if opened from notification
class HelpRequestPreviewPage extends StatefulWidget {
  final String requestId;
  final bool confirmAcceptance;

  const HelpRequestPreviewPage({
    super.key,
    required this.requestId,
    this.confirmAcceptance = false,
  });

  @override
  State<HelpRequestPreviewPage> createState() => _HelpRequestPreviewPageState();
}

class _HelpRequestPreviewPageState extends State<HelpRequestPreviewPage> {
  bool _hasShownConfirmDialog = false;

  @override
  void initState() {
    super.initState();
    // Subscribe to real-time updates for this request
    context.read<NearbyHelpBloc>().add(
          NearbyHelpSubscribeToRequest(widget.requestId),
        );
  }

  @override
  void dispose() {
    // Unsubscribe when leaving the page
    context.read<NearbyHelpBloc>().add(
          const NearbyHelpUnsubscribeFromRequest(),
        );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Help Request',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocConsumer<NearbyHelpBloc, NearbyHelpState>(
        listenWhen: (previous, current) {
          return (previous.errorMessage == null && current.errorMessage != null) ||
              (previous.successMessage == null && current.successMessage != null);
        },
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
            context.read<NearbyHelpBloc>().add(const NearbyHelpClearMessages());
          }
          if (state.successMessage != null &&
              state.viewedRequest?.helperUserId == state.userId) {
            // User successfully accepted the request
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.successMessage!)),
            );
            context.read<NearbyHelpBloc>().add(const NearbyHelpClearMessages());
            // Navigate to helper navigation page
            context.pushReplacement(
              Routes.nearbyHelpHelperNavigationWith(widget.requestId),
            );
          }
        },
        builder: (context, state) {
          final request = state.viewedRequest;

          if (state.status == NearbyHelpStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (request == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Request not found',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This help request may have been cancelled or expired.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          // Show confirmation dialog if opened from notification
          if (widget.confirmAcceptance && !_hasShownConfirmDialog) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showAcceptanceConfirmationDialog(context, request, state);
            });
          }

          return _buildContent(context, state, request);
        },
      ),
    );
  }

  /// Show confirmation dialog asking if the user wants to accept this help request.
  void _showAcceptanceConfirmationDialog(
    BuildContext context,
    HelpRequest request,
    NearbyHelpState state,
  ) {
    if (_hasShownConfirmDialog) return;
    _hasShownConfirmDialog = true;

    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.help_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Help Request Received'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.seekerName} needs help nearby.',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            if (request.topic != null && request.topic!.isNotEmpty) ...[
              Text(
                'Topic: ${request.topic}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Distance: ~${request.radius.meters}m',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Do you want to accept this help request?',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Go back to previous page
              context.pop();
            },
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Accept the request if not already helping
              if (request.helperUserId != state.userId) {
                context.read<NearbyHelpBloc>().add(
                      NearbyHelpAcceptRequest(request.id),
                    );
              }
              // Otherwise just proceed to view the request
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    NearbyHelpState state,
    HelpRequest request,
  ) {
    final theme = Theme.of(context);
    final isAccepting = state.status == NearbyHelpStatus.accepting;
    final isOwnRequest = request.seekerUserId == state.userId;
    final isAlreadyHelping = request.helperUserId == state.userId;
    final isTaken = request.status != HelpRequestStatus.open && !isAlreadyHelping;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status badge
          Center(child: HelpStatusBadge(request: request)),
          const SizedBox(height: 24),

          // Seeker info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CachedAvatar(
                    imageUrl: request.seekerPhotoUrl,
                    name: request.seekerName,
                    radius: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    request.seekerName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'needs help nearby',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Help topic (if provided)
          if (request.topic != null && request.topic!.isNotEmpty) ...[
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Help Topic',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      request.topic!,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Distance and radius info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '~${request.radius.meters}m',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Search radius',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getTimeAgo(request.createdAt),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Requested',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action section
          if (isTaken) ...[
            _buildTakenMessage(theme, request),
          ] else if (isOwnRequest) ...[
            _buildOwnRequestMessage(theme),
          ] else if (isAlreadyHelping) ...[
            _buildAlreadyHelpingMessage(theme, request),
          ] else ...[
            _buildAcceptSection(theme, isAccepting),
          ],
        ],
      ),
    );
  }

  Widget _buildTakenMessage(ThemeData theme, HelpRequest request) {
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.person_pin,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Request Already Taken',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Another helper is already on the way to assist.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnRequestMessage(ThemeData theme) {
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'This Is Your Request',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You cannot help your own request.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlreadyHelpingMessage(ThemeData theme, HelpRequest request) {
    return Column(
      children: [
        Card(
          color: Colors.green.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 48,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                Text(
                  'You\'re Assigned!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You are the assigned helper for this request.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.pushReplacement(
              Routes.nearbyHelpHelperNavigationWith(widget.requestId),
            ),
            icon: const Icon(Icons.navigation),
            label: const Text('View Navigation'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAcceptSection(ThemeData theme, bool isAccepting) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Are you available to help right now?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'If you accept, we\'ll ask for your location '
                'so you can navigate to help them.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isAccepting ? null : () => context.pop(),
                icon: const Icon(Icons.close),
                label: const Text('No / Dismiss'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: isAccepting ? null : _acceptRequest,
                icon: isAccepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(isAccepting ? 'Accepting...' : 'Yes, I Can Help'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _acceptRequest() async {
    // Request location permission before accepting
    // Helper needs location to navigate to the seeker
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location services to help navigate to the person in need.'),
          ),
        );
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is needed to navigate to help.'),
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is permanently denied. Please enable it in settings to help.'),
          ),
        );
      }
      return;
    }

    // Now accept the request
    if (mounted) {
      context.read<NearbyHelpBloc>().add(
            NearbyHelpAcceptRequest(widget.requestId),
          );
    }
  }

  String _getTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
