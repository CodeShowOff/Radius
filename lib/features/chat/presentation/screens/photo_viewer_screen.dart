import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Full-screen photo viewer with pinch-to-zoom and save-to-gallery.
class PhotoViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;
  final String? caption;

  const PhotoViewerScreen({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.caption,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  bool _isSaving = false;
  bool _showOverlay = true;

  Future<void> _saveToGallery() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // Download the image bytes
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image');
      }

      final Uint8List bytes = response.bodyBytes;

      // Save to a temporary file first, then use Gal to save to gallery
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'radius_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Gal.putImage(file.path);

      // Clean up temp file
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = CachedNetworkImageProvider(widget.imageUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          children: [
            // Photo viewer with zoom
            widget.heroTag != null
                ? PhotoView(
                    imageProvider: imageProvider,
                    heroAttributes:
                        PhotoViewHeroAttributes(tag: widget.heroTag!),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                    loadingBuilder: (context, event) => Center(
                      child: CircularProgressIndicator(
                        value: event == null
                            ? null
                            : event.cumulativeBytesLoaded /
                                (event.expectedTotalBytes ?? 1),
                        color: Colors.white,
                      ),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  )
                : PhotoView(
                    imageProvider: imageProvider,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                    loadingBuilder: (context, event) => Center(
                      child: CircularProgressIndicator(
                        value: event == null
                            ? null
                            : event.cumulativeBytesLoaded /
                                (event.expectedTotalBytes ?? 1),
                        color: Colors.white,
                      ),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  ),

            // Top bar with back button
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                          ),
                          const Spacer(),
                          // Save button
                          IconButton(
                            onPressed: _isSaving ? null : _saveToGallery,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.download,
                                    color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Caption at bottom
            if (widget.caption != null && widget.caption!.isNotEmpty)
              AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        child: Text(
                          widget.caption!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
