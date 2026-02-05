import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/entities/user_location.dart';
import '../bloc/nearby_help_bloc.dart';
import '../widgets/location_card.dart';

/// Settings page for Nearby Help feature.
///
/// Allows users to:
/// - Set/update home and work locations
/// - Toggle receiving help alerts
/// - Manage saved locations
class NearbyHelpSettingsPage extends StatelessWidget {
  const NearbyHelpSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nearby Help Settings',
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
                backgroundColor: theme.colorScheme.error,
              ),
            );
            context.read<NearbyHelpBloc>().add(const NearbyHelpClearMessages());
          }
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.successMessage!)),
            );
            context.read<NearbyHelpBloc>().add(const NearbyHelpClearMessages());
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Help alerts toggle
                _buildAlertsSection(context, state, theme),
                const SizedBox(height: 24),

                // Saved locations
                _buildLocationsSection(context, state, theme),
                const SizedBox(height: 24),

                // Info section
                _buildInfoSection(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlertsSection(
    BuildContext context,
    NearbyHelpState state,
    ThemeData theme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Help Alerts',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Receive notifications when someone nearby needs help.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Receive help alerts'),
              subtitle: Text(
                state.receiveHelpAlerts
                    ? 'You\'ll be notified when someone nearby needs help'
                    : 'You won\'t receive help requests',
              ),
              value: state.receiveHelpAlerts,
              onChanged: (value) {
                context.read<NearbyHelpBloc>().add(
                      NearbyHelpUpdateSettings(receiveHelpAlerts: value),
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationsSection(
    BuildContext context,
    NearbyHelpState state,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saved Locations',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Save your frequent locations to receive help alerts when nearby.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),

        // Home location
        LocationCard(
          location: state.homeLocation,
          type: LocationType.home,
          onSetLocation: () => _setLocation(context, LocationType.home),
          onRemove: state.homeLocation != null
              ? () => _confirmRemoveLocation(context, LocationType.home)
              : null,
          onToggleActive: state.homeLocation != null
              ? () {
                  context.read<NearbyHelpBloc>().add(
                        NearbyHelpToggleLocation(
                          type: LocationType.home,
                          isActive: !state.homeLocation!.isActive,
                        ),
                      );
                }
              : null,
        ),
        const SizedBox(height: 12),

        // Work location
        LocationCard(
          location: state.workLocation,
          type: LocationType.work,
          onSetLocation: () => _setLocation(context, LocationType.work),
          onRemove: state.workLocation != null
              ? () => _confirmRemoveLocation(context, LocationType.work)
              : null,
          onToggleActive: state.workLocation != null
              ? () {
                  context.read<NearbyHelpBloc>().add(
                        NearbyHelpToggleLocation(
                          type: LocationType.work,
                          isActive: !state.workLocation!.isActive,
                        ),
                      );
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildInfoSection(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Privacy & Safety',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoItem(
              icon: Icons.location_off,
              text: 'Your exact location is only shared after you accept a help request',
            ),
            const SizedBox(height: 8),
            _InfoItem(
              icon: Icons.visibility_off,
              text: 'Other users only see approximate distance before you help',
            ),
            const SizedBox(height: 8),
            _InfoItem(
              icon: Icons.block,
              text: 'You can disable alerts anytime',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setLocation(BuildContext context, LocationType type) async {
    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location services are disabled. Please enable them in settings.'),
          ),
        );
      }
      return;
    }

    // Check and request permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required'),
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. Please enable them in settings.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Getting location...'),
            ],
          ),
        ),
      );

      try {
        // CRITICAL FIX: Use best accuracy for more precise location.
        // For small radius values (10m, 50m), high accuracy is essential.
        // The previous 'high' setting may not be sufficient for all devices.
        // Using 'best' ensures we get the most accurate GPS reading.
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 30), // Increased timeout for better accuracy
          ),
        );
        
        // Log the accuracy for debugging
        debugPrint('Got location: lat=${position.latitude}, lon=${position.longitude}, accuracy=${position.accuracy}m');

        if (context.mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          
          // Warn user if accuracy is poor for small radius scenarios
          if (position.accuracy > 50) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Location saved, but GPS accuracy is ${position.accuracy.toStringAsFixed(0)}m. '
                  'For best results, try again outdoors with clear sky view.',
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }

          context.read<NearbyHelpBloc>().add(
                NearbyHelpSaveLocation(
                  type: type,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  address: type == LocationType.home
                      ? 'Home Location'
                      : 'Work Location',
                ),
              );
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to get location: $e')),
          );
        }
      }
    }
  }

  void _confirmRemoveLocation(BuildContext context, LocationType type) {
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<NearbyHelpBloc>();
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${type.displayName} Location?'),
        content: Text(
          'You will no longer receive help alerts when you\'re at your ${type.displayName.toLowerCase()}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              bloc.add(NearbyHelpDeleteLocation(type));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
