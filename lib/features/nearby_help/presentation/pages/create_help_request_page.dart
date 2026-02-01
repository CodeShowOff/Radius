import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/help_radius.dart';
import '../bloc/nearby_help_bloc.dart';
import '../widgets/radius_selector.dart';

/// Page for creating a new help request.
///
/// Steps:
/// 1. Get current location
/// 2. Select radius
/// 3. Optionally add topic
/// 4. Confirm and submit
class CreateHelpRequestPage extends StatefulWidget {
  const CreateHelpRequestPage({super.key});

  @override
  State<CreateHelpRequestPage> createState() => _CreateHelpRequestPageState();
}

class _CreateHelpRequestPageState extends State<CreateHelpRequestPage> {
  final _topicController = TextEditingController();
  HelpRadius? _selectedRadius;
  double? _latitude;
  double? _longitude;
  bool _isGettingLocation = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _locationError = null;
    });

    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled. Please enable them in settings.';
          _isGettingLocation = false;
        });
        return;
      }

      // Check and request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permission denied';
            _isGettingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permissions are permanently denied. Please enable them in settings.';
          _isGettingLocation = false;
        });
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isGettingLocation = false;
      });
    } catch (e) {
      setState(() {
        _locationError = 'Failed to get location: $e';
        _isGettingLocation = false;
      });
    }
  }

  bool get _canSubmit =>
      _latitude != null &&
      _longitude != null &&
      _selectedRadius != null &&
      !_isGettingLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Nearby Help'),
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
          if (state.successMessage != null && state.activeRequest != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.successMessage!)),
            );
            context.pop(); // Go back after successful creation
          }
        },
        builder: (context, state) {
          final isCreating = state.status == NearbyHelpStatus.creating;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Location status
                _buildLocationSection(theme),
                const SizedBox(height: 24),

                // Radius selector
                RadiusSelector(
                  selectedRadius: _selectedRadius,
                  onSelected: (radius) {
                    setState(() => _selectedRadius = radius);
                  },
                  enabled: !isCreating,
                ),
                const SizedBox(height: 24),

                // Topic input
                _buildTopicSection(theme, isCreating),
                const SizedBox(height: 32),

                // Submit button
                FilledButton.icon(
                  onPressed: _canSubmit && !isCreating ? _submitRequest : null,
                  icon: isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(isCreating ? 'Creating...' : 'Request Help'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

                const SizedBox(height: 16),

                // Info text
                Text(
                  'Nearby users who have opted in will be notified. '
                  'The first helper to accept will be assigned to help you.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocationSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.my_location,
                  color: _locationError != null
                      ? theme.colorScheme.error
                      : _latitude != null
                          ? Colors.green
                          : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Location',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isGettingLocation)
                        Text(
                          'Getting your location...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      else if (_locationError != null)
                        Text(
                          _locationError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        )
                      else if (_latitude != null)
                        Text(
                          'Location acquired ✓',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isGettingLocation)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_locationError != null)
                  IconButton(
                    onPressed: _getCurrentLocation,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry',
                  )
                else if (_latitude != null)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicSection(ThemeData theme, bool isCreating) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Help Topic (Optional)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Briefly describe what you need help with',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _topicController,
          enabled: !isCreating,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'e.g., Car breakdown, Need directions, etc.',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.help_outline),
          ),
        ),
      ],
    );
  }

  void _submitRequest() {
    if (!_canSubmit) return;

    context.read<NearbyHelpBloc>().add(NearbyHelpCreateRequest(
          latitude: _latitude!,
          longitude: _longitude!,
          radius: _selectedRadius!,
          topic: _topicController.text.trim().isNotEmpty
              ? _topicController.text.trim()
              : null,
        ));
  }
}
