import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/video_chat_profile.dart';

/// Prompt view for returning users — asks if they want to modify
/// their existing anonymous profile or continue with it as-is.
class ProfilePromptView extends StatelessWidget {
  final VideoChatProfile profile;
  final VoidCallback onModify;
  final VoidCallback onContinue;

  const ProfilePromptView({
    super.key,
    required this.profile,
    required this.onModify,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Title
            Text(
              'Welcome Back!',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Your video chat identity',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),

            const SizedBox(height: 32),

            // Current profile card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isDark
                    ? const Color(0xFF1E1E28)
                    : const Color(0xFFF0F0F6),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A2A36)
                      : const Color(0xFFE2E2EC),
                ),
              ),
              child: Column(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 48,
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                    backgroundImage: profile.photoUrl != null &&
                            profile.photoUrl!.isNotEmpty
                        ? CachedNetworkImageProvider(profile.photoUrl!)
                        : null,
                    child:
                        profile.photoUrl == null || profile.photoUrl!.isEmpty
                            ? Text(
                                profile.displayName.isNotEmpty
                                    ? profile.displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              )
                            : null,
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    profile.displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Would you like to change your identity\nbefore entering video chat?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),

            const Spacer(flex: 2),

            // Continue with current profile
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Modify profile
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onModify,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Change Identity',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}
