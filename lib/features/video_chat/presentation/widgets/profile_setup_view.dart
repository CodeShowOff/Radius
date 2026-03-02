import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/video_chat_profile.dart';

/// Profile setup view for new users or users modifying their profile.
///
/// Users must enter a display name. Photo is optional.
/// No auto-generated names — the user types their own.
class ProfileSetupView extends StatefulWidget {
  final VideoChatProfile? existingProfile;
  final bool isFirstTime;
  final void Function(String displayName, String? photoFilePath) onSave;
  final VoidCallback onRemovePhoto;

  const ProfileSetupView({
    super.key,
    this.existingProfile,
    required this.isFirstTime,
    required this.onSave,
    required this.onRemovePhoto,
  });

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedPhotoPath;
  bool _hasExistingPhoto = false;
  bool _photoRemoved = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingProfile != null) {
      _nameController.text = widget.existingProfile!.displayName;
      _hasExistingPhoto =
          widget.existingProfile!.photoUrl != null &&
          widget.existingProfile!.photoUrl!.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_hasExistingPhoto && !_photoRemoved)
              ListTile(
                leading: Icon(Icons.delete, color: AppTheme.errorColor),
                title: Text('Remove Photo',
                    style: TextStyle(color: AppTheme.errorColor)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _photoRemoved = true;
                    _selectedPhotoPath = null;
                  });
                  widget.onRemovePhoto();
                },
              ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (image != null && mounted) {
      setState(() {
        _selectedPhotoPath = image.path;
        _photoRemoved = false;
      });
    }
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(
      _nameController.text.trim(),
      _selectedPhotoPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Title
              Text(
                widget.isFirstTime
                    ? 'Set Up Your Video Chat Profile'
                    : 'Update Your Video Chat Profile',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                'This is your anonymous identity for video chat.\n'
                'It is completely separate from your Radius profile.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),

              const SizedBox(height: 36),

              // Avatar / Photo picker
              GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                      backgroundImage: _getAvatarImage(),
                      child: _shouldShowPlaceholder()
                          ? Icon(
                              Icons.person,
                              size: 48,
                              color: AppTheme.primaryColor.withValues(alpha: 0.6),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF16161D)
                                : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Tap to add photo (optional)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),

              const SizedBox(height: 32),

              // Display Name field
              TextFormField(
                controller: _nameController,
                maxLength: 30,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'Enter your video chat name',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a display name';
                  }
                  if (value.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 40),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.isFirstTime ? 'Continue' : 'Save & Continue',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  ImageProvider? _getAvatarImage() {
    if (_selectedPhotoPath != null) {
      return FileImage(File(_selectedPhotoPath!));
    }
    if (_hasExistingPhoto &&
        !_photoRemoved &&
        widget.existingProfile?.photoUrl != null) {
      return NetworkImage(widget.existingProfile!.photoUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder() {
    if (_selectedPhotoPath != null) return false;
    if (_hasExistingPhoto &&
        !_photoRemoved &&
        widget.existingProfile?.photoUrl != null) {
      return false;
    }
    return true;
  }
}
