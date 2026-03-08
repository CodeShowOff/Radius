import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Bottom sheet for selecting media source (camera/gallery/video).
///
/// Returns a list of [File] objects selected by the user, or null if cancelled.
class MediaPickerSheet extends StatelessWidget {
  final int maxItems;

  const MediaPickerSheet({
    super.key,
    this.maxItems = 10,
  });

  /// Shows the media picker bottom sheet and returns selected files.
  static Future<List<File>?> show(
    BuildContext context, {
    int maxItems = 10,
  }) {
    return showModalBottomSheet<List<File>>(
      context: context,
      builder: (_) => MediaPickerSheet(maxItems: maxItems),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Add Media',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              subtitle: Text('Select up to $maxItems photos'),
              onTap: () => _pickFromGallery(context),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () => _takePhoto(context),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Record a Video'),
              onTap: () => _recordVideo(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    try {
      final pickedFiles = await picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
        limit: maxItems,
      );
      if (pickedFiles.isNotEmpty && context.mounted) {
        final files = pickedFiles.map((xf) => File(xf.path)).toList();
        Navigator.of(context).pop(files);
      } else if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _takePhoto(BuildContext context) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (pickedFile != null && context.mounted) {
        Navigator.of(context).pop([File(pickedFile.path)]);
      } else if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _recordVideo(BuildContext context) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (pickedFile != null && context.mounted) {
        Navigator.of(context).pop([File(pickedFile.path)]);
      } else if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
