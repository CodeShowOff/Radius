import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/nearby_group_bloc.dart';

/// Page for creating a new nearby group.
class CreateNearbyGroupPage extends StatefulWidget {
  const CreateNearbyGroupPage({super.key});

  @override
  State<CreateNearbyGroupPage> createState() => _CreateNearbyGroupPageState();
}

class _CreateNearbyGroupPageState extends State<CreateNearbyGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _createGroup() {
    if (!_formKey.currentState!.validate()) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to create a group')),
      );
      return;
    }

    setState(() => _isCreating = true);

    context.read<NearbyGroupBloc>().add(CreateNearbyGroup(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          creatorId: authState.user.id,
          creatorUsername: authState.user.username,
          creatorDisplayName: authState.user.displayName,
          creatorPhotoUrl: authState.user.avatarUrl,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Nearby Group'),
      ),
      body: BlocListener<NearbyGroupBloc, NearbyGroupState>(
        listener: (context, state) {
          if (state.status == NearbyGroupBlocStatus.created &&
              state.myActiveGroup != null) {
            // Navigate to the new group's chat
            context.go(Routes.nearbyGroupChatWith(state.myActiveGroup!.id));
          } else if (state.status == NearbyGroupBlocStatus.error) {
            setState(() => _isCreating = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'Failed to create group'),
                backgroundColor: theme.colorScheme.error,
              ),
            );
          }
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Intro card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Create a Nearby Group',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your phone will scan for nearby users via Bluetooth. '
                        'Anyone discovered will automatically join your group.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Group name field
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Group Topic / Name',
                  hintText: 'e.g., Coffee Chat, Study Group, Networking',
                  prefixIcon: const Icon(Icons.topic),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: 'What\'s this group about?',
                ),
                maxLength: 50,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a group name';
                  }
                  if (value.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description field (optional)
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Add more context about your group...',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignLabelWithHint: true,
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 24),

              // Info cards
              _InfoCard(
                icon: Icons.bluetooth,
                title: 'Bluetooth-Based Presence',
                description:
                    'Members are automatically added when your device detects them nearby. '
                    'No GPS tracking required.',
              ),
              const SizedBox(height: 8),
              _InfoCard(
                icon: Icons.schedule,
                title: 'Temporary by Proximity',
                description:
                    'The group stays active while you\'re scanning. '
                    'Members leave when they move away.',
              ),
              const SizedBox(height: 8),
              _InfoCard(
                icon: Icons.chat,
                title: 'Open Chat',
                description:
                    'Anyone in range can read and send messages. '
                    'Perfect for spontaneous conversations!',
              ),
              const SizedBox(height: 32),

              // Create button
              FilledButton.icon(
                onPressed: _isCreating ? null : _createGroup,
                icon: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(_isCreating ? 'Creating...' : 'Create & Start Scanning'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 16),

              // Cancel button
              TextButton(
                onPressed: _isCreating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
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
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
