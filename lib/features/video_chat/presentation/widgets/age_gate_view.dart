import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Full-screen age verification gate.
///
/// Blocks access to the Video Chat feature unless the user
/// confirms they are 18 or older. Shown only once per device.
class AgeGateView extends StatelessWidget {
  final VoidCallback onConfirmed;
  final VoidCallback onBack;

  const AgeGateView({
    super.key,
    required this.onConfirmed,
    required this.onBack,
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

            // Warning icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.warningColor.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 44,
                color: AppTheme.warningColor,
              ),
            ),

            const SizedBox(height: 32),

            // Title
            Text(
              'Age Restriction',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            // Description
            Text(
              'You must be 18 or older to use Random Video Chat.\n\n'
              'By continuing, you confirm that you are at least 18 years of age.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.5,
              ),
            ),

            const Spacer(flex: 2),

            // Confirm button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onConfirmed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'I am 18 or older',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Go back button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: onBack,
                child: Text(
                  'Go Back',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
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
