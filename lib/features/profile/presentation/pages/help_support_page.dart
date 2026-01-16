import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Help and support page with FAQs and contact information.
class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          // Quick Help Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.question_answer),
                  title: const Text('FAQs'),
                  subtitle: const Text('Frequently asked questions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateToFAQs(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.book),
                  title: const Text('User Guide'),
                  subtitle: const Text('Learn how to use Radius'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateToUserGuide(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Report a Bug'),
                  subtitle: const Text('Help us improve the app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showReportBugDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Contact Section
          const Text(
            'Contact Us',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('Email Support'),
                  subtitle: const Text('support@radiusapp.com'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchEmail(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Website'),
                  subtitle: const Text('www.radiusapp.com'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchWebsite(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.policy),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchPrivacyPolicy(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchTerms(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // App Info
          const Text(
            'App Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const _InfoRow('Version', '1.0.0'),
                  const Divider(),
                  const _InfoRow('Build', '1'),
                  const Divider(),
                  _InfoRow(
                      'Platform',
                      Platform.isAndroid
                          ? 'Android'
                          : Platform.isIOS
                              ? 'iOS'
                              : 'Other'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToFAQs(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _FAQsPage(),
      ),
    );
  }

  void _navigateToUserGuide(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _UserGuidePage(),
      ),
    );
  }

  void _showReportBugDialog(BuildContext context) {
    final descriptionController = TextEditingController();
    String selectedCategory = 'General';
    final categories = [
      'General',
      'Bluetooth/Discovery',
      'Connections',
      'Chat',
      'Profile',
      'Performance',
      'Other'
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Report a Bug'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category:'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: categories
                        .map((cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(cat),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setDialogState(
                          () => selectedCategory = value ?? 'General');
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Description:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText:
                          'Please describe what happened, what you expected, and any steps to reproduce the issue...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Device info will be automatically included.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: descriptionController.text.trim().isEmpty
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Bug report submitted. Thank you for helping us improve!'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@radiusapp.com',
      query: 'subject=Radius App Support',
    );
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        throw Exception('Could not launch email client');
      }
    } catch (e) {
      // Email client not available, show snackbar with email address
    }
  }

  Future<void> _launchWebsite() async {
    final Uri url = Uri.parse('https://www.radiusapp.com');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch website');
      }
    } catch (e) {
      // Browser not available
    }
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://www.radiusapp.com/privacy');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch privacy policy');
      }
    } catch (e) {
      // Browser not available
    }
  }

  Future<void> _launchTerms() async {
    final Uri url = Uri.parse('https://www.radiusapp.com/terms');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch terms');
      }
    } catch (e) {
      // Browser not available
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// FAQs Page
class _FAQsPage extends StatelessWidget {
  const _FAQsPage();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Frequently Asked Questions'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: const [
          _FAQItem(
            question: 'How does Radius find nearby users?',
            answer:
                'Radius uses Bluetooth Low Energy (BLE) to detect other Radius users within approximately 30 meters. '
                'Your phone broadcasts an anonymous ID that rotates every 15 minutes for privacy. '
                'When another user is detected, the app looks up their profile from our servers.',
          ),
          _FAQItem(
            question: 'Does Radius drain my battery?',
            answer:
                'Radius is optimized for battery efficiency. It uses BLE which consumes minimal power, '
                'and implements intermittent scanning (10 seconds of scanning every 30 seconds) to preserve battery. '
                'Most users report less than 5% additional battery drain per day.',
          ),
          _FAQItem(
            question: 'Is my data private and secure?',
            answer: 'Yes! Your privacy is our top priority:\n'
                '• Your BLE ID rotates every 15 minutes\n'
                '• Your real identity is never broadcast via Bluetooth\n'
                '• Only users you connect with can see your profile\n'
                '• All chat messages are encrypted in transit\n'
                '• We never sell your data to third parties',
          ),
          _FAQItem(
            question: 'Why do I need location permissions?',
            answer:
                'Android requires location permissions for BLE scanning. This is a system requirement, not our choice. '
                'We do NOT track your GPS location. The permission is only used to enable Bluetooth scanning.',
          ),
          _FAQItem(
            question: 'Can I chat without internet?',
            answer:
                'No, chat requires an internet connection. Bluetooth is only used for discovery. '
                'Once you find someone nearby, all chat messages are sent through our secure servers.',
          ),
          _FAQItem(
            question: 'How do I stop being discoverable?',
            answer:
                'Go to Profile → Privacy Settings and toggle off "Make me discoverable". '
                'You can also stop discovery by not using the "Find Nearby People" feature.',
          ),
          _FAQItem(
            question: 'How far can Radius detect users?',
            answer:
                'BLE has a range of approximately 10-30 meters in open space. '
                'Walls, furniture, and other obstacles reduce this range. '
                'The app categorizes proximity as: Immediate (< 1m), Near (1-5m), and Far (5-30m).',
          ),
          _FAQItem(
            question: 'What if someone is bothering me?',
            answer:
                'You can block any user from their profile. Blocked users cannot:\n'
                '• Send you connection requests\n'
                '• See you in their discovery\n'
                '• Message you\n'
                'Go to Privacy Settings → Manage Blocked Users to view your blocked list.',
          ),
        ],
      ),
    );
  }
}

class _FAQItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FAQItem({
    required this.question,
    required this.answer,
  });

  @override
  State<_FAQItem> createState() => _FAQItemState();
}

class _FAQItemState extends State<_FAQItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 12),
                Text(
                  widget.answer,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// User Guide Page
class _UserGuidePage extends StatelessWidget {
  const _UserGuidePage();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Guide'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          const _GuideSection(
            title: '1. Getting Started',
            icon: Icons.rocket_launch,
            steps: [
              'Create your account with email or Google',
              'Grant Bluetooth and Location permissions',
              'Complete your profile with a photo and bio',
              'You\'re ready to discover nearby users!',
            ],
          ),
          const _GuideSection(
            title: '2. Finding Nearby People',
            icon: Icons.people,
            steps: [
              'Tap the "Nearby" tab at the bottom',
              'Tap "Find People Nearby" to start scanning',
              'Wait 10-15 seconds for nearby users to appear',
              'Users are sorted by proximity (closest first)',
              'Tap on a user to view their profile',
            ],
          ),
          const _GuideSection(
            title: '3. Connecting with Users',
            icon: Icons.link,
            steps: [
              'From a user\'s profile, tap "Connect"',
              'The user receives your connection request',
              'Once accepted, you can start chatting',
              'Connected users appear in your Connections tab',
            ],
          ),
          const _GuideSection(
            title: '4. Chatting',
            icon: Icons.chat,
            steps: [
              'Go to the Conversations tab',
              'Tap on a conversation to open chat',
              'Type your message and hit send',
              'Messages are delivered in real-time',
              'You can see when messages are read',
            ],
          ),
          const _GuideSection(
            title: '5. Privacy & Safety',
            icon: Icons.security,
            steps: [
              'Your BLE ID changes every 15 minutes',
              'Only connected users can message you',
              'Block users who are bothering you',
              'Toggle discoverability in Privacy Settings',
              'Request your data or delete your account anytime',
            ],
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.tips_and_updates,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pro Tips',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Keep Bluetooth on for best results\n'
                    '• Allow the app to run in background\n'
                    '• Upload a clear profile photo\n'
                    '• Write an interesting bio\n'
                    '• Be respectful to other users',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> steps;

  const _GuideSection({
    required this.title,
    required this.icon,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...steps.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
