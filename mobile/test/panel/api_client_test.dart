import 'dart:async';

import 'package:community_app/core/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

const _refresh = '/api/auth/refresh';
const _newTokens = {'accessToken': 'new-access', 'refreshToken': 'new-refresh'};

/// Answers 200 only to the new access token, as the backend does once the old one expired.
FakeHttpAnswer _onlyNewToken(RequestOptions request) =>
    request.headers['Authorization'] == 'Bearer new-access' ? (200, {'ok': true}) : (401, {'message': 'Non autorizzato'});

void main() {
  late FakeTokenStorage storage;
  late int sessionsExpired;
  late int forbidden;

  ApiClient clientOver(FakeHttp http) => ApiClient(
        storage,
        adapter: http,
        onSessionExpired: () => sessionsExpired++,
        onForbidden: () => forbidden++,
      );

  setUp(() {
    storage = FakeTokenStorage(access: 'old-access', refresh: 'old-refresh');
    sessionsExpired = 0;
    forbidden = 0;
  });

  group('refresh token rifiutato', () {
    test('la richiesta finisce con il 401, senza ripetere il refresh, e la sessione è persa', () async {
      final http = FakeHttp({
        '/x': (401, {'message': 'Non autorizzato'}),
        _refresh: (401, {'message': 'Sessione non valida o scaduta'}),
      });

      await expectLater(
        clientOver(http).get('/x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(http.calls(_refresh), 1);
      expect(storage.access, isNull);
      expect(storage.refresh, isNull);
      expect(sessionsExpired, 1);
    });

    test('più richieste insieme perdono la sessione una volta sola', () async {
      final http = FakeHttp({
        '/a': (401, {'message': 'Non autorizzato'}),
        '/b': (401, {'message': 'Non autorizzato'}),
        _refresh: (401, {'message': 'Sessione non valida o scaduta'}),
      });
      final api = clientOver(http);

      await Future.wait([
        expectLater(api.get('/a'), throwsA(isA<ApiException>())),
        expectLater(api.get('/b'), throwsA(isA<ApiException>())),
      ]);

      expect(http.calls(_refresh), 1);
      expect(sessionsExpired, 1);
    });

    test('senza avviso funziona lo stesso, come nell\'app', () async {
      final http = FakeHttp({
        '/x': (401, {'message': 'Non autorizzato'}),
        _refresh: (401, {'message': 'Sessione non valida o scaduta'}),
      });

      await expectLater(ApiClient(storage, adapter: http).get('/x'), throwsA(isA<ApiException>()));

      expect(storage.access, isNull);
    });
  });

  group('refresh riuscito', () {
    test('ripete la richiesta con il nuovo token e salva i token ruotati', () async {
      final http = FakeHttp({'/x': _onlyNewToken, _refresh: (200, _newTokens)});

      expect(await clientOver(http).get('/x'), {'ok': true});

      expect(http.calls('/x'), 2);
      expect(storage.access, 'new-access');
      expect(storage.refresh, 'new-refresh');
      expect(sessionsExpired, 0);
    });

    test('richieste scadute insieme condividono un solo refresh', () async {
      // As the backend: the first use of the refresh token deletes it.
      var used = false;
      FakeHttpAnswer rotate(RequestOptions _) {
        if (used) return (401, {'message': 'Sessione non valida o scaduta'});
        used = true;
        return (200, _newTokens);
      }

      final http = FakeHttp({'/a': _onlyNewToken, '/b': _onlyNewToken, _refresh: rotate});
      final api = clientOver(http);

      expect(await Future.wait([api.get('/a'), api.get('/b')]), [
        {'ok': true},
        {'ok': true},
      ]);

      expect(http.calls(_refresh), 1);
      expect(storage.access, 'new-access', reason: 'il secondo refresh cancellerebbe i token nuovi');
      expect(sessionsExpired, 0);
    });

    test('una risposta 401 arrivata dopo il refresh usa i token già nuovi', () async {
      final slow = Completer<FakeHttpAnswer>();
      final http = FakeHttp({
        '/slow': (RequestOptions request) => request.headers['Authorization'] == 'Bearer new-access'
            ? (200, {'ok': true}) as FakeHttpAnswer
            : slow.future,
        '/fast': _onlyNewToken,
        _refresh: (200, _newTokens),
      });
      final api = clientOver(http);

      final late401 = api.get('/slow');
      await api.get('/fast');
      slow.complete((401, {'message': 'Non autorizzato'}));

      expect(await late401, {'ok': true});
      expect(http.calls(_refresh), 1);
    });

    test('vale la risposta alla richiesta ripetuta, non il primo 401', () async {
      final http = FakeHttp({
        '/x': (RequestOptions request) => request.headers['Authorization'] == 'Bearer new-access'
            ? (409, {'message': 'Solo un utente attivo può essere sospeso'})
            : (401, {'message': 'Non autorizzato'}),
        _refresh: (200, _newTokens),
      });

      await expectLater(
        clientOver(http).patch('/x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Solo un utente attivo può essere sospeso')),
      );
    });

    test('un 401 anche dopo il refresh termina senza un altro refresh', () async {
      final http = FakeHttp({
        '/x': (401, {'message': 'Utente non trovato'}),
        _refresh: (200, _newTokens),
      });

      await expectLater(clientOver(http).get('/x'), throwsA(isA<ApiException>()));

      expect(http.calls('/x'), 2);
      expect(http.calls(_refresh), 1);
    });
  });

  group('refresh non riuscito per altri motivi', () {
    for (final (reason, answer, status) in <(String, Object, int)>[
      ('server irraggiungibile', (RequestOptions o) => throw DioException.connectionError(requestOptions: o, reason: 'giù'), 0),
      ('errore del server', (500, {'message': 'Errore interno del server'}), 500),
      ('troppe richieste', (429, {'message': 'Too many requests'}), 429),
    ]) {
      test('$reason: la sessione resta e l\'errore è quello vero, non il 401', () async {
        final http = FakeHttp({
          '/x': (401, {'message': 'Non autorizzato'}),
          _refresh: answer,
        });

        await expectLater(
          clientOver(http).get('/x'),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', status)),
        );

        expect(storage.access, 'old-access');
        expect(storage.refresh, 'old-refresh');
        expect(sessionsExpired, 0);
      });
    }
  });

  test('senza refresh token un 401 passa e basta', () async {
    storage = FakeTokenStorage();
    final http = FakeHttp({
      '/x': (401, {'message': 'Credenziali non valide'}),
    });

    await expectLater(
      clientOver(http).post('/x'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Credenziali non valide')),
    );

    expect(http.calls(_refresh), 0);
    expect(sessionsExpired, 0);
  });

  test('un 403 lo avvisa senza toccare la sessione', () async {
    final http = FakeHttp({
      '/x': (403, {'message': 'Permessi insufficienti'}),
    });

    await expectLater(clientOver(http).get('/x'), throwsA(isA<ApiException>()));

    expect(forbidden, 1);
    expect(sessionsExpired, 0);
    expect(storage.access, 'old-access');
  });
}
