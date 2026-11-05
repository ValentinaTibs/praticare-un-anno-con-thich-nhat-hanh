import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/auth/auth_errors.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

/// Panel session over the given fakes, once the restore started by the
/// constructor is over. Read the state with `container.read(panelAuthProvider)`.
late ProviderContainer container;

Future<PanelAuthNotifier> settled(FakeApiClient api, FakeTokenStorage storage, FakePanelFirebase firebase) async {
  container = ProviderContainer(overrides: [
    panelApiClientProvider.overrideWithValue(api),
    panelTokenStorageProvider.overrideWithValue(storage),
    panelFirebaseProvider.overrideWithValue(firebase),
  ]);
  addTearDown(container.dispose);
  while (container.read(panelAuthProvider).status == PanelAuthStatus.loading) {
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(panelAuthProvider.notifier);
}

PanelAuthState get authState => container.read(panelAuthProvider);

void main() {
  group('accesso con email e password', () {
    for (final role in ['admin', 'super_admin']) {
      test('$role entra nel pannello', () async {
        final api = FakeApiClient({'/api/auth/verify-firebase': sessionJson(role)});
        final storage = FakeTokenStorage();
        final firebase = FakePanelFirebase();
        final auth = await settled(api, storage, firebase);

        await auth.signIn('a@b.it', 'password');

        expect(authState.status, PanelAuthStatus.signedIn);
        expect(authState.user?.role, role);
        expect(storage.access, 'access-$role');
        expect(firebase.signedOut, isTrue, reason: 'il pannello tiene solo la sessione del backend');
      });
    }

    test('un utente semplice viene respinto e la sua sessione revocata', () async {
      final api = FakeApiClient({
        '/api/auth/verify-firebase': sessionJson('user'),
        '/api/auth/logout': {'message': 'Disconnesso'},
      });
      final storage = FakeTokenStorage();
      final auth = await settled(api, storage, FakePanelFirebase());

      await expectLater(
        auth.signIn('a@b.it', 'password'),
        throwsA(isA<AuthFlowException>().having((e) => e.message, 'message', notAdminMessage)),
      );

      expect(authState.status, PanelAuthStatus.signedOut);
      expect(storage.access, isNull);
      expect(api.calls, contains('POST /api/auth/logout'));
    });

    test('un\'email senza account nel backend viene respinta', () async {
      final api = FakeApiClient({
        '/api/auth/verify-firebase': {'status': 'register', 'email': 'a@b.it'},
      });
      final storage = FakeTokenStorage();
      final auth = await settled(api, storage, FakePanelFirebase());

      await expectLater(auth.signIn('a@b.it', 'password'), throwsA(isA<AuthFlowException>()));
      expect(authState.status, PanelAuthStatus.signedOut);
      expect(storage.access, isNull);
    });

    test('con l\'email non verificata chiede di confermarla', () async {
      final api = FakeApiClient({});
      final firebase = FakePanelFirebase(idToken: null);
      final auth = await settled(api, FakeTokenStorage(), firebase);

      await expectLater(
        auth.signIn('a@b.it', 'password'),
        throwsA(isA<AuthFlowException>().having((e) => e.message, 'message', emailNotVerifiedMessage)),
      );
      expect(api.calls, isEmpty);
      expect(firebase.signedOut, isTrue);
    });

    test('mostra il messaggio del backend per un account sospeso', () async {
      final api = FakeApiClient({
        '/api/auth/verify-firebase': ApiException(statusCode: 403, message: 'Account sospeso.'),
      });
      final auth = await settled(api, FakeTokenStorage(), FakePanelFirebase());

      Object? error;
      try {
        await auth.signIn('a@b.it', 'password');
      } catch (e) {
        error = e;
      }
      expect(authErrorMessage(error!), 'Account sospeso.');
    });
  });

  group('ripristino della sessione', () {
    test('senza token mostra l\'accesso', () async {
      await settled(FakeApiClient({}), FakeTokenStorage(), FakePanelFirebase());
      expect(authState.status, PanelAuthStatus.signedOut);
      expect(authState.message, isNull);
    });

    test('un admin con token valido resta dentro', () async {
      final api = FakeApiClient({'/api/users/me': userJson('admin')});
      final storage = FakeTokenStorage(access: 'a', refresh: 'r');
      await settled(api, storage, FakePanelFirebase());
      expect(authState.status, PanelAuthStatus.signedIn);
    });

    test('un admin declassato viene fatto uscire con un messaggio', () async {
      final api = FakeApiClient({
        '/api/users/me': userJson('user'),
        '/api/auth/logout': {'message': 'Disconnesso'},
      });
      final storage = FakeTokenStorage(access: 'a', refresh: 'r');
      await settled(api, storage, FakePanelFirebase());

      expect(authState.status, PanelAuthStatus.signedOut);
      expect(authState.message, notAdminMessage);
      expect(storage.access, isNull);
      expect(api.calls, contains('POST /api/auth/logout'));
    });

    test('con un token scaduto e non rinnovabile mostra l\'accesso', () async {
      final api = FakeApiClient({'/api/users/me': ApiException(statusCode: 401, message: 'Non autorizzato')});
      final storage = FakeTokenStorage(access: 'a', refresh: 'r');
      await settled(api, storage, FakePanelFirebase());

      expect(authState.status, PanelAuthStatus.signedOut);
      expect(storage.access, isNull);
    });
  });

  test('l\'uscita revoca il token e svuota la sessione', () async {
    final api = FakeApiClient({
      '/api/users/me': userJson('admin'),
      '/api/auth/logout': {'message': 'Disconnesso'},
    });
    final storage = FakeTokenStorage(access: 'a', refresh: 'r');
    final auth = await settled(api, storage, FakePanelFirebase());

    await auth.logout();

    expect(authState.status, PanelAuthStatus.signedOut);
    expect(storage.access, isNull);
    expect(api.calls, contains('POST /api/auth/logout'));
  });
}
