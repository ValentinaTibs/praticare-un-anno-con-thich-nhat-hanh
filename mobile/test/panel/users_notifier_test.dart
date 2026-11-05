import 'dart:async';

import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/models/user.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:community_app/panel/users/group.dart';
import 'package:community_app/panel/users/user_actions.dart';
import 'package:community_app/panel/users/users_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

late ProviderContainer container;

UsersState get usersState => container.read(usersProvider);

/// The users list over [api], once its first load is over. Groups are loaded
/// too, as the page does.
Future<UsersNotifier> loaded(FakeApiClient api) async {
  api.responses.putIfAbsent('/api/groups', () => <Object>[]);
  container = ProviderContainer(overrides: [panelApiClientProvider.overrideWithValue(api)]);
  addTearDown(container.dispose);
  container.listen(usersProvider, (_, __) {});
  container.listen(groupsProvider, (_, __) {});
  while (usersState.loading) {
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(usersProvider.notifier);
}

void main() {
  test('il primo caricamento chiede la prima pagina di tutti gli utenti', () async {
    final api = FakeApiClient({'/api/users': usersPageJson([listedUserJson('u1'), listedUserJson('u2')])});
    await loaded(api);

    expect(api.calls, contains('GET /api/users?page=1&limit=50'));
    expect(usersState.users.map((u) => u.id), ['u1', 'u2']);
    expect(usersState.total, 2);
    expect(usersState.error, isNull);
  });

  test('ogni filtro rifà la richiesta con la query giusta', () async {
    final api = FakeApiClient({'/api/users': usersPageJson([])});
    final notifier = await loaded(api);

    await notifier.setOnlyToReview(true);
    expect(api.calls.last, 'GET /api/users?page=1&limit=50&reviewed=false');

    await notifier.setGroup('g1');
    expect(api.calls.last, 'GET /api/users?page=1&limit=50&groupId=g1&reviewed=false');

    await notifier.setStatus('suspended');
    await notifier.setSearch('  anna ');
    expect(api.calls.last, 'GET /api/users?page=1&limit=50&q=anna&groupId=g1&status=suspended&reviewed=false');

    await notifier.setGroup(null);
    expect(api.calls.last, 'GET /api/users?page=1&limit=50&q=anna&status=suspended&reviewed=false');
  });

  test('aprire un gruppo mostra tutti i suoi membri, senza gli altri filtri', () async {
    final api = FakeApiClient({'/api/users': usersPageJson([])});
    final notifier = await loaded(api);
    await notifier.setOnlyToReview(true);
    await notifier.setSearch('anna');

    await notifier.showGroup('g1');

    expect(api.calls.last, 'GET /api/users?page=1&limit=50&groupId=g1');
  });

  test('cambia pagina e conta le pagine da 50', () async {
    final api = FakeApiClient({
      '/api/users': (String _, Map<String, dynamic>? q) =>
          usersPageJson([listedUserJson('u${q!['page']}')], total: 120, page: int.parse(q['page'] as String)),
    });
    final notifier = await loaded(api);
    expect(usersState.pageCount, 3);

    await notifier.goToPage(2);

    expect(api.calls.last, 'GET /api/users?page=2&limit=50');
    expect(usersState.page, 2);
    expect(usersState.users.single.id, 'u2');
  });

  test('vale solo la risposta all\'ultima richiesta', () async {
    final slowAnswer = Completer<Object>();
    final api = FakeApiClient({'/api/users': usersPageJson([])});
    final notifier = await loaded(api);
    // The first request answers after the second one.
    api.responses['/api/users'] = (String _, Map<String, dynamic>? q) =>
        q!['q'] == null ? slowAnswer.future : usersPageJson([listedUserJson('cercato')]);

    final slow = notifier.setStatus('active');
    await notifier.setSearch('anna');
    slowAnswer.complete(usersPageJson([listedUserJson('vecchio')]));
    await slow;

    expect(usersState.users.single.id, 'cercato');
    expect(usersState.filters.search, 'anna');
  });

  test('un\'azione chiama il backend e poi ricarica elenco e gruppi', () async {
    final api = FakeApiClient({
      '/api/users': usersPageJson([listedUserJson('u1')]),
      '/api/admin/u1/suspend': {'id': 'u1', 'status': 'suspended'},
      '/api/admin/u1': '',
    });
    final notifier = await loaded(api);
    final user = usersState.users.single;
    api.calls.clear();

    await notifier.act(UserAction.suspend, user);
    await notifier.act(UserAction.remove, user);
    await container.read(groupsProvider.future);

    expect(api.calls.where((c) => !c.startsWith('GET /api/groups')).toList(), [
      'PATCH /api/admin/u1/suspend',
      'GET /api/users?page=1&limit=50',
      'DELETE /api/admin/u1',
      'GET /api/users?page=1&limit=50',
    ]);
    expect(api.calls, contains('GET /api/groups'), reason: 'i conteggi dei membri cambiano');
  });

  test('un\'azione rifiutata dal backend lancia l\'errore e ricarica comunque l\'elenco', () async {
    final api = FakeApiClient({
      '/api/users': usersPageJson([listedUserJson('u1')]),
      '/api/admin/u1/ban': ApiException(statusCode: 404, message: 'Elemento non trovato'),
    });
    final notifier = await loaded(api);

    await expectLater(
      notifier.act(UserAction.ban, usersState.users.single),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Elemento non trovato')),
    );
    expect(api.calls.last, 'GET /api/users?page=1&limit=50');
  });

  test('un errore di caricamento finisce nello stato con il suo messaggio', () async {
    final api = FakeApiClient({'/api/users': ApiException(statusCode: 400, message: 'Dati non validi')});
    final notifier = await loaded(api);

    expect(usersState.error, 'Dati non validi');
    expect(usersState.users, isEmpty);

    api.responses['/api/users'] = usersPageJson([listedUserJson('u1')]);
    await notifier.retry();
    expect(usersState.error, isNull);
    expect(usersState.users, hasLength(1));
  });

  group('azioni disponibili', () {
    User user(String id, {String role = 'user', String status = 'active', bool reviewed = true}) =>
        User.fromJson(listedUserJson(id, role: role, status: status, reviewed: reviewed));
    final admin = user('a1', role: 'admin');
    final superAdmin = user('s1', role: 'super_admin');

    test('dipendono dallo stato dell\'utente', () {
      expect(actionsFor(admin, user('u1')), [UserAction.suspend, UserAction.ban, UserAction.remove]);
      expect(actionsFor(admin, user('u1', status: 'suspended')), [UserAction.reactivate, UserAction.ban, UserAction.remove]);
      expect(actionsFor(admin, user('u1', status: 'banned')), isEmpty);
      expect(actionsFor(superAdmin, user('u1', status: 'banned')), [UserAction.unban]);
      expect(actionsFor(admin, user('u1', reviewed: false)).first, UserAction.review);
    });

    test('un admin non agisce su sé stesso, su un altro admin né sul Super Admin', () {
      expect(actionsFor(admin, admin), isEmpty);
      expect(restrictionFor(admin, admin), 'Questo è il tuo account.');
      expect(actionsFor(admin, user('a2', role: 'admin')), isEmpty);
      expect(restrictionFor(admin, user('a2', role: 'admin')), 'Solo il Super Admin può intervenire su un admin.');
      expect(actionsFor(admin, superAdmin), isEmpty);
      expect(restrictionFor(admin, superAdmin), isNotNull);
      expect(actionsFor(admin, user('a2', role: 'admin', reviewed: false)), [UserAction.review]);
    });

    test('il Super Admin agisce sugli admin ma non su sé stesso', () {
      expect(actionsFor(superAdmin, admin), [UserAction.suspend, UserAction.ban, UserAction.remove]);
      expect(restrictionFor(superAdmin, admin), isNull);
      expect(actionsFor(superAdmin, superAdmin), isEmpty);
      expect(restrictionFor(superAdmin, superAdmin), 'Questo è il tuo account.');
    });
  });
}
