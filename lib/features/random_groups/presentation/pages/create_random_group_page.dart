import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/random_group_bloc.dart';

/// Page for creating a new random group.
class CreateRandomGroupPage extends StatefulWidget {
  const CreateRandomGroupPage({super.key});

  @override
  State<CreateRandomGroupPage> createState() => _CreateRandomGroupPageState();
}

class _CreateRandomGroupPageState extends State<CreateRandomGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedTopic;

  static const _topics = [
    'Technology',
    'Gaming',
    'Music',
    'Sports',
    'Movies',
    'Books',
    'Art',
    'Food',
    'Travel',
    'Fitness',
    'Science',
    'Other',
  ];

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

    final user = authState.user;

    context.read<RandomGroupBloc>().add(CreateRandomGroup(
          name: _nameController.text.trim(),
          topic: _selectedTopic,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          creatorId: user.id,
          creatorUsername: user.username,
          creatorDisplayName: user.displayName,
          creatorPhotoUrl: user.avatarUrl,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<RandomGroupBloc, RandomGroupState>(
      listener: (context, state) {
        if (state.status == RandomGroupBlocStatus.created) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group created successfully!')),
          );
          context.pop();
        } else if (state.status == RandomGroupBlocStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Failed to create group'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Create Group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: BlocBuilder<RandomGroupBloc, RandomGroupState>(
          builder: (context, state) {
            final isCreating = state.status == RandomGroupBlocStatus.creating;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Icon(
                      Icons.groups,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create a Random Group',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Anyone can discover and request to join your group. You\'ll approve members before they can participate.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Name field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Group Name *',
                        hintText: 'Enter a name for your group',
                        prefixIcon: Icon(Icons.label),
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 50,
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a group name';
                        }
                        if (value.trim().length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        return null;
                      },
                      enabled: !isCreating,
                    ),
                    const SizedBox(height: 16),

                    // Topic dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTopic,
                      decoration: const InputDecoration(
                        labelText: 'Topic (Optional)',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                      ),
                      items: _topics.map((topic) {
                        return DropdownMenuItem(
                          value: topic,
                          child: Text(topic),
                        );
                      }).toList(),
                      onChanged: isCreating
                          ? null
                          : (value) {
                              setState(() => _selectedTopic = value);
                            },
                    ),
                    const SizedBox(height: 16),

                    // Description field
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'What is this group about?',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      enabled: !isCreating,
                    ),
                    const SizedBox(height: 24),

                    // Info card
                    Card(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'As the creator, you\'ll be the primary admin. You can approve join requests and manage members.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Create button
                    FilledButton.icon(
                      onPressed: isCreating ? null : _createGroup,
                      icon: isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(isCreating ? 'Creating...' : 'Create Group'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
