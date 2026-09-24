import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Bottom sheet/picker for selecting media source (camera/gallery/video).
/// Uses premium wechat_assets_picker for a modern, Instagram-like experience.
class MediaPickerSheet {
  /// Opens the modern gallery picker and returns selected files.
  static Future<List<File>?> show(
    BuildContext context, {
    int maxItems = 10,
    bool videoOnly = false,
  }) async {
    final theme = Theme.of(context);
    
    List<AssetEntity>? assets;
    try {
      // Pick assets using the modern picker
      assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: maxItems,
          requestType: videoOnly ? RequestType.video : RequestType.common,
          textDelegate: const EnglishAssetPickerTextDelegate(),
          themeColor: theme.colorScheme.primary,
          gridCount: 3, // Premium modern grid look
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open gallery: $e')),
        );
      }
      return null;
    }

    if (assets != null && assets.isNotEmpty) {
      // Show loading overlay while extracting files
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final List<File> files = [];
      try {
        for (final asset in assets) {
          final file = await asset.file;
          if (file != null) {
            files.add(file);
          }
        }
      } finally {
        if (context.mounted) {
          Navigator.of(context).pop(); // dismiss loading
        }
      }
      return files;
    }
    return null;
  }
}
