import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/lanterna_theme.dart';

// A piece of plain text: either text as it is, or a link with the address to open.
class TextSegment {
  final String text;
  final Uri? link;

  const TextSegment.text(this.text) : link = null;
  const TextSegment.link(this.text, Uri this.link);

  @override
  bool operator ==(Object other) => other is TextSegment && other.text == text && other.link == link;

  @override
  int get hashCode => Object.hash(text, link);

  @override
  String toString() => link == null ? 'text($text)' : 'link($text → $link)';
}

final _candidate = RegExp(r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);
const _trailingPunctuation = '.,;:!?\'"»”’';

// Punctuation right after a link belongs to the sentence, not to the address. A closing
// bracket stays only when the address opened it, as in Wikipedia links.
String _trimLink(String link) {
  var end = link.length;
  while (end > 0) {
    final last = link[end - 1];
    if (_trailingPunctuation.contains(last)) {
      end--;
      continue;
    }
    if (last == ')') {
      final body = link.substring(0, end);
      if ('('.allMatches(body).length < ')'.allMatches(body).length) {
        end--;
        continue;
      }
    }
    break;
  }
  return link.substring(0, end);
}

// Splits plain text into text and the links it contains, starting with http://,
// https:// or www. Nothing else is interpreted: no formatting.
List<TextSegment> splitLinks(String text) {
  final segments = <TextSegment>[];
  var start = 0;
  for (final match in _candidate.allMatches(text)) {
    final link = _trimLink(match.group(0)!);
    final uri = Uri.tryParse(link.toLowerCase().startsWith('www.') ? 'https://$link' : link);
    if (uri == null || uri.host.isEmpty) continue;
    if (match.start > start) segments.add(TextSegment.text(text.substring(start, match.start)));
    segments.add(TextSegment.link(link, uri));
    start = match.start + link.length;
  }
  if (start < text.length) segments.add(TextSegment.text(text.substring(start)));
  return segments;
}

// Opens a link outside the app: in the browser, or in the app that handles it.
// Returns false if nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri link);

final linkOpenerProvider = Provider<LinkOpener>((ref) {
  return (link) async {
    try {
      return await launchUrl(link, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  };
});

// Plain text whose links can be tapped. Images and audio are links like any other.
class LinkedText extends ConsumerStatefulWidget {
  final String text;
  final TextStyle? style;

  const LinkedText(this.text, {super.key, this.style});

  @override
  ConsumerState<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends ConsumerState<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(Uri link) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(link);
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _open(Uri link) async {
    final opened = await ref.read(linkOpenerProvider)(link);
    if (opened || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Impossibile aprire il link')),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    const linkStyle = TextStyle(
      color: LanternaColors.accent,
      decoration: TextDecoration.underline,
      decorationColor: LanternaColors.accent,
    );
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final segment in splitLinks(widget.text))
            if (segment.link case final link?)
              TextSpan(
                text: segment.text,
                style: linkStyle,
                recognizer: _recognizerFor(link),
              )
            else
              TextSpan(text: segment.text),
        ],
      ),
    );
  }
}
