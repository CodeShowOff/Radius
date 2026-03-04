import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Text widget that detects URLs and email addresses and makes them tappable.
///
/// - Tapping a URL opens it in the external browser.
/// - Tapping an email opens the default mail client.
/// - Links are underlined and use [linkColor].
class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;

  /// Matches URLs (http/https/www) and email addresses.
  static final _linkRegex = RegExp(
    r'(?:https?://[^\s<>\"\)]+|www\.[^\s<>\"\)]+|[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    caseSensitive: false,
  );

  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
  });

  @override
  Widget build(BuildContext context) {
    final matches = _linkRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style);
    }
    return Text.rich(
      TextSpan(children: _buildSpans(matches)),
      style: style,
    );
  }

  List<InlineSpan> _buildSpans(List<RegExpMatch> matches) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      final linkText = match.group(0)!;
      final isEmail = linkText.contains('@') && !linkText.contains('://');

      spans.add(
        TextSpan(
          text: linkText,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openLink(linkText, isEmail),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans;
  }

  static Future<void> _openLink(String link, bool isEmail) async {
    try {
      final Uri uri;
      if (isEmail) {
        uri = Uri(scheme: 'mailto', path: link);
      } else if (link.startsWith('www.')) {
        uri = Uri.parse('https://$link');
      } else {
        uri = Uri.parse(link);
      }

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to open link: $e');
    }
  }
}
