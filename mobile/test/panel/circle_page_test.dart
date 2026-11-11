import 'package:community_app/core/locale.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';
import 'pump_panel.dart';

const saturdayAtNine = {'dayOfWeek': 6, 'startTime': '09:00', 'durationMinutes': 60};

Future<FakeApiClient> openCirclePage(WidgetTester tester, Map<String, Object> responses) async {
  final container = await pumpPanel(tester, role: 'admin', responses: {
    '/api/sharing-channel/channels': <Object>[],
    ...responses,
  });
  await tester.tap(find.text('Cerchio'));
  await tester.pumpAndSettle();
  return container.read(panelApiClientProvider) as FakeApiClient;
}

void main() {
  setUpAll(initItalianLocale);

  group('programmazione', () {
    testWidgets('mostra l\'appuntamento settimanale', (tester) async {
      await openCirclePage(tester, {'/api/sharing-channel/schedule': saturdayAtNine});
      expect(find.text('Ogni sabato alle 09:00, per 60 minuti'), findsOneWidget);
    });

    testWidgets('senza programmazione dice che il cerchio non si apre', (tester) async {
      await openCirclePage(tester, {});
      expect(find.text('Nessuna programmazione: il cerchio non si apre finché non la imposti.'), findsOneWidget);
    });

    testWidgets('senza dati non chiama il backend e dice cosa manca', (tester) async {
      final api = await openCirclePage(tester, {});
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(find.text('Scegli il giorno della settimana.'), findsOneWidget);
      expect(api.calls, isNot(contains('PUT /api/sharing-channel/schedule')));
    });

    testWidgets('salva giorno, ora e durata e mostra il nuovo appuntamento', (tester) async {
      // The backend answers a PUT with what it saved, and a GET with the latest save.
      late final FakeApiClient api;
      Object? saved = saturdayAtNine;
      api = await openCirclePage(tester, {
        '/api/sharing-channel/schedule': (String method, Map<String, dynamic>? _) =>
            method == 'PUT' ? saved = api.bodies.last : saved,
      });

      await tester.tap(find.text('sabato'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('domenica').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Durata in minuti'), '45');
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(api.calls, contains('PUT /api/sharing-channel/schedule'));
      expect(api.bodies.last, {'dayOfWeek': 7, 'startTime': '09:00', 'durationMinutes': 45});
      expect(find.text('Ogni domenica alle 09:00, per 45 minuti'), findsOneWidget);
    });
  });

  group('cerchi aperti', () {
    testWidgets('elenca i cerchi aperti con gruppo, chiusura, membri e messaggi', (tester) async {
      await openCirclePage(tester, {
        '/api/sharing-channel/channels': [
          channelJson('ch1', groupStartedAt: '2099-01-01T00:00:00.000', memberCount: 2, postCount: 1),
          channelJson('ch2', groupStartedAt: '2098-03-01T00:00:00.000', memberCount: 1, postCount: 0),
        ],
      });

      expect(find.text('Gruppo dal 1 gennaio 2099'), findsOneWidget);
      expect(find.text('Gruppo dal 1 marzo 2098'), findsOneWidget);
      expect(find.text('Chiude il 3 gennaio 2099, 10:00 · 2 membri · 1 messaggio'), findsOneWidget);
      expect(find.text('Chiude il 3 gennaio 2099, 10:00 · 1 membro · 0 messaggi'), findsOneWidget);
    });

    testWidgets('senza cerchi aperti lo dice', (tester) async {
      await openCirclePage(tester, {});
      expect(find.text('Nessun cerchio aperto'), findsOneWidget);
    });

    testWidgets('scelto un cerchio mostra membri e messaggi con l\'autore', (tester) async {
      await openCirclePage(tester, {
        '/api/sharing-channel/channels': [channelJson('ch1', memberCount: 2, postCount: 1)],
        '/api/sharing-channel/channels/ch1': detailJson(
          members: ['Anna Rossi', 'Marco Bianchi'],
          posts: [('p1', 'Anna Rossi', 'Oggi mi sento grata')],
        ),
      });

      await tester.tap(find.text('Gruppo dal 1 gennaio 2099'));
      await tester.pumpAndSettle();

      expect(find.text('Anna Rossi'), findsWidgets);
      expect(find.text('Marco Bianchi'), findsOneWidget);
      expect(find.text('Oggi mi sento grata'), findsOneWidget);
    });

    testWidgets('«Cancella» chiede conferma e toglie il messaggio', (tester) async {
      final messages = <(String, String, String)>[('p1', 'Anna Rossi', 'Da togliere')];
      final api = await openCirclePage(tester, {
        '/api/sharing-channel/channels': [channelJson('ch1')],
        '/api/sharing-channel/channels/ch1': (String _, Map<String, dynamic>? __) =>
            detailJson(members: ['Anna Rossi'], posts: messages),
        '/api/sharing-channel/posts/p1': (String _, Map<String, dynamic>? __) {
          messages.clear();
          return '';
        },
      });
      await tester.tap(find.text('Gruppo dal 1 gennaio 2099'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancella'));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains('DELETE /api/sharing-channel/posts/p1')));

      await tester.tap(find.widgetWithText(FilledButton, 'Cancella'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('DELETE /api/sharing-channel/posts/p1'));
      expect(find.text('Da togliere'), findsNothing);
    });

    group('aggiornamento', () {
      // A circle whose messages change on the backend after the page has loaded them.
      Future<void Function(String)> openCircleWithLiveMessages(WidgetTester tester) async {
        final messages = <(String, String, String)>[('p1', 'Anna Rossi', 'Primo messaggio')];
        await openCirclePage(tester, {
          '/api/sharing-channel/channels': [channelJson('ch1')],
          '/api/sharing-channel/channels/ch1': (String _, Map<String, dynamic>? __) =>
              detailJson(members: ['Anna Rossi'], posts: messages),
        });
        await tester.tap(find.text('Gruppo dal 1 gennaio 2099'));
        await tester.pumpAndSettle();
        return (content) => messages.add(('p${messages.length + 1}', 'Anna Rossi', content));
      }

      testWidgets('membri e messaggi si aggiornano da soli ogni 10 secondi', (tester) async {
        final write = await openCircleWithLiveMessages(tester);
        write('Arrivato dopo');

        expect(find.text('Arrivato dopo'), findsNothing);

        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(find.text('Arrivato dopo'), findsOneWidget);
      });

      testWidgets('«Aggiorna» ricarica subito membri e messaggi', (tester) async {
        final write = await openCircleWithLiveMessages(tester);
        write('Arrivato dopo');

        await tester.tap(find.text('Aggiorna'));
        await tester.pumpAndSettle();

        expect(find.text('Arrivato dopo'), findsOneWidget);
      });
    });
  });
}

/// A circle as GET /api/sharing-channel/channels/:id returns it; names are "Name Surname".
Map<String, dynamic> detailJson({List<String> members = const [], List<(String, String, String)> posts = const []}) {
  Map<String, dynamic> person(String fullName) {
    final [name, surname] = fullName.split(' ');
    return {'id': 'u-$name', 'name': name, 'surname': surname};
  }

  return {
    ...channelJson('ch1'),
    'members': [
      for (final m in members) {'joinedAt': '2099-01-03T09:05:00.000', 'user': person(m)},
    ],
    'posts': [
      for (final (id, author, content) in posts)
        {'id': id, 'content': content, 'createdAt': '2099-01-03T09:10:00.000', 'author': person(author)},
    ],
  };
}

Map<String, dynamic> channelJson(
  String id, {
  String groupStartedAt = '2099-01-01T00:00:00.000',
  int memberCount = 0,
  int postCount = 0,
}) =>
    {
      'id': id,
      'openedAt': '2099-01-03T09:00:00.000',
      'scheduledClosedAt': '2099-01-03T10:00:00.000',
      'group': {'id': 'g-$id', 'startedAt': groupStartedAt},
      'memberCount': memberCount,
      'postCount': postCount,
    };
