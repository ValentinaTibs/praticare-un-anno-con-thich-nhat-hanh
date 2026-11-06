import 'package:community_app/app.dart';
import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/features/auth/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../panel/fakes.dart';
import 'app_fakes.dart';

const _refresh = '/api/auth/refresh';
const _logout = '/api/auth/logout';
const _me = '/api/users/me';
const _sessionRefused = (401, {'message': 'Sessione non valida o scaduta'});
const _unauthorized = (401, {'message': 'Non autorizzato'});
const _suspended = (403, {'message': 'Account sospeso. Contatta un amministratore per riattivarlo.'});

Never _serverDown(RequestOptions o) => throw DioException.connectionError(requestOptions: o, reason: 'giù');

void main() {
  setUpAll(initItalianLocale);

  late FakeTokenStorage storage;
  late FakeSocket socket;
  late FakePush push;

  setUp(() {
    storage = FakeTokenStorage(access: 'old-access', refresh: 'old-refresh');
    socket = FakeSocket();
    push = FakePush();
  });

  /// A backend with a signed-in user.
  FakeHttp backend([Map<String, Object> routes = const {}]) => FakeHttp({
        _me: (200, userJson('user')),
        _logout: (200, {'message': 'Disconnesso'}),
        ...routes,
      });

  ProviderContainer containerOver(FakeHttp http) {
    final container = ProviderContainer(overrides: [
      httpAdapterProvider.overrideWithValue(http),
      tokenStorageProvider.overrideWithValue(storage),
      socketServiceProvider.overrideWithValue(socket),
      pushServiceProvider.overrideWithValue(push),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// The app's session once the restore started at launch is over.
  Future<ProviderContainer> started(FakeHttp http) async {
    final container = containerOver(http);
    while (container.read(authProvider).status == AuthStatus.loading) {
      await Future<void>.delayed(Duration.zero);
    }
    return container;
  }

  void expectSignedOut(ProviderContainer container, String? error) {
    expect(container.read(authProvider).status, AuthStatus.unauthenticated);
    expect(container.read(authProvider).error, error);
    expect(storage.access, isNull);
    expect(storage.refresh, isNull);
  }

  group('sessione persa', () {
    test('col refresh token rifiutato a app aperta torna all\'accesso con il messaggio', () async {
      final http = backend({'/x': _unauthorized, _refresh: _sessionRefused});
      final container = await started(http);
      expect(container.read(authProvider).status, AuthStatus.authenticated);

      await expectLater(container.read(apiClientProvider).get('/x'), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);

      expectSignedOut(container, sessionExpiredMessage);
      expect(socket.disconnected, 1);
    });

    test('all\'avvio con il refresh token rifiutato mostra l\'accesso con il messaggio', () async {
      final container = await started(backend({_me: _unauthorized, _refresh: _sessionRefused}));

      expectSignedOut(container, sessionExpiredMessage);
      expect(socket.connected, isEmpty);
    });

    test('un utente sospeso prima dell\'avvio vede il motivo, e il suo token è revocato', () async {
      final http = backend({_me: _suspended});
      final container = await started(http);

      expectSignedOut(container, 'Account sospeso. Contatta un amministratore per riattivarlo.');
      expect(http.calls(_logout), 1);
    });

    testWidgets('la schermata di accesso mostra il messaggio', (tester) async {
      final container = containerOver(backend({_me: _unauthorized, _refresh: _sessionRefused}));

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const App()));
      await tester.pumpAndSettle();

      expect(find.text('Benvenuto'), findsOneWidget);
      expect(find.text(sessionExpiredMessage), findsOneWidget);
    });
  });

  group('all\'avvio il server non risponde', () {
    void expectSessionKept(ProviderContainer container) {
      expect(container.read(authProvider).status, AuthStatus.unavailable);
      expect(storage.access, 'old-access');
      expect(storage.refresh, 'old-refresh');
    }

    for (final (reason, routes) in <(String, Map<String, Object>)>[
      ('server irraggiungibile', {_me: _serverDown}),
      ('errore del server', {_me: (500, {'message': 'Errore interno del server'})}),
      ('troppe richieste', {_me: (429, {'message': 'Too many requests'})}),
      ('token d\'accesso scaduto e refresh che non arriva', {_me: _unauthorized, _refresh: _serverDown}),
    ]) {
      test('$reason: la sessione resta', () async {
        expectSessionKept(await started(backend(routes)));
      });
    }

    test('quando il server torna, riprovare riapre la sessione senza un nuovo accesso', () async {
      final http = backend({_me: _serverDown});
      final container = await started(http);
      expectSessionKept(container);

      http.routes[_me] = (200, userJson('user'));
      await container.read(authProvider.notifier).retry();

      expect(container.read(authProvider).status, AuthStatus.authenticated);
      expect(socket.connected, ['old-access']);
    });

    testWidgets('mostra «Riprova» e «Esci», che porta all\'accesso e cancella la sessione', (tester) async {
      final container = containerOver(backend({_me: _serverDown}));

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const App()));
      await tester.pumpAndSettle();

      expect(find.text(serverUnavailableMessage), findsOneWidget);
      expect(find.text('Riprova'), findsOneWidget);
      expect(find.text('Benvenuto'), findsNothing);

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();

      expect(find.text('Benvenuto'), findsOneWidget);
      expect(storage.access, isNull);
    });
  });

  group('avvio con sessione valida', () {
    test('il socket usa il token rinnovato, non quello scaduto', () async {
      final container = await started(backend({
        _me: (RequestOptions r) =>
            r.headers['Authorization'] == 'Bearer new-access' ? (200, userJson('user')) : _unauthorized,
        _refresh: (200, {'accessToken': 'new-access', 'refreshToken': 'new-refresh'}),
      }));

      expect(container.read(authProvider).status, AuthStatus.authenticated);
      expect(socket.connected, ['new-access']);
    });

    test('un problema con le notifiche non chiude la sessione', () async {
      push.onInit = () async => throw StateError('notifiche non disponibili');

      final container = await started(backend());

      expect(container.read(authProvider).status, AuthStatus.authenticated);
      expect(storage.access, 'old-access');
    });
  });

  group('uscita', () {
    test('revoca il refresh token rinnovato durante la rimozione del dispositivo', () async {
      final http = backend();
      final container = await started(http);
      push.onUnregister = () => storage.saveTokens(access: 'new-access', refresh: 'new-refresh');

      await container.read(authProvider.notifier).logout();

      final logout = http.requests.singleWhere((r) => r.path == _logout);
      expect((logout.data as Map)['refreshToken'], 'new-refresh');
      expectSignedOut(container, null);
    });

    test('revoca il refresh token anche se la rimozione del dispositivo fallisce', () async {
      final http = backend();
      final container = await started(http);
      push.onUnregister = () async => throw ApiException(statusCode: 0, message: 'giù');

      await container.read(authProvider.notifier).logout();

      expect(http.calls(_logout), 1);
      expectSignedOut(container, null);
    });
  });
}
