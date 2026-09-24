import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

/// Settings page with app options and sign-out.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(Routes.login);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Settings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              children: [
                _SettingsOption(
                  icon: Icons.bluetooth,
                  title: 'Bluetooth Settings',
                  onTap: () => context.push(Routes.bluetoothSettings),
                ),
                _SettingsOption(
                  icon: Icons.location_on_outlined,
                  title: 'Location Settings',
                  onTap: () => context.push(Routes.locationSettings),
                ),
                _SettingsOption(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  onTap: () => context.push(Routes.appearanceSettings),
                ),
                _SettingsOption(
                  icon: Icons.notifications_outlined,
                  title: 'Notification Settings',
                  onTap: () => context.push(Routes.notificationSettings),
                ),
                _SettingsOption(
                  icon: Icons.visibility_outlined,
                  title: 'Privacy Settings',
                  onTap: () => context.push(Routes.privacySettings),
                ),
                _SettingsOption(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () => context.push(Routes.helpSupport),
                ),
                const SizedBox(height: 24),

                // Sign out button
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: const _SignOutButton(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton();

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

class _SettingsOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SettingsOption({
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
