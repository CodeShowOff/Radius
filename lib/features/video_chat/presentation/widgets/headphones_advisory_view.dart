import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Headphones advisory shown each time the user enters Video Chat
/// (unless they check "Don't show again").
class HeadphonesAdvisoryView extends StatefulWidget {
  final void Function(bool permanently) onDismissed;

  const HeadphonesAdvisoryView({
    super.key,
    required this.onDismissed,
  });

  @override
  State<HeadphonesAdvisoryView> createState() =>
      _HeadphonesAdvisoryViewState();
}

class _HeadphonesAdvisoryViewState extends State<HeadphonesAdvisoryView> {
  bool _dontShowAgain = false;

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

            // Headphones icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentColor.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.headphones_rounded,
                size: 44,
                color: AppTheme.accentColor,
              ),
            ),

            const SizedBox(height: 32),

            // Title
            Text(
              'Headphones Recommended',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            // Description
            Text(
              'Strangers may use offensive\nor inappropriate language.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.5,
              ),
            ),

            const Spacer(flex: 2),

            // Got it button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => widget.onDismissed(_dontShowAgain),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Don't show again checkbox
            GestureDetector(
              onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _dontShowAgain,
                      onChanged: (val) =>
                          setState(() => _dontShowAgain = val ?? false),
                      activeColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Don't show this again",
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}
