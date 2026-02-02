import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/cloudinary_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/profile_bloc.dart';
import '../../domain/entities/profile.dart';

/// Edit profile page with optimized UI.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  bool _isVisible = true;
  bool _hasChanges = false;
  String? _profileImageUrl;
  File? _selectedImage;
  bool _isUploadingImage = false;
  String? _selectedVibe;
  String? _selectedGender;
  final _cloudinaryService = CloudinaryService();
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _bioController = TextEditingController();

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
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initializeFromProfile(Profile profile) {
    if (_nameController.text.isEmpty && _bioController.text.isEmpty) {
      _nameController.text = profile.name;
      _bioController.text = profile.bio;
      _isVisible = profile.isVisible;
      _profileImageUrl = profile.photoUrl;
      _selectedVibe = profile.vibe;
      _selectedGender = profile.gender;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _selectedImage = File(pickedFile.path);
        _hasChanges = true;
      });

      // Upload to Cloudinary
      await _uploadImage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final url = await _cloudinaryService.uploadImage(
        _selectedImage!,
        folder: 'radius/profiles',
        tags: {'profile_picture': 'true'},
      );

      if (!mounted) return;
      setState(() {
        _profileImageUrl = url;
        _isUploadingImage = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully')),
      );
    } catch (e) {
      setState(() => _isUploadingImage = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: $e')),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profileImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _profileImageUrl = null;
                    _selectedImage = null;
                    _hasChanges = true;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) return;

    final updatedProfile = profileState.profile.copyWith(
      name: _nameController.text.trim(),
      bio: _bioController.text.trim(),
      isVisible: _isVisible,
      photoUrl: _profileImageUrl,
      vibe: _selectedVibe,
      gender: _selectedGender,
      updatedAt: DateTime.now(),
    );

    context.read<ProfileBloc>().add(ProfileUpdateRequested(updatedProfile));
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
            'You have unsaved changes. Are you sure you want to leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: BlocConsumer<ProfileBloc, ProfileState>(
        listenWhen: (previous, current) =>
            (current is ProfileSaved || current is ProfileError) &&
            previous != current,
        listener: (context, state) {
          if (state is ProfileSaved) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile saved successfully'),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green,
              ),
            );
            setState(() => _hasChanges = false);
            context.pop();
          } else if (state is ProfileError) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
        buildWhen: (previous, current) =>
            current is ProfileLoading ||
            current is ProfileLoaded ||
            current is ProfileSaving,
        builder: (context, state) {
          final isLoading = state is ProfileLoading;
          final isSaving = state is ProfileSaving;
          final profile = state is ProfileLoaded
              ? state.profile
              : state is ProfileSaving
                  ? state.profile
                  : null;

          if (profile != null) {
            _initializeFromProfile(profile);
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Edit Profile',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                // Save button - only rebuilds when saving state changes
                _SaveButton(
                  isEnabled: _hasChanges && !isSaving,
                  isSaving: isSaving,
                  onPressed: _saveProfile,
                ),
              ],
            ),
            body: isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final bottomPadding =
                          MediaQuery.of(context).padding.bottom;
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                            16, 16, 16, 16 + bottomPadding + 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Profile photo section
                              _ProfilePhotoSection(
                                photoUrl: _selectedImage != null
                                    ? null
                                    : (_profileImageUrl ?? profile?.photoUrl),
                                imageFile: _selectedImage,
                                isUploading: _isUploadingImage,
                                onPhotoTap: _showImageSourceDialog,
                              ),
                              const SizedBox(height: 32),

                              // Name field
                              _ProfileTextField(
                                controller: _nameController,
                                label: 'Display Name',
                                hint: 'Enter your name',
                                icon: Icons.person_outline,
                                maxLength: 50,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Name is required';
                                  }
                                  if (value.trim().length < 2) {
                                    return 'Name must be at least 2 characters';
                                  }
                                  return null;
                                },
                                onChanged: (_) => _onFieldChanged(),
                              ),
                              const SizedBox(height: 16),

                              // Bio field
                              _ProfileTextField(
                                controller: _bioController,
                                label: 'Bio',
                                hint: 'Tell others about yourself',
                                icon: Icons.info_outline,
                                maxLength: 200,
                                maxLines: 4,
                                onChanged: (_) => _onFieldChanged(),
                              ),
                              const SizedBox(height: 24),

                              // Vibe selector
                              _VibeSelector(
                                selectedVibe: _selectedVibe,
                                onChanged: (vibe) {
                                  setState(() {
                                    _selectedVibe = vibe;
                                    _hasChanges = true;
                                  });
                                },
                              ),
                              const SizedBox(height: 24),

                              // Gender selector
                              _GenderSelector(
                                selectedGender: _selectedGender,
                                isLocked: profile?.gender != null,
                                onChanged: (gender) {
                                  setState(() {
                                    _selectedGender = gender;
                                    _hasChanges = true;
                                  });
                                },
                              ),
                              const SizedBox(height: 24),

                              // Visibility toggle
                              _VisibilityToggle(
                                isVisible: _isVisible,
                                onChanged: (value) {
                                  setState(() {
                                    _isVisible = value;
                                    _hasChanges = true;
                                  });
                                },
                              ),
                              const SizedBox(height: 32),

                              // Info card
                              _InfoCard(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

/// Optimized save button widget - prevents unnecessary rebuilds.
class _SaveButton extends StatelessWidget {
  final bool isEnabled;
  final bool isSaving;
  final VoidCallback onPressed;

  const _SaveButton({
    required this.isEnabled,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: isSaving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: isEnabled ? onPressed : null,
              child: Text(
                'Save',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
    );
  }
}

/// Profile photo section widget.
class _ProfilePhotoSection extends StatelessWidget {
  final String? photoUrl;
  final File? imageFile;
  final bool isUploading;
  final VoidCallback onPhotoTap;

  const _ProfilePhotoSection({
    this.photoUrl,
    this.imageFile,
    this.isUploading = false,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? backgroundImage;
    if (imageFile != null) {
      backgroundImage = FileImage(imageFile!) as ImageProvider;
    } else if (photoUrl != null) {
      backgroundImage = NetworkImage(photoUrl!) as ImageProvider;
    }

    return Center(
      child: Stack(
        children: [
          GestureDetector(
            onTap: isUploading ? null : onPhotoTap,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: backgroundImage,
              child: photoUrl == null && imageFile == null
                  ? Icon(
                      Icons.person,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
          ),
          if (isUploading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
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
          if (!isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: onPhotoTap,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reusable text field widget for profile fields.
class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLength = 100,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
      ),
    );
  }
}

/// Visibility toggle widget.
class _VisibilityToggle extends StatelessWidget {
  final bool isVisible;
  final ValueChanged<bool> onChanged;

  const _VisibilityToggle({
    required this.isVisible,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isVisible
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isVisible ? Icons.visibility : Icons.visibility_off,
                color: isVisible
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Visibility',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isVisible
                        ? 'Others can discover you nearby'
                        : 'You are hidden from discovery',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: isVisible,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Info card with helpful tips.
class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tip',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A complete profile helps others connect with you. Add a photo and bio to make a great first impression!',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
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

/// Vibe selector widget with predefined vibe options.
class _VibeSelector extends StatelessWidget {
  final String? selectedVibe;
  final ValueChanged<String?> onChanged;

  const _VibeSelector({
    required this.selectedVibe,
    required this.onChanged,
  });

  static const vibes = {
    '👋 Open to talk': '👋 Open to talk',
    '🎧 Busy': '🎧 Busy',
    '🤝 Networking': '🤝 Networking',
    '💬 Looking for conversation': '💬 Looking for conversation',
    '☕ Coffee break': '☕ Coffee break',
    '🎮 Gaming': '🎮 Gaming',
    '📚 Studying': '📚 Studying',
    '🎨 Being creative': '🎨 Being creative',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.mood,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Vibe',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Let others know your current status',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Clear selection chip
                FilterChip(
                  label: const Text('None'),
                  selected: selectedVibe == null,
                  onSelected: (selected) {
                    if (selected) onChanged(null);
                  },
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                ),
                // Vibe chips
                ...vibes.entries.map((entry) {
                  return FilterChip(
                    label: Text(entry.key),
                    selected: selectedVibe == entry.value,
                    onSelected: (selected) {
                      onChanged(selected ? entry.value : null);
                    },
                    selectedColor: Theme.of(context)
                        .colorScheme
                        .tertiaryContainer,
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Gender selector widget - one-time selection only.
class _GenderSelector extends StatelessWidget {
  final String? selectedGender;
  final bool isLocked;
  final ValueChanged<String?> onChanged;

  const _GenderSelector({
    required this.selectedGender,
    required this.isLocked,
    required this.onChanged,
  });

  static const genders = {
    '👨 Male': 'Male',
    '👩 Female': 'Female',
    '⚧️ Non-binary': 'Non-binary',
    '🤷 Prefer not to say': 'Prefer not to say',
  };

  Future<void> _showWarningAndSelect(
      BuildContext context, String gender) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Important: Cannot Change Later'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Once you set your gender, you CANNOT change it later.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This is a permanent decision to ensure authenticity in our community.',
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to set your gender to: $gender?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      onChanged(gender);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isLocked
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock : Icons.person_outline,
                    color: isLocked
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Gender',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isLocked) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'LOCKED',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLocked
                            ? 'Gender cannot be changed once set'
                            : '⚠️ Warning: Cannot be changed later',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isLocked
                              ? theme.colorScheme.outline
                              : theme.colorScheme.error,
                          fontWeight:
                              isLocked ? FontWeight.normal : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: genders.entries.map((entry) {
                final isSelected = selectedGender == entry.value;
                return FilterChip(
                  label: Text(entry.key),
                  selected: isSelected,
                  onSelected: isLocked
                      ? null
                      : (selected) {
                          if (selected) {
                            _showWarningAndSelect(context, entry.value);
                          }
                        },
                  selectedColor: theme.colorScheme.primaryContainer,
                  disabledColor: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
