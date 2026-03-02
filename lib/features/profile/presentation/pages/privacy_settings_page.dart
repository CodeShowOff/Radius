import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/firebase/profile_service.dart';
import '../../../auth/domain/repositories/i_auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../bloc/profile_bloc.dart';

/// Privacy settings page for managing discovery and profile visibility.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _isDiscoverable = true;
  bool _showOnlineStatus = true;
  bool _allowConnectionRequests = true;
  bool _showLastSeen = true;
  List<String> _blockedUserIds = [];
  Map<String, String> _blockedUserNames = {};
  bool _isLoadingBlocked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentSettings();
      _loadBlockedUsers();
    });
  }

  void _loadCurrentSettings() {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      setState(() {
        _isDiscoverable = profileState.profile.isVisible;
        _showOnlineStatus = profileState.profile.showOnlineStatus;
        _allowConnectionRequests = profileState.profile.allowConnectionRequests;
        _showLastSeen = profileState.profile.showLastSeen;
      });
    }
  }

  Future<void> _loadBlockedUsers() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      try {
        final connectionService = getIt<ConnectionService>();
        final profileService = getIt<ProfileService>();
        final blockedIds =
            await connectionService.getBlockedUserIds(authState.user.id);
        
        // Fetch display names for blocked users
        final names = <String, String>{};
        for (final userId in blockedIds) {
          try {
            final profile = await profileService.getProfile(userId);
            names[userId] = profile?.name ?? 'Unknown User';
          } catch (_) {
            names[userId] = 'Unknown User';
          }
        }
        
        if (mounted) {
          setState(() {
            _blockedUserIds = blockedIds;
            _blockedUserNames = names;
            _isLoadingBlocked = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoadingBlocked = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return BlocListener<ProfileBloc, ProfileState>(
      listenWhen: (previous, current) =>
          current is ProfileError && previous != current,
      listener: (context, state) {
        if (state is ProfileLoaded) {
          // Settings saved successfully
        } else if (state is ProfileError) {
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
            'Privacy Settings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
          children: [
            // Discovery Section
            const Text(
              'Discovery',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.visibility),
                    title: const Text('Make me discoverable'),
                    subtitle: const Text(
                      'Allow nearby users to see you while the app is open',
                    ),
                    value: _isDiscoverable,
                    onChanged: (value) {
                      setState(() => _isDiscoverable = value);
                      unawaited(_saveVisibilitySetting(value));
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.person_add),
                    title: const Text('Allow connection requests'),
                    subtitle: const Text(
                      'Let others send you connection requests',
                    ),
                    value: _allowConnectionRequests,
                    onChanged: (value) {
                      setState(() => _allowConnectionRequests = value);
                      _savePrivacySettings();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Online Status Section
            const Text(
              'Online Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.circle),
                    title: const Text('Show online status'),
                    subtitle: const Text(
                      'Let connections see when you\'re online',
                    ),
                    value: _showOnlineStatus,
                    onChanged: (value) {
                      setState(() => _showOnlineStatus = value);
                      _savePrivacySettings();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.access_time),
                    title: const Text('Show last seen'),
                    subtitle: const Text(
                      'Let connections see when you were last active',
                    ),
                    value: _showLastSeen,
                    onChanged: (value) {
                      setState(() => _showLastSeen = value);
                      _savePrivacySettings();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Blocked Users Section
            const Text(
              'Blocked Users',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Manage blocked users'),
                subtitle: _isLoadingBlocked
                    ? const Text('Loading...')
                    : Text(
                        '${_blockedUserIds.length} user${_blockedUserIds.length == 1 ? '' : 's'} blocked'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showBlockedUsersSheet(),
              ),
            ),
            const SizedBox(height: 24),

            // Data & Privacy Section
            const Text(
              'Data & Privacy',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Download my data'),
                    subtitle: const Text('Request a copy of your data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _requestDataDownload,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_forever,
                        color: Theme.of(context).colorScheme.error),
                    title: Text(
                      'Delete my account',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                    subtitle: const Text('Permanently delete your account'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showDeleteAccountDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Privacy Information
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
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Your Privacy',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'By default, nearby discovery runs while the app is open. '
                      'You can optionally enable Background Advertising in Bluetooth Settings to stay discoverable after closing the app. '
                      'Your broadcast username is visible to nearby Radius users for discovery. '
                      'You can disconnect from any user to disable chatting while preserving chat history. '
                      'All chat messages are encrypted in transit and stored securely.',
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

  Future<void> _saveVisibilitySetting(bool isVisible) async {
    context.read<ProfileBloc>().add(ProfileVisibilityToggled(isVisible));
    // Visibility is now just a profile setting.
    // The simplified BLE system broadcasts usernames directly without a
    // Firestore-based discoverability flag.
  }

  void _savePrivacySettings() {
    context.read<ProfileBloc>().add(ProfilePrivacySettingsUpdated(
          showOnlineStatus: _showOnlineStatus,
          allowConnectionRequests: _allowConnectionRequests,
          showLastSeen: _showLastSeen,
        ));
  }

  void _showBlockedUsersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Blocked Users',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _blockedUserIds.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.block,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No blocked users',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Users you block will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _blockedUserIds.length,
                      itemBuilder: (context, index) {
                        final blockedId = _blockedUserIds[index];
                        final displayName = _blockedUserNames[blockedId] ?? 'Unknown User';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Icon(Icons.person,
                                color: Theme.of(context).colorScheme.outline),
                          ),
                          title: Text(displayName),
                          trailing: TextButton(
                            onPressed: () =>
                                _unblockUser(blockedId, sheetContext),
                            child: const Text('Unblock'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unblockUser(String blockedId, BuildContext sheetContext) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      // Capture messenger before async gap to avoid use_build_context_synchronously
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(sheetContext);

      try {
        // Unblock via ConnectionBloc - this updates both Firestore and bloc state
        context.read<ConnectionBloc>().add(
              ConnectionUnblockUser(blockedId),
            );

        // Wait for the operation to complete
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          setState(() {
            _blockedUserIds.remove(blockedId);
          });
          navigator.pop();
          messenger.showSnackBar(
            const SnackBar(content: Text('User unblocked')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to unblock user: $e')),
          );
        }
      }
    }
  }

  void _requestDataDownload() {
    final authState = context.read<AuthBloc>().state;
    final email =
        authState is AuthAuthenticated ? authState.user.email : 'your email';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Download Your Data'),
        content: Text(
          'We\'ll prepare a copy of your data and send a download link to $email within 48 hours.\n\n'
          'This will include:\n'
          '• Your profile information\n'
          '• Your connections list\n'
          '• Your chat history\n'
          '• Your privacy settings',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Send data download request email
              await _sendDataDownloadRequest(email);
            },
            child: const Text('Request Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendDataDownloadRequest(String email) async {
    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: 'support@radiusapp.tech',
        queryParameters: {
          'subject': 'Data Download Request - Radius App',
          'body': 'I would like to request a copy of my data.\n\n'
              'Email: $email\n'
              'Request Date: ${DateTime.now()}\n\n'
              'Please send my data export to this email address within 48 hours.',
        },
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Opening email client. Please send the request to receive your data.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please email support@radiusapp.tech to request your data download.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening email client: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete:\n\n'
          '• Your profile and all personal data\n'
          '• All your connections\n'
          '• All your chat messages\n'
          '• Your account credentials\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmDeleteAccount();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isConfirmEnabled = textController.text == 'DELETE';

          return AlertDialog(
            title: const Text('Final Confirmation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Type DELETE in capitals to confirm permanent account deletion.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: textController,
                  decoration: InputDecoration(
                    labelText: 'Type DELETE',
                    border: const OutlineInputBorder(),
                    errorText:
                        textController.text.isNotEmpty && !isConfirmEnabled
                            ? 'Please type DELETE exactly'
                            : null,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isConfirmEnabled
                      ? Theme.of(dialogContext).colorScheme.error
                      : Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                ),
                onPressed: isConfirmEnabled
                    ? () async {
                        Navigator.pop(dialogContext);
                        await _performAccountDeletion();
                      }
                    : null,
                child: const Text('Delete My Account'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _performAccountDeletion() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Deleting your account...'),
          ],
        ),
      ),
    );

    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) {
        throw Exception('Not authenticated');
      }

      // Delete account through auth repository
      final result = await getIt<IAuthRepository>().deleteAccount();

      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      result.fold(
        (failure) {
          // Show error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete account: ${failure.message}'),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 4),
            ),
          );
        },
        (_) {
          // Account deleted successfully - sign out will be handled by auth bloc
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account has been permanently deleted.'),
              duration: Duration(seconds: 3),
            ),
          );

          // Sign out to trigger navigation to login
          context.read<AuthBloc>().add(const AuthSignOutRequested());
        },
      );
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting account: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
