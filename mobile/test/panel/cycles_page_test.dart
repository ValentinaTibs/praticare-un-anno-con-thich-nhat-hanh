import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/locale.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';
import 'pump_panel.dart';

Map<String, dynamic> cycleJson({
  String id = 'c1',
  String status = 'open',
  String startsAt = '2099-01-12T00:00:00.000',
  String? closes = '2099-01-05T18:30:00.000',
  String? closedAt,
  int durationDays = 365,
}) =>
    {
      'id': id,
      'status': status,
      'startsAt': startsAt,
      'durationDays': durationDays,
      'scheduledClosedAt': closes,
      'closedAt': closedAt,
    };

Future<FakeApiClient> openCyclesPage(WidgetTester tester, List<Map<String, dynamic>> cycles, {Object? onWrite}) async {
  final container = await pumpPanel(tester, role: 'super_admin', responses: {
    '/api/cycles': cycles,
    '/api/cycles/open': onWrite ?? cycleJson(),
    '/api/cycles/close': cycleJson(status: 'closed'),
    '/api/cycles/c1': onWrite ?? cycleJson(),
  });
  await tester.tap(find.text('Cicli'));
  await tester.pumpAndSettle();
  return container.read(panelApiClientProvider) as FakeApiClient;
}

Future<void> confirmPicker(WidgetTester tester) async {
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initItalianLocale);

  testWidgets('apre un ciclo con chiusura, inizio e durata predefinita', (tester) async {
    final api = await openCyclesPage(tester, []);
    expect(find.text('Nessun ciclo'), findsOneWidget);

    await tester.tap(find.text('Apri un ciclo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scegli data e ora'));
    await tester.pumpAndSettle();
    await confirmPicker(tester); // day
    await confirmPicker(tester); // time
    await tester.tap(find.text('Scegli la data'));
    await tester.pumpAndSettle();
    await confirmPicker(tester);
    await tester.tap(find.text('Apri il ciclo'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /api/cycles/open'));
    final body = api.bodies.last as Map<String, dynamic>;
    final closes = DateTime.parse(body['scheduledClosedAt'] as String).toLocal();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect((closes.day, closes.hour, closes.minute), (tomorrow.day, 23, 59));
    expect(DateTime.parse(body['startDate'] as String).isAfter(closes), isTrue);
    expect(body['durationDays'], 365);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('senza date non chiama il backend e dice cosa manca', (tester) async {
    final api = await openCyclesPage(tester, []);
    await tester.tap(find.text('Apri un ciclo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri il ciclo'));
    await tester.pumpAndSettle();

    expect(find.text('Scegli la data di chiusura delle richieste.'), findsOneWidget);
    expect(api.calls, isNot(contains('POST /api/cycles/open')));
  });

  testWidgets('con un ciclo aperto non se ne può aprire un altro', (tester) async {
    await openCyclesPage(tester, [cycleJson()]);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('Apri un ciclo'), matching: find.bySubtype<ButtonStyleButton>()),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Può esserci un solo ciclo aperto alla volta.'), findsOneWidget);
    expect(find.text('Percorso dal 12 gennaio 2099'), findsOneWidget);
    expect(find.text('Richieste aperte fino al 5 gennaio 2099, 18:30'), findsOneWidget);
  });

  testWidgets('la modifica invia solo ciò che è cambiato', (tester) async {
    final api = await openCyclesPage(tester, [cycleJson()]);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('PATCH /api/cycles/c1'));
    expect(api.bodies.last, {'durationDays': 100});
  });

  testWidgets('senza modifiche non chiama il backend', (tester) async {
    final api = await openCyclesPage(tester, [cycleJson()]);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c.startsWith('PATCH')), isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('un ciclo chiuso resta modificabile e avvisa della riapertura', (tester) async {
    await openCyclesPage(tester, [
      cycleJson(status: 'closed', closedAt: '2098-12-20T10:00:00.000'),
    ]);
    expect(find.text('Richieste chiuse'), findsOneWidget);
    expect(find.text('Richieste chiuse il 20 dicembre 2098, 10:00'), findsOneWidget);
    expect(find.text('Chiudi le richieste'), findsNothing);

    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    expect(find.text('Una nuova data di chiusura riapre le richieste.'), findsOneWidget);
  });

  testWidgets('dopo l\'inizio il ciclo è in sola lettura', (tester) async {
    await openCyclesPage(tester, [
      cycleJson(status: 'closed', startsAt: '2020-01-12T00:00:00.000', closes: '2020-01-05T18:30:00.000'),
    ]);
    expect(find.text('Percorso iniziato'), findsOneWidget);
    expect(find.text('Modifica'), findsNothing);
    expect(find.text('Chiudi le richieste'), findsNothing);
  });

  testWidgets('la chiusura anticipata chiede conferma', (tester) async {
    final api = await openCyclesPage(tester, [cycleJson()]);
    await tester.tap(find.text('Chiudi le richieste'));
    await tester.pumpAndSettle();
    expect(api.calls, isNot(contains('POST /api/cycles/close')));

    await tester.tap(find.widgetWithText(FilledButton, 'Chiudi le richieste'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('POST /api/cycles/close'));
  });

  testWidgets('un errore del backend resta nel modulo', (tester) async {
    await openCyclesPage(tester, [cycleJson()],
        onWrite: ApiException(statusCode: 409, message: 'C\'è già un ciclo aperto'));
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('C\'è già un ciclo aperto'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
