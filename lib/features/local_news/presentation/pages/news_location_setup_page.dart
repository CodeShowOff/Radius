import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/news_location.dart';
import '../bloc/news_location_bloc.dart';
import '../widgets/manual_location_picker.dart';

/// Page for setting up the user's news location.
///
/// The user picks their country and city from dropdowns.
/// After selection, shows a confirmation step before saving.
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
                _ManualEntryView(userId: userId),
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
                  userId: userId,
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
// Manual entry view â€” wraps ManualLocationPicker
// ---------------------------------------------------------------------------
class _ManualEntryView extends StatelessWidget {
  final String userId;

  const _ManualEntryView({required this.userId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          const SizedBox(height: 24),
          Text(
            'Pick your country and city from the list below.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ManualLocationPicker(
            onLocationSelected: (country, city) {
              context.read<NewsLocationBloc>().add(
                    NewsLocationManualSelected(
                      city: city,
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
  final String userId;

  const _ErrorView({required this.message, required this.userId});

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
                    const NewsLocationChangeRequested(),
                  );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
