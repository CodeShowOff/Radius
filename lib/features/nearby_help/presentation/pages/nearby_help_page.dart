import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../domain/entities/help_request_status.dart';
import '../bloc/nearby_help_bloc.dart';
import '../widgets/help_request_card.dart';

/// Main page for the Nearby Help feature.
///
/// Shows:
/// - Active help request (if any)
/// - Button to request help
/// - Active helper assignments
/// - Settings access
class NearbyHelpPage extends StatefulWidget {
  const NearbyHelpPage({super.key});

  @override
  State<NearbyHelpPage> createState() => _NearbyHelpPageState();
}

class _NearbyHelpPageState extends State<NearbyHelpPage> {
  @override
  void initState() {
    super.initState();
    _initializeBloc();
  }

  void _initializeBloc() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final profileState = context.read<ProfileBloc>().state;
      String userName = authState.user.displayName ?? 'User';
      String? userPhotoUrl = authState.user.avatarUrl;

      if (profileState is ProfileLoaded) {
        userName = profileState.profile.name.isNotEmpty
            ? profileState.profile.name
            : userName;
        userPhotoUrl = profileState.profile.photoUrl ?? userPhotoUrl;
      }

      context.read<NearbyHelpBloc>().add(NearbyHelpInitialize(
            userId: authState.user.id,
            userName: userName,
            userPhotoUrl: userPhotoUrl,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Help'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.nearbyHelpSettings),
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: BlocConsumer<NearbyHelpBloc, NearbyHelpState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.successMessage!)),
            );
          }
        },
        builder: (context, state) {
          if (state.status == NearbyHelpStatus.initial ||
              state.status == NearbyHelpStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<NearbyHelpBloc>().add(const NearbyHelpLoadLocations());
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active request section
                  if (state.hasActiveRequest) ...[
                    _buildActiveRequestSection(context, state),
                    const SizedBox(height: 24),
                  ],

                  // Helper assignments section
                  if (state.helperRequests.isNotEmpty) ...[
                    _buildHelperSection(context, state),
                    const SizedBox(height: 24),
                  ],

                  // Main action section
                  if (!state.hasActiveRequest) ...[
                    _buildMainActionSection(context, state),
                  ],

                  // Location setup prompt
                  if (!state.hasLocations) ...[
                    const SizedBox(height: 24),
                    _buildLocationSetupPrompt(context),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveRequestSection(BuildContext context, NearbyHelpState state) {
    final theme = Theme.of(context);
    final request = state.activeRequest!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Active Request',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        HelpRequestCard(
          request: request,
          showHelper: true,
          onTap: () => context.push(
            Routes.nearbyHelpRequestDetailWith(request.id),
          ),
        ),
        const SizedBox(height: 12),
        if (request.status == HelpRequestStatus.open)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _showCancelConfirmation(context, request.id);
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Request'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
              ),
            ),
          )
        else if (request.status == HelpRequestStatus.inProgress)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                context.read<NearbyHelpBloc>().add(
                      NearbyHelpMarkCompleted(request.id),
                    );
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Mark as Completed'),
            ),
          ),
      ],
    );
  }

  Widget _buildHelperSection(BuildContext context, NearbyHelpState state) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.volunteer_activism,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'You\'re Helping',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...state.helperRequests.map((request) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HelpRequestCompactCard(
                request: request,
                onTap: () => context.push(
                  Routes.nearbyHelpHelperNavigationWith(request.id),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildMainActionSection(BuildContext context, NearbyHelpState state) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sos,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Need Help Nearby?',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Request help from users in your vicinity. '
              'They\'ll be notified and can come assist you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _requestHelp(context),
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Get Nearby Help'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSetupPrompt(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Set Up Your Locations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Save your home and work locations to receive help alerts when you\'re nearby.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.push(Routes.nearbyHelpSettings),
              child: const Text('Set Up Locations'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestHelp(BuildContext context) async {
    // Check location permission
    final status = await Permission.location.status;
    if (!status.isGranted) {
      final result = await Permission.location.request();
      if (!result.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to request help'),
            ),
          );
        }
        return;
      }
    }

    if (context.mounted) {
      context.push(Routes.nearbyHelpCreateRequest);
    }
  }

  void _showCancelConfirmation(BuildContext context, String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text(
          'Are you sure you want to cancel your help request? '
          'Helpers will no longer be able to respond.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep Request'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<NearbyHelpBloc>().add(
                    NearbyHelpCancelRequest(requestId),
                  );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
  }
}
