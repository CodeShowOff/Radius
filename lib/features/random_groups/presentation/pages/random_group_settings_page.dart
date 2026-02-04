import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/cloudinary_service.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/random_group_bloc.dart';

/// Page for editing random group settings (admin only).
///
/// Allows admins to:
/// - Update group photo
/// - Update group name
/// - Update group topic
/// - Update group description
class RandomGroupSettingsPage extends StatefulWidget {
  final String groupId;

  const RandomGroupSettingsPage({
    super.key,
    required this.groupId,
  });

  @override
  State<RandomGroupSettingsPage> createState() =>
      _RandomGroupSettingsPageState();
}

class _RandomGroupSettingsPageState extends State<RandomGroupSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _selectedTopic;
  String? _newPhotoUrl;
  bool _isUploading = false;
  bool _hasChanges = false;

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
  void initState() {
    super.initState();
    _loadGroupDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _loadGroupDetails() {
    final state = context.read<RandomGroupBloc>().state;
    final group = state.selectedGroup;

    if (group != null) {
      _nameController.text = group.name;
      _descriptionController.text = group.description ?? '';
      _selectedTopic = group.topic;
      _newPhotoUrl = group.photoUrl;
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      // Upload to Cloudinary
      final cloudinary = CloudinaryService();
      final photoUrl = await cloudinary.uploadImage(
        File(image.path),
        folder: 'group_photos',
      );

      if (mounted) {
        setState(() {
          _newPhotoUrl = photoUrl;
          _hasChanges = true;
          _isUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _saveChanges() {
    if (!_formKey.currentState!.validate()) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final state = context.read<RandomGroupBloc>().state;
    final group = state.selectedGroup;
    if (group == null) return;

    // Only send changed fields
    final String? name = _nameController.text.trim() != group.name
        ? _nameController.text.trim()
        : null;
    final String? description = _descriptionController.text.trim() != (group.description ?? '')
        ? _descriptionController.text.trim()
        : null;
    final String? topic = _selectedTopic != group.topic ? _selectedTopic : null;
    final String? photoUrl = _newPhotoUrl != group.photoUrl ? _newPhotoUrl : null;

    context.read<RandomGroupBloc>().add(UpdateRandomGroup(
          groupId: widget.groupId,
          adminId: authState.user.id,
          name: name,
          topic: topic,
          description: description,
          photoUrl: photoUrl,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<RandomGroupBloc, RandomGroupState>(
      listener: (context, state) {
        if (state.status == RandomGroupBlocStatus.loaded && _hasChanges) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group updated successfully!')),
          );
          setState(() => _hasChanges = false);
          context.pop();
        } else if (state.status == RandomGroupBlocStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Failed to update group'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final group = state.selectedGroup;

        if (group == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group Settings')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final isLoading = state.status == RandomGroupBlocStatus.loading;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Group Settings'),
            actions: [
              if (_hasChanges)
                IconButton(
                  onPressed: isLoading ? null : _saveChanges,
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  tooltip: 'Save Changes',
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              onChanged: () {
                if (!_hasChanges) {
                  setState(() => _hasChanges = true);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Group photo section
                  Center(
                    child: Stack(
                      children: [
                        CachedAvatar(
                          imageUrl: _newPhotoUrl,
                          name: _nameController.text.isNotEmpty
                              ? _nameController.text
                              : group.name,
                          radius: 60,
                        ),
                        if (_isUploading)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary,
                            radius: 20,
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt, size: 20),
                              color: theme.colorScheme.onPrimary,
                              onPressed: _isUploading ? null : _pickImage,
                              tooltip: 'Change Photo',
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Group name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'Enter group name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a group name';
                      }
                      if (value.trim().length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      if (value.trim().length > 50) {
                        return 'Name must be less than 50 characters';
                      }
                      return null;
                    },
                    maxLength: 50,
                  ),
                  const SizedBox(height: 16),

                  // Topic
                  DropdownButtonFormField<String>(
                    value: _selectedTopic,
                    decoration: const InputDecoration(
                      labelText: 'Topic',
                      border: OutlineInputBorder(),
                    ),
                    items: _topics.map((topic) {
                      return DropdownMenuItem(
                        value: topic,
                        child: Text(topic),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTopic = value;
                        _hasChanges = true;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Enter group description or rules',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 24),

                  // Save button
                  FilledButton.icon(
                    onPressed: isLoading || !_hasChanges ? null : _saveChanges,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
