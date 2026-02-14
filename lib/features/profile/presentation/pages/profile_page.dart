import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../nearby_help/data/nearby_help_service.dart';
import '../bloc/profile_bloc.dart';

/// User profile page.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // Load profile when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        context
            .read<ProfileBloc>()
            .add(ProfileLoadRequested(authState.user.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(Routes.login);
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          final user = authState is AuthAuthenticated ? authState.user : null;
          final email = user?.email ?? '';

          return BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, profileState) {
              // Use profile name if loaded, fallback to auth displayName
              String displayName = user?.displayName ?? 'User';
              String? photoUrl = user?.avatarUrl;
              String bio = '';
              String? vibe;
              String? mood;
              String? discoveryUsername;

              if (profileState is ProfileLoaded) {
                final profile = profileState.profile;
                if (profile.name.isNotEmpty) {
                  displayName = profile.name;
                }
                if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty) {
                  photoUrl = profile.photoUrl;
                }
                bio = profile.bio;
                vibe = profile.vibe;
                mood = profile.mood;
                discoveryUsername = profile.discoveryUsername;
              }

              return Scaffold(
                appBar: AppBar(
                  title: const Text(
                    'Profile',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                body: SafeArea(
                  bottom:
                      false, // Let content extend to bottom with custom padding
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + MediaQuery.of(context).padding.bottom + 24,
                    ),
                    child: Column(
                      children: [
                        // Avatar
                        CircleAvatar(
                          radius: 50,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage:
                              photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Display name
                        Text(
                          displayName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 20),

                        // Profile Info Card
                        Card(
                          elevation: 0,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProfileInfoField(
                                  icon: Icons.alternate_email,
                                  label: 'Username',
                                  value: discoveryUsername,
                                ),
                                const Divider(height: 24),
                                _ProfileInfoField(
                                  icon: Icons.description_outlined,
                                  label: 'Bio',
                                  value: bio.isNotEmpty ? bio : null,
                                ),
                                const Divider(height: 24),
                                _ProfileInfoField(
                                  icon: Icons.mood,
                                  label: 'Vibe',
                                  value: vibe,
                                ),
                                const Divider(height: 24),
                                _ProfileInfoField(
                                  icon: Icons.sentiment_satisfied_alt,
                                  label: 'Mood',
                                  value: mood,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Stats
                        BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                          builder: (context, connectionState) {
                            final connectionsCount =
                                connectionState.connections.length;
                            
                            // Get helps done count where user was the helper
                            final userId = user?.id ?? '';
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _StatItem(
                                  label: 'Connections',
                                  value: connectionsCount.toString(),
                                ),
                                StreamBuilder<int>(
                                  stream: getIt<NearbyHelpService>().streamHelpsDoneCount(userId),
                                  builder: (context, snapshot) {
                                    final helpsDone = snapshot.data ?? 0;
                                    return _StatItem(
                                      label: 'Helps Done',
                                      value: helpsDone.toString(),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 32),

                        // Profile options
                        _ProfileOption(
                          icon: Icons.edit_outlined,
                          title: 'Edit Profile',
                          onTap: () => context.push(Routes.editProfile),
                        ),
                        _ProfileOption(
                          icon: Icons.bluetooth,
                          title: 'Bluetooth Settings',
                          onTap: () => context.push(Routes.bluetoothSettings),
                        ),
                        _ProfileOption(
                          icon: Icons.location_on_outlined,
                          title: 'Location Settings',
                          onTap: () => context.push(Routes.locationSettings),
                        ),
                        _ProfileOption(
                          icon: Icons.palette_outlined,
                          title: 'Appearance',
                          onTap: () => context.push(Routes.appearanceSettings),
                        ),
                        _ProfileOption(
                          icon: Icons.notifications_outlined,
                          title: 'Notification Settings',
                          onTap: () =>
                              context.push(Routes.notificationSettings),
                        ),
                        _ProfileOption(
                          icon: Icons.visibility_outlined,
                          title: 'Privacy Settings',
                          onTap: () => context.push(Routes.privacySettings),
                        ),
                        _ProfileOption(
                          icon: Icons.help_outline,
                          title: 'Help & Support',
                          onTap: () => context.push(Routes.helpSupport),
                        ),
                        const SizedBox(height: 24),

                        // Sign out button
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: _SignOutButton(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;

        return OutlinedButton.icon(
          onPressed: isLoading ? null : () => _showSignOutDialog(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          ),
          icon: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.error,
                  ),
                )
              : const Icon(Icons.logout),
          label: Text(isLoading ? 'Signing out...' : 'Sign Out'),
        );
      },
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AuthBloc>().add(const AuthSignOutRequested());
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ProfileInfoField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _ProfileInfoField({
    required this.icon,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value?.isNotEmpty == true;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasValue ? value! : 'Not set',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasValue
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
