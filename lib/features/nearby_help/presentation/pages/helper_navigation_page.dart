import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/help_request.dart';
import '../../domain/entities/help_request_status.dart';
import '../bloc/nearby_help_bloc.dart';
import '../widgets/help_status_indicator.dart';

/// Page for assigned helpers to navigate to the seeker.
///
/// Shows:
/// - Seeker's exact location on map
/// - Seeker details
/// - Navigation options
/// - Status updates
/// - Complete help button
class HelperNavigationPage extends StatefulWidget {
  final String requestId;

  const HelperNavigationPage({
    super.key,
    required this.requestId,
  });

  @override
  State<HelperNavigationPage> createState() => _HelperNavigationPageState();
}

class _HelperNavigationPageState extends State<HelperNavigationPage> {
  @override
  void initState() {
    super.initState();
    context.read<NearbyHelpBloc>().add(
          NearbyHelpSubscribeToRequest(widget.requestId),
        );
  }

  @override
  void dispose() {
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
        title: const Text('Navigate to Help'),
        actions: [
          IconButton(
            onPressed: () => _showInfoDialog(context),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: BlocConsumer<NearbyHelpBloc, NearbyHelpState>(
        listener: (context, state) {
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.successMessage!)),
            );
          }
          if (state.viewedRequest?.status == HelpRequestStatus.resolved ||
              state.viewedRequest?.status == HelpRequestStatus.cancelled) {
            // Request completed or cancelled, go back
            Future.delayed(const Duration(seconds: 2), () {
              if (context.mounted) context.pop();
            });
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
                ],
              ),
            );
          }

          // Check if user is the assigned helper
          if (request.helperUserId != state.userId) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.block,
                    size: 64,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Not Authorized',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You are not the assigned helper for this request.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          return _buildContent(context, state, request, theme);
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    NearbyHelpState state,
    HelpRequest request,
    ThemeData theme,
  ) {
    final isUpdating = state.status == NearbyHelpStatus.updating;

    return Column(
      children: [
        // Google Maps showing seeker location
        Expanded(
          flex: 2,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(request.latitude, request.longitude),
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('seeker'),
                    position: LatLng(request.latitude, request.longitude),
                    infoWindow: InfoWindow(
                      title: request.seekerName,
                      snippet: request.topic ?? 'Needs help',
                    ),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                  ),
                },
                circles: {
                  Circle(
                    circleId: const CircleId('radius'),
                    center: LatLng(request.latitude, request.longitude),
                    radius: request.radius.meters.toDouble(),
                    fillColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    strokeColor: theme.colorScheme.primary.withValues(alpha: 0.5),
                    strokeWidth: 2,
                  ),
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
              // Navigate button overlay
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.extended(
                  onPressed: () => _openMapsNavigation(request),
                  icon: const Icon(Icons.navigation),
                  label: const Text('Navigate'),
                ),
              ),
            ],
          ),
        ),

        // Details panel
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status
                Center(child: HelpStatusBadge(request: request)),
                const SizedBox(height: 16),

                // Seeker info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CachedAvatar(
                          imageUrl: request.seekerPhotoUrl,
                          name: request.seekerName,
                          radius: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.seekerName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (request.topic != null)
                                Text(
                                  request.topic!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                if (!request.helperOnTheWay) ...[
                  FilledButton.icon(
                    onPressed: isUpdating
                        ? null
                        : () {
                            context.read<NearbyHelpBloc>().add(
                                  NearbyHelpMarkOnTheWay(widget.requestId),
                                );
                          },
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Mark as On The Way'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                FilledButton.icon(
                  onPressed: isUpdating
                      ? null
                      : () => _showCompleteConfirmation(context),
                  icon: isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: const Text('Mark Help as Completed'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMapsNavigation(HelpRequest request) async {
    final lat = request.latitude;
    final lng = request.longitude;

    // Try Google Maps first, then fall back to default maps
    final googleMapsUrl = Uri.parse(
      'google.navigation:q=$lat,$lng&mode=w',
    );
    final appleMapsUrl = Uri.parse(
      'https://maps.apple.com/?daddr=$lat,$lng&dirflg=w',
    );
    final genericUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl);
      } else {
        await launchUrl(genericUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open maps: $e')),
        );
      }
    }
  }

  void _showCompleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Help?'),
        content: const Text(
          'Are you sure you want to mark this help as completed? '
          'This will notify the seeker and close the request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not Yet'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<NearbyHelpBloc>().add(
                    NearbyHelpMarkCompleted(widget.requestId),
                  );
            },
            child: const Text('Yes, Complete'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Helper Information'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Tap "Navigate" to open maps with directions'),
            SizedBox(height: 8),
            Text('• Mark as "On The Way" to notify the seeker'),
            SizedBox(height: 8),
            Text('• Mark as "Completed" when done helping'),
            SizedBox(height: 8),
            Text('• The seeker can see your status in real-time'),
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
}
