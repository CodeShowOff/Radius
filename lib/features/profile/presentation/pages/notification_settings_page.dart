import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/profile_bloc.dart';

/// Notification settings page for managing push notification preferences.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _directMessages = true;
  bool _locationGroups = true;
  bool _nearbyGroups = true;
  bool _randomGroups = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentSettings();
    });
  }

  void _loadCurrentSettings() {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      setState(() {
        _directMessages = profileState.profile.notifyDirectMessages;
        _locationGroups = profileState.profile.notifyLocationGroups;
        _nearbyGroups = profileState.profile.notifyNearbyGroups;
        _randomGroups = profileState.profile.notifyRandomGroups;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return BlocListener<ProfileBloc, ProfileState>(
      listenWhen: (previous, current) =>
          current is ProfileError && previous != current,
      listener: (context, state) {
        if (state is ProfileError) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${state.message}'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Notification Settings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
          children: [
            // Header
            const Text(
              'Chat Notifications',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Control which types of messages send you push notifications',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Notification toggles
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.message),
                    title: const Text('Direct Messages'),
                    subtitle: const Text('1-on-1 conversations'),
                    value: _directMessages,
                    onChanged: (value) {
                      setState(() => _directMessages = value);
                      unawaited(_saveNotificationSettings());
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.location_on),
                    title: const Text('Location Groups'),
                    subtitle: const Text('Location-based group chats'),
                    value: _locationGroups,
                    onChanged: (value) {
                      setState(() => _locationGroups = value);
                      unawaited(_saveNotificationSettings());
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.bluetooth),
                    title: const Text('Nearby Groups'),
                    subtitle: const Text('Bluetooth-based group chats'),
                    value: _nearbyGroups,
                    onChanged: (value) {
                      setState(() => _nearbyGroups = value);
                      unawaited(_saveNotificationSettings());
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.group),
                    title: const Text('Random Groups'),
                    subtitle: const Text('Internet-based community groups'),
                    value: _randomGroups,
                    onChanged: (value) {
                      setState(() => _randomGroups = value);
                      unawaited(_saveNotificationSettings());
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Info card
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'About Notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'These settings control push notifications. You\'ll still receive messages in the app, but won\'t get notified when the app is closed or in the background.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNotificationSettings() async {
    context.read<ProfileBloc>().add(ProfileNotificationSettingsUpdated(
          notifyDirectMessages: _directMessages,
          notifyLocationGroups: _locationGroups,
          notifyNearbyGroups: _nearbyGroups,
          notifyRandomGroups: _randomGroups,
        ));
  }
}
