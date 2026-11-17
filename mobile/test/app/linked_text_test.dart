import 'package:community_app/core/widgets/linked_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('riconoscimento dei link nel testo semplice', () {
    test('il testo senza link resta com\'è, senza formattazione', () {
      expect(splitLinks('Oggi *respira* con calma'), [const TextSegment.text('Oggi *respira* con calma')]);
    });

    test('un link http o https in mezzo al testo', () {
      expect(splitLinks('Ascolta https://example.org/audio.mp3 stasera'), [
        const TextSegment.text('Ascolta '),
        TextSegment.link('https://example.org/audio.mp3', Uri.parse('https://example.org/audio.mp3')),
        const TextSegment.text(' stasera'),
      ]);
    });

    test('un indirizzo che inizia con www si apre in https', () {
      expect(splitLinks('www.example.org'), [
        TextSegment.link('www.example.org', Uri.parse('https://www.example.org')),
      ]);
    });

    test('la punteggiatura dopo il link appartiene alla frase', () {
      expect(splitLinks('Guarda http://example.org/foto.jpg.'), [
        const TextSegment.text('Guarda '),
        TextSegment.link('http://example.org/foto.jpg', Uri.parse('http://example.org/foto.jpg')),
        const TextSegment.text('.'),
      ]);
    });

    test('una parentesi chiusa resta nel link solo se il link l\'ha aperta', () {
      expect(splitLinks('(vedi https://example.org/a)'), [
        const TextSegment.text('(vedi '),
        TextSegment.link('https://example.org/a', Uri.parse('https://example.org/a')),
        const TextSegment.text(')'),
      ]);
      expect(splitLinks('https://it.wikipedia.org/wiki/Pace_(concetto)'), [
        TextSegment.link(
          'https://it.wikipedia.org/wiki/Pace_(concetto)',
          Uri.parse('https://it.wikipedia.org/wiki/Pace_(concetto)'),
        ),
      ]);
    });

    test('più link nello stesso testo', () {
      final links = splitLinks('https://a.example e https://b.example').where((s) => s.link != null);
      expect(links.map((s) => s.text), ['https://a.example', 'https://b.example']);
    });
  });

  group('tocco su un link', () {
    Future<List<Uri>> pumpLinkedText(WidgetTester tester, String text, {bool opens = true}) async {
      final opened = <Uri>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          linkOpenerProvider.overrideWithValue((link) async {
            opened.add(link);
            return opens;
          }),
        ],
        child: MaterialApp(home: Scaffold(body: LinkedText(text))),
      ));
      return opened;
    }

    testWidgets('toccando il link si apre il suo indirizzo', (tester) async {
      final opened = await pumpLinkedText(tester, 'Ascolta https://example.org/audio.mp3 stasera');

      await tester.tapOnText(find.textRange.ofSubstring('https://example.org/audio.mp3'));

      expect(opened, [Uri.parse('https://example.org/audio.mp3')]);
    });

    testWidgets('toccando il testo fuori dal link non si apre nulla', (tester) async {
      final opened = await pumpLinkedText(tester, 'Ascolta https://example.org/audio.mp3 stasera');

      await tester.tapOnText(find.textRange.ofSubstring('stasera'));

      expect(opened, isEmpty);
    });

    testWidgets('se il link non si può aprire compare un avviso', (tester) async {
      await pumpLinkedText(tester, 'https://example.org', opens: false);

      await tester.tapOnText(find.textRange.ofSubstring('https://example.org'));
      await tester.pump();

      expect(find.text('Impossibile aprire il link'), findsOneWidget);
    });
  });
}
