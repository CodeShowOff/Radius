import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Text widget that detects URLs and email addresses and makes them tappable.
///
/// - Tapping a URL opens it in the external browser.
/// - Tapping an email opens the default mail client.
/// - Links are underlined and use [linkColor].
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final InlineSpan? trailingSpan;

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
    this.trailingSpan,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();

  static Future<void> openLink(String link, bool isEmail) async {
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

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dispose old recognizers before rebuilding
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final matches = LinkifiedText._linkRegex.allMatches(widget.text).toList();
    if (matches.isEmpty && widget.trailingSpan == null) {
      return Text(widget.text, style: widget.style);
    }
    final spans = matches.isEmpty
        ? <InlineSpan>[TextSpan(text: widget.text)]
        : _buildSpans(matches);
    if (widget.trailingSpan != null) {
      spans.add(widget.trailingSpan!);
    }
    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
    );
  }

  List<InlineSpan> _buildSpans(List<RegExpMatch> matches) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: widget.text.substring(lastEnd, match.start)));
      }

      final linkText = match.group(0)!;
      final isEmail = linkText.contains('@') && !linkText.contains('://');

      final recognizer = TapGestureRecognizer()
        ..onTap = () => LinkifiedText.openLink(linkText, isEmail);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: linkText,
          style: TextStyle(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
          ),
          recognizer: recognizer,
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(lastEnd)));
    }

    return spans;
  }
}
