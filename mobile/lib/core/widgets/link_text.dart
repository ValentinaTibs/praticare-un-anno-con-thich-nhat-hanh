import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/lanterna_theme.dart';

/// Plain text whose web addresses are amber links, opened in the browser.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const LinkText(this.text, {super.key, this.style});

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  static final _url = RegExp(r'https?://[^\s<>"]+');
  // Punctuation that usually closes the sentence rather than the address.
  static final _trailing = RegExp(r'[.,;:!?)\]»”’]+$');

  final _recognizers = <TapGestureRecognizer>[];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = _build();
  }

  @override
  void didUpdateWidget(LinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _spans = _build();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  List<InlineSpan> _build() {
    _disposeRecognizers();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _url.allMatches(text)) {
      final url = match[0]!.replaceFirst(_trailing, '');
      final end = match.start + url.length;
      if (match.start > start) spans.add(TextSpan(text: text.substring(start, match.start)));
      final recognizer = TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: LanternaColors.accent, decoration: TextDecoration.underline, decorationColor: LanternaColors.accent),
        recognizer: recognizer,
      ));
      start = end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return spans;
  }

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(style: widget.style, children: _spans));
}
