import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Help and support page with FAQs and contact information.
class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                  leading: const Icon(Icons.bluetooth),
                  title: const Text('Bluetooth & Battery settings'),
                  subtitle: const Text('Fix discovery on some phones'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateToBluetoothBatteryHelp(context),
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
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.feedback),
                  title: const Text('Send Feedback'),
                  subtitle: const Text('Share your thoughts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showFeedbackDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: const Text('Suggest a Feature'),
                  subtitle: const Text('Share your ideas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showFeatureSuggestionDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Contact Section
          Text(
            'Contact Us',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('Email Support'),
                  subtitle: const Text('support@rediusapp.tech'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchEmail(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Website'),
                  subtitle: const Text('https://radiusapp.tech/'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchWebsite(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.policy),
                  title: const Text('Privacy Policy'),
                  subtitle: const Text('How we protect your data'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateToPrivacyPolicy(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Terms of Service'),
                  subtitle: const Text('App usage terms'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateToTermsOfService(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // App Info
          Text(
            'App Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
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
          const SizedBox(height: 32),

          // Developer Attribution
          Center(
            child: Column(
              children: [
                Text(
                  'Developed by',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CodeShowOff',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u00a9 2026 All rights reserved',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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

  void _navigateToBluetoothBatteryHelp(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _BluetoothBatteryHelpPage(),
      ),
    );
  }

  void _navigateToPrivacyPolicy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _PrivacyPolicyPage(),
      ),
    );
  }

  void _navigateToTermsOfService(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _TermsOfServicePage(),
      ),
    );
  }

  Future<void> _showReportBugDialog(BuildContext context) async {
    try {
      // Collect device information
      String deviceInfo = '';

      if (Platform.isAndroid) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo = '''
Platform: Android
Device: ${androidInfo.manufacturer} ${androidInfo.model}
Android Version: ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})
Brand: ${androidInfo.brand}
''';
      } else if (Platform.isIOS) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo = '''
Platform: iOS
Device: ${iosInfo.name} (${iosInfo.model})
iOS Version: ${iosInfo.systemVersion}
''';
      } else {
        deviceInfo = 'Platform: ${Platform.operatingSystem}';
      }

      // Create email body with bug report template
      final emailBody = Uri.encodeComponent('''
Please describe the bug you encountered:



---
Device Information:
$deviceInfo
App Version: 1.0.0
Build: 1
''');

      // Launch email client with pre-filled bug report
      final Uri emailUri = Uri.parse(
        'mailto:support@radiusapp.tech?subject=Bug Report&body=$emailBody',
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Opening email app. Please describe the bug and send to support@radiusapp.tech'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Fallback if email client not available
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please email your bug report to support@radiusapp.tech'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening email: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showFeedbackDialog(BuildContext context) async {
    try {
      // Collect device information
      String deviceInfo = '';

      if (Platform.isAndroid) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo =
            '''\nDevice: ${androidInfo.manufacturer} ${androidInfo.model} (Android ${androidInfo.version.release})''';
      } else if (Platform.isIOS) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo =
            '''\nDevice: ${iosInfo.name} (iOS ${iosInfo.systemVersion})''';
      }

      // Create email body with feedback template
      final emailBody = Uri.encodeComponent('''
Please share your feedback:



---
App Version: 1.0.0$deviceInfo
''');

      // Launch email client with pre-filled feedback
      final Uri emailUri = Uri.parse(
        'mailto:support@radiusapp.tech?subject=Radius Feedback&body=$emailBody',
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Opening email app. Please share your feedback and send to support@radiusapp.tech'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Please email your feedback to support@radiusapp.tech'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening email: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showFeatureSuggestionDialog(BuildContext context) async {
    try {
      // Collect device information
      String deviceInfo = '';

      if (Platform.isAndroid) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo =
            '''\nDevice: ${androidInfo.manufacturer} ${androidInfo.model} (Android ${androidInfo.version.release})''';
      } else if (Platform.isIOS) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo =
            '''\nDevice: ${iosInfo.name} (iOS ${iosInfo.systemVersion})''';
      }

      // Create email body with feature suggestion template
      final emailBody = Uri.encodeComponent('''
Please describe your feature suggestion:



---
App Version: 1.0.0$deviceInfo
''');

      // Launch email client with pre-filled suggestion
      final Uri emailUri = Uri.parse(
        'mailto:support@radiusapp.tech?subject=Feature Suggestion&body=$emailBody',
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Opening email app. Please describe your suggestion and send to support@radiusapp.tech'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please email your suggestion to support@radiusapp.tech'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening email: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@radiusapp.tech',
      query: 'subject=Radius App Support',
    );
    try {
      await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      // Email client not available
    }
  }

  Future<void> _launchWebsite() async {
    final Uri websiteUri = Uri.parse('https://radiusapp.tech/');
    try {
      await launchUrl(
        websiteUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      // Browser not available
    }
  }
}

class _BluetoothBatteryHelpPage extends StatelessWidget {
  const _BluetoothBatteryHelpPage();

  Future<_AndroidDeviceSummary?> _getAndroidDeviceSummary() async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _AndroidDeviceSummary(
        manufacturer: info.manufacturer.trim(),
        brand: info.brand.trim(),
        model: info.model.trim(),
        sdkInt: info.version.sdkInt,
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _oemGuidanceFor(_AndroidDeviceSummary? d) {
    final manufacturer = (d?.manufacturer ?? '').toLowerCase();
    final brand = (d?.brand ?? '').toLowerCase();

    final key = manufacturer.isNotEmpty ? manufacturer : brand;

    if (key.contains('xiaomi') ||
        key.contains('redmi') ||
        key.contains('poco')) {
      return const [
        'Settings → Apps → Radius → Battery saver: set to “No restrictions”.',
        'Enable Autostart for Radius (if available).',
        'Lock Radius in Recents (app icon → Lock) to reduce kills.',
      ];
    }

    if (key.contains('huawei') || key.contains('honor')) {
      return const [
        'Battery optimization: set Radius to “Not allowed to optimize”.',
        'App launch: manage manually; allow auto-launch + background activity.',
      ];
    }

    if (key.contains('samsung')) {
      return const [
        'Battery: set Radius to “Unrestricted” (or disable “Put unused apps to sleep” for it).',
        'Make sure Bluetooth is ON and keep the app open for best discovery.',
      ];
    }

    if (key.contains('oppo') ||
        key.contains('realme') ||
        key.contains('vivo')) {
      return const [
        'Allow background activity / disable app sleep for Radius.',
        'Battery optimization: set Radius to “Don’t optimize” / “No restrictions”.',
      ];
    }

    if (key.contains('oneplus')) {
      return const [
        'Battery optimization: set Radius to “Don’t optimize”.',
        'Disable aggressive sleep/hibernation for Radius if available.',
      ];
    }

    return const [
      'Battery optimization: set Radius to “Don’t optimize” / “Unrestricted” if available.',
      'Keep the app open (foreground or in recent apps) for best discovery.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bluetooth & Battery settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discovery basics',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Radius discovers nearby users using Bluetooth Low Energy (BLE). '
                    'By default, advertising runs while the app is open (foreground or in recent apps). '
                    'You can optionally enable Background Advertising in Bluetooth Settings to stay discoverable even after closing the app. '
                    'Scanning runs for 15 seconds when you tap "Find People Nearby". '
                    'For best results, keep Bluetooth enabled and grant all requested permissions.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await openAppSettings();
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Open app settings'),
                      ),
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android)
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Permission.bluetoothScan.request();
                            await Permission.bluetoothConnect.request();
                            await Permission.bluetoothAdvertise.request();
                          },
                          icon: const Icon(Icons.security_outlined),
                          label: const Text('Request Bluetooth permissions'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Battery optimization (Android)',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Some Android phones aggressively pause Bluetooth scanning/advertising when battery optimizations are enabled. If discovery is unreliable, set Radius to “Unrestricted” / “No restrictions” and disable app sleep features.',
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<_AndroidDeviceSummary?>(
                    future: _getAndroidDeviceSummary(),
                    builder: (context, snap) {
                      if (defaultTargetPlatform != TargetPlatform.android) {
                        return Text(
                          'On iOS, discovery works best when the app is open. '
                          'Keep Radius in foreground or recent apps for continuous advertising.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                          ),
                        );
                      }

                      final summary = snap.data;
                      final steps = _oemGuidanceFor(summary);
                      final deviceLine = summary == null
                          ? 'Your Android device'
                          : 'Device: ${summary.manufacturer.isEmpty ? summary.brand : summary.manufacturer} ${summary.model} (SDK ${summary.sdkInt})'
                              .trim();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceLine, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          for (final s in steps)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '• ',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      s,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'If you still see no nearby users',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try these quick checks:\n'
                    '• Turn Bluetooth OFF then ON.\n'
                    '• Ensure Location is not required (Radius uses Android 12+ Bluetooth permissions).\n'
                    '• Keep the screen on and stay on the Nearby page during scanning.\n'
                    '• Test with another phone using nRF Connect/LightBlue to confirm advertisements are visible.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
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

class _AndroidDeviceSummary {
  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;

  const _AndroidDeviceSummary({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.sdkInt,
  });
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
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
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
        title: const Text(
          'Frequently Asked Questions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: const [
          _FAQItem(
            question: 'How does Radius find nearby users?',
            answer:
                'Radius uses Bluetooth Low Energy (BLE) to detect other Radius users within approximately 30 meters. '
                'Your phone broadcasts your username via BLE for discovery. '
                'When another user is detected, the app looks up their full profile from our servers. '
                'By default, discovery runs while the app is open (foreground or in recent apps). '
                'If you\'d like to stay discoverable even after closing the app, you can enable the optional Background Advertising setting in Bluetooth Settings.',
          ),
          _FAQItem(
            question: 'Does Radius drain my battery?',
            answer:
                'Radius is optimized for battery efficiency. It uses BLE which consumes minimal power. '
                'Scanning runs for 15 seconds when you tap "Find People Nearby", and advertising runs while the app is open. '
                'If you enable the optional Background Advertising, it uses a lightweight service that has negligible battery impact. '
                'Most users report less than 5% additional battery drain per day.',
          ),
          _FAQItem(
            question: 'Is my data private and secure?',
            answer: 'Yes! Your privacy is our top priority:\n'
                '• Your username is broadcast for discovery (visible to nearby Radius users)\n'
                '• Only connected users can chat with you\n'
                '• All chat messages are encrypted in transit\n'
                '• You can disconnect from any user to disable chatting while preserving chat history\n'
                '• We never sell your data to third parties',
          ),
          _FAQItem(
            question: 'Do I need location permissions for Bluetooth?',
            answer:
                'No. Radius uses Android 12+ Bluetooth permissions (Scan/Connect/Advertise) and does not request location permissions. '
                'We do NOT access GPS or collect your location.',
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
                'Simply close the app to stop advertising. '
                'You can also go to Profile → Privacy Settings to manage visibility. '
                'If you have Background Advertising enabled, you can turn it off anytime in Bluetooth Settings. '
                'Scanning only runs when you tap "Find People Nearby".',
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
                'You can disconnect or block any user from their profile or chat. Blocked users cannot:\n'
                '• Send you connection requests\n'
                '• See you in their discovery\n'
                '• Message you\n'
                'Disconnecting preserves chat history but disables messaging. '
                'Go to Privacy Settings → Manage Blocked Users to view your blocked list.',
          ),
          _FAQItem(
            question: 'What are Random Group Chatrooms?',
            answer:
                'Random Group Chatrooms are internet-based groups organized by topics and interests. '
                'Users can create groups or request to join existing ones. '
                'Group admins review and approve join requests to maintain quality discussions. '
                'Perfect for finding like-minded people worldwide! '
                'You can browse active groups, request to join, and start chatting once approved.',
          ),
          _FAQItem(
            question: 'How do Nearby Groups work?',
            answer:
                'Nearby Groups use Bluetooth to create temporary group chats for spontaneous meetups. '
                'When you create a nearby group, your device automatically detects and adds users around you. '
                'No approval needed - members join automatically when detected nearby. '
                'Perfect for events, gatherings, conferences, or any situation where you want to chat with everyone nearby! '
                'The group remains active as long as the creator keeps scanning.',
          ),
          _FAQItem(
            question: 'What is Nearby Help?',
            answer:
                'Nearby Help lets you request or provide assistance to people in your vicinity. '
                'When you need help, users within your selected radius (up to 5km) receive a push notification. '
                'Available helpers can accept your request and navigate to your location using in-app directions. '
                'You can set home and work locations to receive help alerts only when you\'re nearby. '
                'It\'s about building a caring, helpful community!',
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        title: const Text(
          'User Guide',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          const _GuideSection(
            title: '1. Getting Started',
            icon: Icons.rocket_launch,
            steps: [
              'Create your account with email or Google',
              'Grant Bluetooth permissions when prompted',
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
              'Your username is broadcast via Bluetooth for discovery',
              'Only connected users can message you',
              'Disconnect or block users who are bothering you',
              'Toggle discoverability in Privacy Settings',
              'Request your data or delete your account anytime',
            ],
          ),
          const _GuideSection(
            title: '6. Random Group Chatrooms',
            icon: Icons.groups,
            steps: [
              'Tap "Groups" tab and select "Random Groups"',
              'Browse active groups by topic and interest',
              'Tap "Request to Join" and optionally add a message',
              'Wait for admin approval (you\'ll get notified)',
              'Once approved, start chatting with group members',
              'Create your own group and manage join requests as admin',
            ],
          ),
          const _GuideSection(
            title: '7. Nearby Groups',
            icon: Icons.bluetooth_searching,
            steps: [
              'Go to "Groups" tab and select "Nearby Groups"',
              'Tap "Create Group" and give it a name/description',
              'Your device will scan for nearby Radius users',
              'Detected users automatically join your group',
              'Start chatting - no approval needed!',
              'Close the group when done to stop scanning',
            ],
          ),
          const _GuideSection(
            title: '8. Nearby Help',
            icon: Icons.help_outline,
            steps: [
              'Tap "Help" tab to access Nearby Help',
              'Set your home/work locations in settings (optional)',
              'When you need help: Tap "Request Help", select radius, add topic',
              'Nearby users receive notifications and can accept',
              'Chat with your helper and they can navigate to you',
              'Mark as resolved when help is complete',
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
                    '• Keep the app open while using Nearby\n'
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
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
                            color: Theme.of(context).colorScheme.onSurface,
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

// Privacy Policy Page
class _PrivacyPolicyPage extends StatelessWidget {
  const _PrivacyPolicyPage();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          Text(
            'Last Updated: February 2, 2026',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          const _PolicySection(
            title: '1. Introduction',
            content:
                'Welcome to Radius, a proximity-based social networking application developed by CodeShowOff. '
                'We are committed to protecting your privacy and ensuring the security of your personal information. '
                'This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.\n\n'
                'By using Radius, you agree to the collection and use of information in accordance with this Privacy Policy. '
                'If you do not agree with our policies and practices, please do not use our app.',
          ),
          const _PolicySection(
            title: '2. Information We Collect',
            content:
                'We collect information that you provide directly to us:\n\n'
                '• Account Information: Email address, display name, username, profile photo, and bio\n'
                '• User-Generated Content: Messages, chat history, connection requests, and profile updates\n'
                '• Device Information: Device model, operating system version, and app version (for bug reporting and support)\n\n'
                'Information collected automatically:\n\n'
                '• Bluetooth Discovery: Your 7-character username is broadcast via Bluetooth Low Energy (BLE) for nearby user discovery\n'
                '• Usage Data: App interactions, feature usage, and crash reports\n'
                '• Authentication Data: Firebase Authentication tokens for secure login\n\n'
                'Device & Session Information (collected during login/registration for security purposes):\n\n'
                '• Device Details: Brand, model, type (phone/tablet/emulator), screen resolution, screen density\n'
                '• Operating System: Platform (Android/iOS), OS version, build number\n'
                '• App Details: App version, build number, install source (Play Store/App Store/sideload)\n'
                '• Network Information: IP address (IPv4/IPv6), network type (WiFi/cellular), carrier name\n'
                '• Approximate Location: Country and city (derived from IP address, NOT GPS)\n'
                '• ISP Information: Internet Service Provider name and ASN\n\n'
                'This device and session information is collected ONLY when you log in or register, and is used exclusively for:\n'
                '• Detecting and preventing unauthorized account access\n'
                '• Identifying suspicious login patterns and security threats\n'
                '• Debugging technical issues and improving app stability\n'
                '• Ensuring account security and fraud prevention\n\n'
                'We do NOT collect:\n\n'
                '• GPS location or precise geographic coordinates\n'
                '• Contact lists or phonebook data\n'
                '• Microphone or camera access without your explicit permission\n'
                '• Third-party social media data beyond Google Sign-In',
          ),
          const _PolicySection(
            title: '3. How We Use Your Information',
            content: 'We use the collected information for:\n\n'
                '• Providing Core Services: User discovery, connection management, and real-time messaging\n'
                '• Account Management: Authentication, profile customization, and account recovery\n'
                '• Communication: Sending notifications for connection requests and new messages\n'
                '• Improvement: Analyzing usage patterns to enhance app features and performance\n'
                '• Security: Detecting and preventing fraud, abuse, and technical issues\n'
                '• Support: Responding to your inquiries and providing customer assistance',
          ),
          const _PolicySection(
            title: '4. Bluetooth Discovery & Privacy',
            content:
                'Radius uses Bluetooth Low Energy (BLE) for proximity-based user discovery:\n\n'
                '• Your username is broadcast via BLE advertising when the app is open\n'
                '• Other Radius users within approximately 30 meters can discover your username\n'
                '• We do not collect or store your GPS location\n'
                '• Discovery requires Bluetooth permissions but NOT location permissions (Android 12+)\n'
                '• You can stop being discoverable by closing the app or adjusting privacy settings\n'
                '• Only users you accept as connections can message you\n\n'
                'Optional Background Advertising:\n\n'
                '• You may choose to enable Background Advertising in Bluetooth Settings\n'
                '• When enabled, your username continues to be broadcast via BLE even after the app is closed\n'
                '• This is entirely optional and off by default — you are always in control\n'
                '• Only your username is broadcast; no other personal data is shared\n'
                '• You can disable it at any time from Bluetooth Settings\n\n'
                'Bluetooth is also used for:\n\n'
                '• Nearby Groups: Auto-detecting and adding members within Bluetooth range',
          ),
          const _PolicySection(
            title: '5. Location-Based Features',
            content:
                'Nearby Help is our only feature that uses GPS location data:\n\n'
                '• Location access is requested ONLY when you use Nearby Help\n'
                '• Your location is shared ONLY when you request help or accept a help request\n'
                '• Helpers can navigate to your location only during an active help session\n'
                '• You can set home and work locations (stored as coordinates) to receive alerts only when nearby\n'
                '• Your approximate city is derived from IP address for help request radius calculations\n'
                '• We do NOT track or store your location history\n'
                '• Location permissions can be revoked anytime in device settings\n\n'
                'All other features (Nearby users, Nearby Groups, Random Groups) use only Bluetooth and do NOT access GPS.',
          ),
          const _PolicySection(
            title: '6. Group Features & Data',
            content:
                'Radius offers multiple group chat features with different privacy models:\n\n'
                'Random Group Chatrooms:\n'
                '• Internet-based groups visible to all Radius users\n'
                '• Group names, topics, descriptions, and member counts are public\n'
                '• Join requests and chat messages are visible only to approved members\n'
                '• Admins can view pending join requests and member lists\n'
                '• Chat history is stored until you leave the group or the group is deleted\n\n'
                'Nearby Groups:\n'
                '• Temporary Bluetooth-based groups for local gatherings\n'
                '• Group information is visible to all users while active\n'
                '• Members are auto-added based on Bluetooth proximity to creator\n'
                '• Member presence data (RSSI signal strength, timestamps) is stored temporarily\n'
                '• Groups and messages are deleted when the creator closes the group or after inactivity\n\n'
                'Location Groups:\n'
                '• City/region-based community groups\n'
                '• Join approval may be required depending on group settings\n'
                '• Members can see other members\' profiles and chat history',
          ),
          const _PolicySection(
            title: '7. Nearby Help Data',
            content: 'When you use Nearby Help:\n\n'
                '• Your GPS coordinates are collected when you request help\n'
                '• Help requests include: your location, selected radius, topic, and contact info\n'
                '• Nearby users within the radius receive push notifications with your name and topic\n'
                '• Helpers who accept can see your real-time location for navigation\n'
                '• Help session data (locations, chat messages, timestamps) is stored for 30 days\n'
                '• You can mark requests as resolved or cancel them anytime\n'
                '• Your saved home/work locations are stored as coordinates only\n\n'
                'Location data is NOT used or accessed by any other app features.',
          ),
          const _PolicySection(
            title: '8. Data Storage & Security',
            content: 'We implement industry-standard security measures:\n\n'
                '• All data is stored in Firebase Cloud Firestore with encryption at rest\n'
                '• Messages are encrypted in transit using TLS/SSL protocols\n'
                '• User passwords are hashed and never stored in plain text\n'
                '• Access to user data is restricted to authorized personnel only\n'
                '• Regular security audits and vulnerability assessments\n\n'
                'While we strive to protect your information, no method of transmission over the internet or electronic storage is 100% secure. '
                'We cannot guarantee absolute security.',
          ),
          const _PolicySection(
            title: '9. Data Sharing & Disclosure',
            content:
                'We do NOT sell your personal information to third parties. We may share your information only in the following circumstances:\n\n'
                '• With Other Users: Your profile information (name, photo, bio) is visible to users you connect with\n'
                '• Service Providers: Firebase (Google Cloud) for authentication, database, and cloud storage\n'
                '• Legal Requirements: When required by law, court order, or government request\n'
                '• Safety & Security: To prevent fraud, abuse, or threats to user safety\n'
                '• Business Transfers: In the event of a merger, acquisition, or sale of assets (with notice)',
          ),
          const _PolicySection(
            title: '10. Your Privacy Rights',
            content: 'You have the following rights regarding your data:\n\n'
                '• Access: Request a copy of your personal data\n'
                '• Correction: Update or correct inaccurate information\n'
                '• Deletion: Request deletion of your account and associated data\n'
                '• Portability: Export your data in a machine-readable format\n'
                '• Objection: Opt-out of certain data processing activities\n'
                '• Revocation: Withdraw consent at any time\n\n'
                'To exercise these rights, contact us at support@radiusapp.tech. We will respond within 30 days.',
          ),
          const _PolicySection(
            title: '11. Data Retention',
            content:
                'We retain your information for as long as your account is active or as needed to provide services:\n\n'
                '• Account Data: Retained until you delete your account\n'
                '• Chat Messages: Stored until manually deleted by you or your connection\n'
                '• Device Session Logs: Retained for up to 90 days for security monitoring and debugging purposes\n'
                '• Deleted Accounts: Data is permanently deleted within 90 days of account deletion\n'
                '• Legal Requirements: Some data may be retained longer if required by law',
          ),
          const _PolicySection(
            title: '12. Children\'s Privacy',
            content:
                'Radius is not intended for users under the age of 13 (or 16 in the European Union). '
                'We do not knowingly collect personal information from children. If we become aware that a child has provided us with personal information, '
                'we will take steps to delete such information immediately. If you believe a child has provided information to us, please contact us at support@radiusapp.tech.',
          ),
          const _PolicySection(
            title: '13. International Data Transfers',
            content:
                'Your information may be transferred to and processed in countries other than your own. '
                'We use Firebase (Google Cloud) services, which may process data in multiple regions. '
                'We ensure appropriate safeguards are in place to protect your information in compliance with applicable data protection laws.',
          ),
          const _PolicySection(
            title: '14. Third-Party Services',
            content:
                'Radius integrates with the following third-party services:\n\n'
                '• Firebase Authentication: For secure login (Google Sign-In)\n'
                '• Firebase Firestore: For data storage\n'
                '• Firebase Cloud Storage: For profile photos and media\n'
                '• Firebase Cloud Messaging: For push notifications\n\n'
                'These services have their own privacy policies. We recommend reviewing Google\'s Privacy Policy at https://policies.google.com/privacy',
          ),
          const _PolicySection(
            title: '15. Changes to This Privacy Policy',
            content:
                'We may update this Privacy Policy from time to time to reflect changes in our practices or for legal, operational, or regulatory reasons. '
                'We will notify you of any material changes by posting the updated policy in the app and updating the "Last Updated" date. '
                'Your continued use of Radius after changes constitutes acceptance of the updated policy.',
          ),
          const _PolicySection(
            title: '16. Contact Us',
            content:
                'If you have any questions, concerns, or requests regarding this Privacy Policy or your personal information, please contact us:\n\n'
                'Email: support@radiusapp.tech\n'
                'Developer: CodeShowOff\n\n'
                'We will respond to your inquiry within 30 business days.',
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '\u00a9 2026 CodeShowOff. All rights reserved.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Terms of Service Page
class _TermsOfServicePage extends StatelessWidget {
  const _TermsOfServicePage();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Terms of Service',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          Text(
            'Last Updated: February 2, 2026',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          const _PolicySection(
            title: '1. Acceptance of Terms',
            content:
                'By downloading, installing, accessing, or using Radius ("the App"), you agree to be bound by these Terms of Service ("Terms"). '
                'If you do not agree to these Terms, do not use the App. These Terms constitute a legally binding agreement between you and CodeShowOff ("we," "us," or "our").',
          ),
          const _PolicySection(
            title: '2. Eligibility',
            content:
                'You must be at least 13 years old (or 16 years old in the European Union) to use Radius. '
                'By using the App, you represent and warrant that you meet this age requirement. '
                'If you are under 18, you confirm that you have obtained parental or guardian consent to use the App.',
          ),
          const _PolicySection(
            title: '3. Account Registration',
            content:
                'To use Radius, you must create an account by providing:\n\n'
                '• A valid email address or Google account\n'
                '• A unique display name and username\n'
                '• A profile photo (optional)\n\n'
                'You are responsible for:\n\n'
                '• Maintaining the confidentiality of your account credentials\n'
                '• All activities that occur under your account\n'
                '• Notifying us immediately of any unauthorized access\n\n'
                'You agree to provide accurate, current, and complete information during registration and to update such information as necessary.',
          ),
          const _PolicySection(
            title: '4. Acceptable Use Policy',
            content:
                'You agree to use Radius only for lawful purposes and in accordance with these Terms. You agree NOT to:\n\n'
                '• Violate any applicable laws or regulations\n'
                '• Harass, abuse, threaten, or intimidate other users\n'
                '• Impersonate any person or entity or misrepresent your affiliation\n'
                '• Post or transmit any content that is illegal, harmful, threatening, abusive, harassing, defamatory, vulgar, obscene, or otherwise objectionable\n'
                '• Upload or share any content that infringes on intellectual property rights, privacy rights, or other rights of any party\n'
                '• Transmit spam, unsolicited messages, or advertisements\n'
                '• Attempt to gain unauthorized access to the App, other accounts, or computer systems\n'
                '• Use the App for commercial purposes without our prior written consent\n'
                '• Reverse engineer, decompile, or disassemble the App\n'
                '• Use automated tools, bots, or scripts to access or interact with the App',
          ),
          const _PolicySection(
            title: '5. User-Generated Content',
            content:
                'You retain ownership of any content you create, post, or share through Radius ("User Content"). '
                'By posting User Content, you grant us a worldwide, non-exclusive, royalty-free, transferable license to use, reproduce, modify, display, and distribute your User Content solely for the purpose of operating and improving the App.\n\n'
                'You represent and warrant that:\n\n'
                '• You own or have the necessary rights to your User Content\n'
                '• Your User Content does not violate these Terms or any applicable laws\n'
                '• Your User Content does not infringe on the rights of any third party\n\n'
                'We reserve the right to remove any User Content that violates these Terms or is otherwise objectionable, without prior notice.',
          ),
          const _PolicySection(
            title: '6. Bluetooth Discovery & Proximity Features',
            content:
                'Radius uses Bluetooth Low Energy (BLE) for proximity-based user discovery:\n\n'
                '• Your username is broadcast via BLE when the app is open, making you discoverable to nearby users\n'
                '• By default, Bluetooth advertising runs while the app is in the foreground or recent apps\n'
                '• You may optionally enable Background Advertising to stay discoverable after closing the app — this is off by default and fully under your control\n'
                '• Scanning for nearby users runs for 10 seconds when you tap the "Scan" button\n'
                '• We do not collect or track your GPS location\n'
                '• You can control your discoverability by closing the app, disabling Background Advertising, or adjusting privacy settings\n\n'
                'You acknowledge and agree that:\n\n'
                '• Bluetooth discovery is inherently proximity-based and may reveal your general location to nearby users\n'
                '• We are not responsible for how other users use the proximity information\n'
                '• Discovery functionality may vary based on device capabilities and environmental factors',
          ),
          const _PolicySection(
            title: '7. Privacy & Data Protection',
            content:
                'Your privacy is important to us. Our Privacy Policy explains how we collect, use, and protect your information. '
                'By using Radius, you consent to the collection and use of your information as described in the Privacy Policy. '
                'Please review our Privacy Policy at Help & Support > Privacy Policy.',
          ),
          const _PolicySection(
            title: '8. Connections & Messaging',
            content:
                'Radius allows you to connect with nearby users and exchange messages:\n\n'
                '• You can send connection requests to other users\n'
                '• Other users can accept or decline your requests\n'
                '• Only accepted connections can exchange messages\n'
                '• You can disconnect from or block any user at any time\n'
                '• Blocked users cannot send you connection requests or messages\n\n'
                'We do not monitor the content of private messages between users. However, we may review reported content to enforce these Terms and take appropriate action against users who violate our policies.',
          ),
          const _PolicySection(
            title: '9. Group Features',
            content: 'Radius offers multiple group chat features:\n\n'
                'Random Group Chatrooms:\n'
                '• You can create or request to join internet-based groups\n'
                '• Group admins review and approve/reject join requests\n'
                '• Admins can remove members and manage group settings\n'
                '• You agree not to create groups for illegal or harmful purposes\n'
                '• Inappropriate group names, descriptions, or content may be removed\n\n'
                'Nearby Groups:\n'
                '• Create temporary Bluetooth-based groups for local gatherings\n'
                '• Your device automatically adds nearby users to the group\n'
                '• Members are auto-removed when out of Bluetooth range\n'
                '• Only the creator can close the group\n'
                '• Groups expire after 30 minutes or when creator stops scanning\n\n'
                'Location Groups:\n'
                '• Community groups organized by city or region\n'
                '• May require admin approval to join\n'
                '• Subject to additional community guidelines set by admins',
          ),
          const _PolicySection(
            title: '10. Nearby Help Feature',
            content:
                'Nearby Help allows you to request or provide assistance:\n\n'
                'When requesting help:\n'
                '• You must allow location access to use this feature\n'
                '• Your real-time location is shared with users who accept your request\n'
                '• You agree to use this feature only for legitimate help requests\n'
                '• False, frivolous, or inappropriate help requests are prohibited\n'
                '• You can cancel requests at any time\n\n'
                'When providing help:\n'
                '• You choose whether to accept or decline help requests\n'
                '• You can navigate to the requester\'s location using in-app directions\n'
                '• You agree to provide help in good faith and with genuine intent\n'
                '• You can end help sessions at any time if you feel unsafe\n\n'
                'Important:\n'
                '• Always prioritize your personal safety\n'
                '• Meet in public places when possible\n'
                '• We are not responsible for interactions between users\n'
                '• Report any misuse or safety concerns immediately',
          ),
          const _PolicySection(
            title: '11. Intellectual Property Rights',
            content:
                'The App, including its design, features, functionality, graphics, logos, and underlying code, is owned by CodeShowOff and is protected by copyright, trademark, and other intellectual property laws. '
                'You are granted a limited, non-exclusive, non-transferable, revocable license to use the App for personal, non-commercial purposes.\n\n'
                'You may not:\n\n'
                '• Copy, modify, distribute, sell, or lease any part of the App\n'
                '• Reverse engineer or attempt to extract the source code of the App\n'
                '• Remove or alter any copyright, trademark, or proprietary notices',
          ),
          const _PolicySection(
            title: '12. Prohibited Activities',
            content:
                'You agree not to engage in any of the following prohibited activities:\n\n'
                '• Using the App for any illegal or unauthorized purpose\n'
                '• Attempting to interfere with, compromise, or disrupt the App or its servers\n'
                '• Collecting or harvesting information about other users without their consent\n'
                '• Creating multiple accounts to evade bans or restrictions\n'
                '• Using the App to send spam, phishing attempts, or malicious software\n'
                '• Engaging in any form of harassment, stalking, or threatening behavior\n'
                '• Posting or distributing sexually explicit, violent, or otherwise inappropriate content\n'
                '• Impersonating or falsely representing affiliation with any person or entity',
          ),
          const _PolicySection(
            title: '13. Account Suspension & Termination',
            content:
                'We reserve the right to suspend or terminate your account at any time, without prior notice, for:\n\n'
                '• Violation of these Terms\n'
                '• Fraudulent, abusive, or illegal activity\n'
                '• Extended periods of inactivity\n'
                '• At our sole discretion if we believe it is in the best interest of the App or other users\n\n'
                'Upon termination:\n\n'
                '• Your access to the App will be immediately revoked\n'
                '• Your User Content may be deleted\n'
                '• You may request deletion of your personal data as outlined in our Privacy Policy\n\n'
                'You may also delete your account at any time through the App settings. Account deletion is permanent and cannot be undone.',
          ),
          const _PolicySection(
            title: '14. Disclaimer of Warranties',
            content:
                'THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.\n\n'
                'We do not warrant that:\n\n'
                '• The App will be uninterrupted, secure, or error-free\n'
                '• The results obtained from using the App will be accurate or reliable\n'
                '• Any errors or defects in the App will be corrected\n\n'
                'You use the App at your own risk. We are not responsible for any damage to your device, loss of data, or any other harm resulting from your use of the App.',
          ),
          const _PolicySection(
            title: '15. Limitation of Liability',
            content:
                'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, CODESHOWOFF SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO:\n\n'
                '• Loss of profits, data, or goodwill\n'
                '• Service interruptions or security breaches\n'
                '• Unauthorized access to your account or User Content\n'
                '• Interactions with other users (online or offline)\n'
                '• Any damages arising from your use or inability to use the App\n\n'
                'OUR TOTAL LIABILITY TO YOU FOR ANY CLAIMS ARISING FROM YOUR USE OF THE APP SHALL NOT EXCEED THE AMOUNT YOU PAID TO US IN THE PAST 12 MONTHS (WHICH IS CURRENTLY \$0).',
          ),
          const _PolicySection(
            title: '16. Indemnification',
            content:
                'You agree to indemnify, defend, and hold harmless CodeShowOff, its affiliates, officers, directors, employees, and agents from and against any claims, liabilities, damages, losses, costs, or expenses (including reasonable attorneys\' fees) arising out of or in connection with:\n\n'
                '• Your use of the App\n'
                '• Your violation of these Terms\n'
                '• Your violation of any rights of another person or entity\n'
                '• Your User Content',
          ),
          const _PolicySection(
            title: '17. Dispute Resolution',
            content:
                'Any disputes arising out of or relating to these Terms or your use of the App shall be resolved through:\n\n'
                '1. Informal Negotiation: Contact us at support@radiusapp.tech to attempt to resolve the issue informally\n'
                '2. Arbitration: If informal resolution fails, disputes shall be resolved through binding arbitration in accordance with the rules of a mutually agreed arbitration body\n'
                '3. Governing Law: These Terms are governed by the laws of [Your Jurisdiction], without regard to conflict of law principles\n\n'
                'You agree to waive your right to participate in class action lawsuits or class-wide arbitration.',
          ),
          const _PolicySection(
            title: '18. Changes to Terms',
            content:
                'We reserve the right to modify these Terms at any time. We will notify you of material changes by:\n\n'
                '• Posting an updated version in the App\n'
                '• Updating the "Last Updated" date\n'
                '• Sending you a notification (email or in-app)\n\n'
                'Your continued use of the App after changes constitutes your acceptance of the revised Terms. If you do not agree to the updated Terms, you must stop using the App and delete your account.',
          ),
          const _PolicySection(
            title: '19. Severability',
            content:
                'If any provision of these Terms is found to be invalid, illegal, or unenforceable, the remaining provisions shall continue in full force and effect. '
                'The invalid provision shall be modified to the minimum extent necessary to make it valid and enforceable.',
          ),
          const _PolicySection(
            title: '20. Entire Agreement',
            content:
                'These Terms, together with our Privacy Policy, constitute the entire agreement between you and CodeShowOff regarding your use of Radius and supersede all prior agreements and understandings.',
          ),
          const _PolicySection(
            title: '21. Contact Information',
            content:
                'If you have any questions, concerns, or feedback regarding these Terms of Service, please contact us:\n\n'
                'Email: support@radiusapp.tech\n'
                'Developer: CodeShowOff\n\n'
                'We will respond to your inquiry within 30 business days.',
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '\u00a9 2026 CodeShowOff. All rights reserved.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widget for policy sections
class _PolicySection extends StatelessWidget {
  final String title;
  final String content;

  const _PolicySection({
    required this.title,
    required this.content,
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
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
