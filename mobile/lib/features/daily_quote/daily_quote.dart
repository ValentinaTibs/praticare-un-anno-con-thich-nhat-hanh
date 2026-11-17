import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/lanterna_theme.dart';

/// Today's quote by Thich Nhat Hanh, with the book it comes from if known.
class DailyQuote {
  final String text;
  final String? source;

  const DailyQuote({required this.text, this.source});
}

/// The backend does not serve the quotes yet (spec, section 10): until it
/// does there is no quote, and the screens leave it out.
final dailyQuoteProvider = Provider.autoDispose<DailyQuote?>((_) => null);

/// The quote, centred, with its author and source below.
class DailyQuoteText extends StatelessWidget {
  final DailyQuote quote;
  final TextStyle style;

  const DailyQuoteText(this.quote, {super.key, this.style = LanternaText.quote});

  @override
  Widget build(BuildContext context) {
    final source = quote.source;
    return Column(
      children: [
        Text(quote.text, style: style, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Text(
          source == null || source.isEmpty ? 'Thich Nhat Hanh' : 'Thich Nhat Hanh · $source',
          style: LanternaText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
