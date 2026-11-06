import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/locale.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';
import 'pump_panel.dart';

Map<String, dynamic> journeyJson(List<Map<String, dynamic>> requests, {String status = 'open'}) => {
      'id': 'c1',
      'status': status,
      'startsAt': '2099-01-12T10:00:00.000Z',
      'scheduledClosedAt': '2099-01-05T17:30:00.000',
      'requests': requests,
    };

Future<FakeApiClient> openWaitingPage(WidgetTester tester, Map<String, Object> responses) async {
  final container = await pumpPanel(tester, role: 'admin', responses: responses);
  await tester.tap(find.text('In attesa'));
  await tester.pumpAndSettle();
  return container.read(panelApiClientProvider) as FakeApiClient;
}

void main() {
  setUpAll(initItalianLocale);

  group('richiedenti', () {
    testWidgets('mostra percorso, numero e motivazione', (tester) async {
      await openWaitingPage(tester, {
        '/api/cycles/requests': [
          journeyJson([
            listedUserJson('a', name: 'Anna', reviewed: false, motivation: 'Cerco costanza'),
            listedUserJson('b', name: 'Bruno', motivation: 'Già nel percorso scorso'),
          ]),
        ],
      });

      expect(find.text('Percorso dal 12 gennaio 2099'), findsOneWidget);
      expect(find.text('Richieste aperte fino al 5 gennaio 2099, 17:30'), findsOneWidget);
      expect(find.text('2 richiedenti · 1 da revisionare'), findsOneWidget);
      expect(find.text('Cerco costanza'), findsOneWidget);
      expect(find.text('Da revisionare'), findsOneWidget);
    });

    testWidgets('senza percorsi e senza richieste lo dice', (tester) async {
      await openWaitingPage(tester, {});
      expect(find.text('Nessun percorso in programma'), findsOneWidget);
    });

    testWidgets('un percorso a richieste chiuse senza richiedenti', (tester) async {
      await openWaitingPage(tester, {
        '/api/cycles/requests': [journeyJson([], status: 'closed')],
      });
      expect(find.text('Richieste chiuse'), findsOneWidget);
      expect(find.text('0 richiedenti'), findsOneWidget);
      expect(find.text('Nessuna richiesta'), findsOneWidget);
    });

    testWidgets('un errore si può riprovare', (tester) async {
      var down = true;
      await openWaitingPage(tester, {
        '/api/cycles/requests': (String _, Map<String, dynamic>? __) =>
            down ? ApiException(statusCode: 500, message: 'Errore interno del server') : <Object>[],
      });
      expect(find.text('Errore interno del server'), findsOneWidget);

      down = false;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Nessun percorso in programma'), findsOneWidget);
    });

    testWidgets('dalla scheda si rimuove e l\'elenco si aggiorna', (tester) async {
      var removed = false;
      final api = await openWaitingPage(tester, {
        '/api/cycles/requests': (String _, Map<String, dynamic>? __) => [
              journeyJson(removed ? [] : [listedUserJson('a', name: 'Anna')]),
            ],
        '/api/admin/a': (String _, Map<String, dynamic>? __) {
          removed = true;
          return <String, Object>{};
        },
      });

      await tester.tap(find.byTooltip('Apri la scheda di Anna Bianchi'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Banna'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Rimuovi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog).last, matching: find.widgetWithText(FilledButton, 'Rimuovi')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('DELETE /api/admin/a'));
      expect(find.text('Utente rimosso'), findsOneWidget);
      expect(find.text('Nessuna richiesta'), findsOneWidget);
    });
  });

  group('utenti in attesa', () {
    testWidgets('elenca solo chi è in attesa, con il loro numero', (tester) async {
      final api = await openWaitingPage(tester, {
        '/api/users': usersPageJson([listedUserJson('a', name: 'Anna', reviewed: false)]),
      });
      await tester.tap(find.widgetWithText(Tab, 'Utenti in attesa'));
      await tester.pumpAndSettle();

      expect(api.calls.any((c) => c.startsWith('GET /api/users?') && c.contains('waiting=true')), isTrue);
      expect(find.text('1 utente in attesa'), findsOneWidget);
      expect(find.text('Anna Bianchi'), findsOneWidget);
      expect(find.text('Da revisionare'), findsOneWidget);
    });

    testWidgets('senza utenti lo dice', (tester) async {
      await openWaitingPage(tester, {});
      await tester.tap(find.widgetWithText(Tab, 'Utenti in attesa'));
      await tester.pumpAndSettle();
      expect(find.text('Nessun utente in attesa'), findsOneWidget);
    });

    testWidgets('la revisione dalla scheda aggiorna l\'elenco', (tester) async {
      var reviewed = false;
      await openWaitingPage(tester, {
        '/api/users': (String _, Map<String, dynamic>? __) => usersPageJson([listedUserJson('a', reviewed: reviewed)]),
        '/api/admin/a/review': (String _, Map<String, dynamic>? __) {
          reviewed = true;
          return <String, Object>{};
        },
      });
      await tester.tap(find.widgetWithText(Tab, 'Utenti in attesa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Apri la scheda di Anna Bianchi'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Segna come revisionato'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Segna come revisionato'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();

      expect(find.text('Da revisionare'), findsNothing);
    });
  });
}
