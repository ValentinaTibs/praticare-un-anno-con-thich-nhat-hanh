import 'package:community_app/core/auth/auth_errors.dart';
import 'package:community_app/core/locale.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:community_app/panel/panel_app.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

const _sessionRefused = (401, {'message': 'Sessione non valida o scaduta'});
const _unauthorized = (401, {'message': 'Non autorizzato'});

Never _serverDown(RequestOptions o) => throw DioException.connectionError(requestOptions: o, reason: 'giù');

/// The panel over the real ApiClient, with only the HTTP transport replaced.
Future<void> pumpOver(WidgetTester tester, FakeHttp http, FakeTokenStorage storage) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    panelHttpAdapterProvider.overrideWithValue(http),
    panelTokenStorageProvider.overrideWithValue(storage),
    panelFirebaseProvider.overrideWithValue(FakePanelFirebase()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const PanelApp()));
  await tester.pumpAndSettle();
}

/// A backend with a signed-in admin and one plain user.
FakeHttp adminBackend() => FakeHttp({
      '/api/users/me': (200, userJson('admin')),
      '/api/groups': (200, <Object>[]),
      '/api/users': (200, usersPageJson([listedUserJson('u1')])),
      '/api/users/u1': (200, listedUserJson('u1')),
      '/api/auth/logout': (200, {'message': 'Disconnesso'}),
    });

Future<void> openUsersTab(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(Tab, 'Utenti'));
  await tester.pumpAndSettle();
}

/// Makes the users list ask the backend again.
Future<void> reloadUsers(WidgetTester tester) async {
  await tester.tap(find.text('Solo da revisionare'));
  await tester.pumpAndSettle();
}

Future<void> suspendFromCard(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Apri la scheda di Anna Bianchi'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(OutlinedButton, 'Sospendi'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Sospendi'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initItalianLocale);

  late FakeTokenStorage storage;

  setUp(() => storage = FakeTokenStorage(access: 'old-access', refresh: 'old-refresh'));

  void expectLoginPage(String? message) {
    expect(find.text('Accedi'), findsOneWidget);
    expect(find.text('Utenti e gruppi'), findsNothing);
    if (message != null) expect(find.text(message), findsOneWidget);
    expect(storage.access, isNull);
    expect(storage.refresh, isNull);
  }

  testWidgets('all\'avvio con il refresh token scaduto torna all\'accesso, senza restare appeso', (tester) async {
    final http = adminBackend();
    http.routes
      ..['/api/users/me'] = _unauthorized
      ..['/api/auth/refresh'] = _sessionRefused;

    await pumpOver(tester, http, storage);

    expectLoginPage(sessionExpiredMessage);
    expect(http.calls('/api/auth/refresh'), 1);
  });

  testWidgets('a sessione scaduta col pannello aperto torna all\'accesso con il messaggio', (tester) async {
    final http = adminBackend();
    await pumpOver(tester, http, storage);
    await openUsersTab(tester);

    http.routes
      ..['/api/users'] = _unauthorized
      ..['/api/auth/refresh'] = _sessionRefused;
    await reloadUsers(tester);

    expectLoginPage(sessionExpiredMessage);
    expect(http.calls('/api/auth/refresh'), 1);
  });

  testWidgets('anche con una scheda aperta, e senza altri avvisi', (tester) async {
    final http = adminBackend();
    await pumpOver(tester, http, storage);
    await openUsersTab(tester);

    http.routes
      ..['/api/admin/u1/suspend'] = _unauthorized
      ..['/api/users'] = _unauthorized
      ..['/api/users/u1'] = _unauthorized
      ..['/api/auth/refresh'] = _sessionRefused;
    await suspendFromCard(tester);

    expectLoginPage(sessionExpiredMessage);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('con il token d\'accesso scaduto ma il refresh valido il pannello resta aperto', (tester) async {
    final http = adminBackend();
    await pumpOver(tester, http, storage);
    await openUsersTab(tester);

    http.routes
      ..['/api/users'] = ((RequestOptions request) => request.headers['Authorization'] == 'Bearer new-access'
          ? (200, usersPageJson([listedUserJson('u2', name: 'Marco')]))
          : _unauthorized)
      ..['/api/auth/refresh'] = (200, {'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
    await reloadUsers(tester);

    expect(find.text('Marco Bianchi'), findsOneWidget);
    expect(find.text('Accedi'), findsNothing);
    expect(storage.refresh, 'new-refresh');
  });

  testWidgets('«Esci» a sessione scaduta non si blocca', (tester) async {
    final http = adminBackend();
    await pumpOver(tester, http, storage);

    http.routes
      ..['/api/auth/logout'] = _unauthorized
      ..['/api/auth/refresh'] = _sessionRefused;
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();

    expectLoginPage(null);
    expect(find.text(sessionExpiredMessage), findsNothing, reason: 'l\'uscita è voluta');
  });

  testWidgets('un admin sospeso col pannello aperto torna all\'accesso con il motivo', (tester) async {
    const suspended = (403, {'message': 'Account sospeso. Contatta un amministratore per riattivarlo.'});
    final http = adminBackend();
    await pumpOver(tester, http, storage);
    await openUsersTab(tester);

    http.routes
      ..['/api/users'] = suspended
      ..['/api/users/me'] = suspended;
    await reloadUsers(tester);

    expectLoginPage('Account sospeso. Contatta un amministratore per riattivarlo.');
    expect(http.calls('/api/auth/logout'), 1, reason: 'il refresh token va revocato');
  });

  testWidgets('un admin declassato col pannello aperto esce e la sessione è revocata', (tester) async {
    final http = adminBackend();
    await pumpOver(tester, http, storage);
    await openUsersTab(tester);

    http.routes
      ..['/api/users'] = (403, {'message': 'Permessi insufficienti'})
      ..['/api/users/me'] = (200, userJson('user'));
    await reloadUsers(tester);

    expectLoginPage(notAdminMessage);
    expect(http.calls('/api/auth/logout'), 1);
  });

  testWidgets('un admin sospeso prima dell\'avvio vede il motivo nella pagina di accesso', (tester) async {
    final http = adminBackend();
    http.routes['/api/users/me'] = (403, {'message': 'Account sospeso. Contatta un amministratore per riattivarlo.'});

    await pumpOver(tester, http, storage);

    expectLoginPage('Account sospeso. Contatta un amministratore per riattivarlo.');
    expect(http.calls('/api/auth/logout'), 1, reason: 'il refresh token va revocato');
  });

  testWidgets('un 403 sulla singola azione lascia dentro e mostra il messaggio nella scheda', (tester) async {
    final http = adminBackend();
    await pumpOver(tester, http, storage);
    await openUsersTab(tester);

    http.routes['/api/admin/u1/suspend'] = (403, {'message': 'Non puoi eseguire questa azione su questo utente'});
    await suspendFromCard(tester);

    expect(find.text('Accedi'), findsNothing);
    expect(find.text('Non puoi eseguire questa azione su questo utente'), findsOneWidget);
    expect(storage.access, 'old-access');
  });

  group('all\'avvio il server non risponde', () {
    void expectSessionKept() {
      expect(find.text(serverUnavailableMessage), findsOneWidget);
      expect(find.text('Riprova'), findsOneWidget);
      expect(find.text('Accedi'), findsNothing);
      expect(storage.access, 'old-access');
      expect(storage.refresh, 'old-refresh');
    }

    for (final (reason, routes) in <(String, Map<String, Object>)>[
      ('server irraggiungibile', {'/api/users/me': _serverDown}),
      ('errore del server', {'/api/users/me': (500, {'message': 'Errore interno del server'})}),
      ('troppe richieste', {'/api/users/me': (429, {'message': 'Too many requests'})}),
      ('token d\'accesso scaduto e refresh che non arriva', {'/api/users/me': _unauthorized, '/api/auth/refresh': _serverDown}),
    ]) {
      testWidgets('$reason: la sessione resta e si può riprovare', (tester) async {
        final http = adminBackend();
        http.routes.addAll(routes);

        await pumpOver(tester, http, storage);

        expectSessionKept();
      });
    }

    testWidgets('quando il server torna, «Riprova» riapre il pannello senza un nuovo accesso', (tester) async {
      final http = adminBackend();
      final me = http.routes['/api/users/me']!;
      http.routes['/api/users/me'] = _serverDown;
      await pumpOver(tester, http, storage);
      expectSessionKept();

      http.routes['/api/users/me'] = me;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();

      expect(find.text('Utenti e gruppi'), findsWidgets);
      expect(find.text('Accedi'), findsNothing);
    });

    testWidgets('se il server è ancora giù, «Riprova» resta sulla stessa schermata', (tester) async {
      final http = adminBackend();
      http.routes['/api/users/me'] = _serverDown;
      await pumpOver(tester, http, storage);

      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();

      expectSessionKept();
      expect(http.calls('/api/users/me'), 2);
    });

    testWidgets('«Esci» porta all\'accesso e cancella la sessione', (tester) async {
      final http = adminBackend();
      http.routes['/api/users/me'] = _serverDown;
      await pumpOver(tester, http, storage);

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();

      expectLoginPage(null);
    });
  });
}
