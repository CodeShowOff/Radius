import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/news_location.dart';
import '../bloc/news_location_bloc.dart';
import '../widgets/manual_location_picker.dart';

/// Page for setting up the user's news location.
///
/// Offers two paths:
/// 1. **GPS detection** — auto-detect via GPS + reverse geocoding
/// 2. **Manual entry** — pick country and state/region from dropdowns
///
/// After detection, shows a confirmation step before saving.
class NewsLocationSetupPage extends StatelessWidget {
  final String userId;

  const NewsLocationSetupPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Your Location'),
      ),
      body: SafeArea(
        child: BlocConsumer<NewsLocationBloc, NewsLocationState>(
          listener: (context, state) {
            if (state.status == NewsLocationStatus.ready) {
              Navigator.of(context).pop(state.location);
            }
          },
          builder: (context, state) {
            return switch (state.status) {
              NewsLocationStatus.initial ||
              NewsLocationStatus.loading =>
                const _LoadingView(),
              NewsLocationStatus.needsSetup =>
                _SetupChoiceView(userId: userId),
              NewsLocationStatus.detecting =>
                const _DetectingView(),
              NewsLocationStatus.detected =>
                _ConfirmLocationView(
                  location: state.location!,
                  userId: userId,
                ),
              NewsLocationStatus.saving =>
                const _SavingView(),
              NewsLocationStatus.error =>
                _ErrorView(
                  message: state.errorMessage ?? 'An unknown error occurred.',
                ),
              NewsLocationStatus.ready =>
                const _LoadingView(), // Brief flash before pop
            };
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading indicator
// ---------------------------------------------------------------------------
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Checking location...'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Setup Choice — GPS vs Manual
// ---------------------------------------------------------------------------
class _SetupChoiceView extends StatefulWidget {
  final String userId;

  const _SetupChoiceView({required this.userId});

  @override
  State<_SetupChoiceView> createState() => _SetupChoiceViewState();
}

class _SetupChoiceViewState extends State<_SetupChoiceView> {
  bool _showManualPicker = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showManualPicker) {
      return _ManualEntryView(
        onBack: () => setState(() => _showManualPicker = false),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Where are you located?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'We use your location to show news and updates '
            'from your area. You can change this anytime.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // GPS option
          _OptionCard(
            icon: Icons.my_location,
            title: 'Use GPS',
            subtitle: 'Automatically detect your location',
            recommended: true,
            onTap: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationGpsRequested(),
                  );
            },
          ),

          const SizedBox(height: 16),

          // Manual option
          _OptionCard(
            icon: Icons.edit_location_alt_outlined,
            title: 'Enter Manually',
            subtitle: 'Select your country and region',
            onTap: () {
              setState(() => _showManualPicker = true);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Option card
// ---------------------------------------------------------------------------
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool recommended;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.recommended = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: recommended ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: recommended
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: recommended ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GPS detecting view
// ---------------------------------------------------------------------------
class _DetectingView extends StatelessWidget {
  const _DetectingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Detecting your location...',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm detected / manually selected location
// ---------------------------------------------------------------------------
class _ConfirmLocationView extends StatelessWidget {
  final NewsLocation location;
  final String userId;

  const _ConfirmLocationView({
    required this.location,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Location Found',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'You will see news from:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Location display card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.location_on,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    location.displayString,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location.country,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (location.source == LocationSource.gps) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.gps_fixed,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Detected via GPS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const Spacer(),

          // Confirm button
          FilledButton.icon(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    NewsLocationSaveRequested(userId: userId),
                  );
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirm Location'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Choose different location
          OutlinedButton(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationChangeRequested(),
                  );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Choose Different Location'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saving indicator
// ---------------------------------------------------------------------------
class _SavingView extends StatelessWidget {
  const _SavingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Saving your location...'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.error_outline,
            size: 72,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 24),
          Text(
            'Something went wrong',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationGpsRequested(),
                  );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try GPS Again'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationChangeRequested(),
                  );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Enter Location Manually'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual entry view — wraps ManualLocationPicker
// ---------------------------------------------------------------------------
class _ManualEntryView extends StatelessWidget {
  final VoidCallback onBack;

  const _ManualEntryView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Text(
                'Select Location',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose your country and region to see local news.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ManualLocationPicker(
            onLocationSelected: (country, state) {
              context.read<NewsLocationBloc>().add(
                    NewsLocationManualSelected(
                      district: state,
                      city: state, // Use state/region as city for manual entry
                      country: country,
                    ),
                  );
            },
          ),
        ],
      ),
    );
  }
}
