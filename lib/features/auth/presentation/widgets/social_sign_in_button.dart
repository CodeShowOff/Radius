import 'package:flutter/material.dart';

/// A button for social sign-in providers (Google, Apple, etc.)
class SocialSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String icon;
  final String label;
  final bool isLoading;

  const SocialSignInButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      child: isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIcon(context),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    // For Google icon, use a styled text 'G'
    if (icon == 'G') {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Center(
          child: Text(
            'G',
            style: TextStyle(
              color: Color(0xFF4285F4),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }
    
    // Default icon
    return Icon(
      Icons.login,
      size: 24,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}

/// Google sign-in button with proper branding
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SocialSignInButton(
      onPressed: onPressed,
      icon: 'G',
      label: 'Continue with Google',
      isLoading: isLoading,
    );
  }
}
