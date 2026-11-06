import 'package:community_app/app.dart';
import 'package:community_app/features/auth/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../panel/fakes.dart';
import 'app_fakes.dart';

const _next = '/api/cycles/next';
const _requests = '/api/cycles/requests';
const _mine = '/api/cycles/requests/mine';
const _askLabel = 'Chiedi di partecipare';
const _cancelLabel = 'Annulla la richiesta';

Map<String, dynamic> nextJson({
  bool open = true,
  bool requested = false,
  bool? canRequest,
  int requesters = 0,
  String startsAt = '2099-01-12T10:00:00.000Z',
}) =>
    {
      'cycle': {'id': 'c1', 'open': open, 'startsAt': startsAt, 'durationDays': 365, 'scheduledClosedAt': null},
      'requesters': requesters,
      'requested': requested,
      'canRequest': canRequest ?? (open && !requested),
    };

const _noJourney = {'cycle': null, 'requesters': 0, 'requested': false, 'canRequest': false};

Map<String, dynamic> memberJson({String? endedAt}) => {
      ...userJson('user'),
      'group': {'id': 'g1', 'startedAt': '2026-01-01T00:00:00.000Z', 'endedAt': endedAt},
    };

Future<FakeHttp> pumpApp(WidgetTester tester, Map<String, Object> routes) async {
  final http = FakeHttp({
    '/api/users/me': (200, userJson('user')),
    '/api/main-channel': (200, {'posts': <Object>[], 'hasMore': false}),
    ...routes,
  });
  final container = ProviderContainer(overrides: [
    httpAdapterProvider.overrideWithValue(http),
    tokenStorageProvider.overrideWithValue(FakeTokenStorage(access: 'a', refresh: 'r')),
    socketServiceProvider.overrideWithValue(FakeSocket()),
    pushServiceProvider.overrideWithValue(FakePush()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const App()));
  await tester.pumpAndSettle();
  return http;
}

bool enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>())).onPressed != null;

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initItalianLocale);

  testWidgets('chi non ha un gruppo vede solo la schermata In attesa e il profilo', (tester) async {
    await pumpApp(tester, {_next: (200, nextJson())});

    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Condivisione'), findsNothing);
    expect(find.text('Profilo'), findsOneWidget);
  });

  testWidgets('chi è in un gruppo attivo non vede la schermata In attesa', (tester) async {
    await pumpApp(tester, {'/api/users/me': (200, memberJson())});

    expect(find.text('In attesa'), findsNothing);
    expect(find.text('Condivisione'), findsOneWidget);
  });

  testWidgets('a gruppo finito si torna alla schermata In attesa', (tester) async {
    await pumpApp(tester, {
      '/api/users/me': (200, memberJson(endedAt: '2026-02-01T00:00:00.000Z')),
      _next: (200, nextJson()),
    });

    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Condivisione'), findsNothing);
  });

  testWidgets('a ciclo aperto mostra data e numero dei richiedenti e permette di chiedere', (tester) async {
    var requested = false;
    final http = await pumpApp(tester, {
      _next: (RequestOptions _) => (200, nextJson(requested: requested, requesters: requested ? 3 : 2)),
      _requests: (RequestOptions _) {
        requested = true;
        return (201, {'id': 'r1'});
      },
    });

    expect(find.text('Sono aperte le richieste per il percorso che inizia il 12 gennaio 2099.'), findsOneWidget);
    expect(find.text('2 persone hanno chiesto di partecipare al prossimo percorso.'), findsOneWidget);

    await tapAndSettle(tester, find.text(_askLabel));

    expect(http.calls(_requests), 1);
    expect(find.text('Hai chiesto di partecipare al percorso che inizia il 12 gennaio 2099.'), findsOneWidget);
    expect(find.text('3 persone hanno chiesto di partecipare al prossimo percorso.'), findsOneWidget);
    expect(find.text(_cancelLabel), findsOneWidget);
    expect(find.text(_askLabel), findsNothing);
  });

  testWidgets('annullare chiede conferma e la richiesta si può rifare', (tester) async {
    var requested = true;
    final http = await pumpApp(tester, {
      _next: (RequestOptions _) => (200, nextJson(requested: requested)),
      _mine: (RequestOptions _) {
        requested = false;
        return (204, null);
      },
    });

    await tapAndSettle(tester, find.text(_cancelLabel));
    expect(find.text('Potrai chiedere di nuovo di partecipare finché le richieste sono aperte.'), findsOneWidget);
    await tapAndSettle(tester, find.text('Indietro'));
    expect(http.calls(_mine), 0);

    await tapAndSettle(tester, find.text(_cancelLabel));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, _cancelLabel));

    expect(http.calls(_mine), 1);
    expect(enabled(tester, _askLabel), isTrue);
  });

  testWidgets('a ciclo chiuso avvisa che annullando non si potrà più chiedere', (tester) async {
    await pumpApp(tester, {_next: (200, nextJson(open: false, requested: true))});

    await tapAndSettle(tester, find.text(_cancelLabel));

    expect(find.text('Le richieste sono chiuse: non potrai più chiedere di partecipare a questo percorso.'), findsOneWidget);
  });

  testWidgets('a ciclo chiuso il pulsante è disattivato, con il messaggio', (tester) async {
    await pumpApp(tester, {_next: (200, nextJson(open: false, requesters: 1))});

    expect(enabled(tester, _askLabel), isFalse);
    expect(find.text('Le richieste di partecipazione sono chiuse. Il prossimo percorso inizia il 12 gennaio 2099.'), findsOneWidget);
    expect(find.text('1 persona ha chiesto di partecipare al prossimo percorso.'), findsOneWidget);
  });

  testWidgets('senza percorsi in programma il pulsante è disattivato e non c\'è il conteggio', (tester) async {
    await pumpApp(tester, {_next: (200, _noJourney)});

    expect(enabled(tester, _askLabel), isFalse);
    expect(find.text('Le richieste di partecipazione sono chiuse.'), findsOneWidget);
    expect(find.textContaining('prossimo percorso.'), findsNothing);
  });

  testWidgets('chi è stato rimosso dal ciclo aperto non può chiedere', (tester) async {
    await pumpApp(tester, {_next: (200, nextJson(canRequest: false))});

    expect(enabled(tester, _askLabel), isFalse);
    expect(find.text('Potrai chiedere di partecipare dal prossimo percorso.'), findsOneWidget);
  });

  testWidgets('un rifiuto mostra il messaggio e aggiorna la schermata', (tester) async {
    var open = true;
    await pumpApp(tester, {
      _next: (RequestOptions _) => (200, nextJson(open: open)),
      _requests: (RequestOptions _) {
        open = false;
        return (409, {'message': 'Le richieste di partecipazione sono chiuse'});
      },
    });

    await tester.tap(find.text(_askLabel));
    await tester.pumpAndSettle();

    expect(find.text('Le richieste di partecipazione sono chiuse'), findsOneWidget);
    expect(enabled(tester, _askLabel), isFalse);
  });

  testWidgets('se il percorso è cominciato nel frattempo l\'app passa al gruppo', (tester) async {
    var inGroup = false;
    await pumpApp(tester, {
      '/api/users/me': (RequestOptions _) => (200, inGroup ? memberJson() : userJson('user')),
      _next: (RequestOptions _) {
        inGroup = true;
        return (403, {'message': 'Partecipi già a un percorso'});
      },
    });

    expect(find.text('In attesa'), findsNothing);
    expect(find.text('Condivisione'), findsOneWidget);
  });

  testWidgets('un errore si può riprovare', (tester) async {
    var down = true;
    await pumpApp(tester, {
      _next: (RequestOptions _) => down ? (500, {'message': 'Errore interno del server'}) : (200, nextJson()),
    });
    expect(find.text('Riprova'), findsOneWidget);

    down = false;
    await tapAndSettle(tester, find.text('Riprova'));

    expect(find.text(_askLabel), findsOneWidget);
  });
}
