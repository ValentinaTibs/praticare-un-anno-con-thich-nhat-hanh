import 'package:community_app/app.dart';
import 'package:community_app/features/auth/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../panel/fakes.dart';
import 'app_fakes.dart';

const _posts = '/api/main-channel/posts';

final _member = {
  ...userJson('user'),
  'group': {'id': 'g1', 'startedAt': '2026-01-01T00:00:00.000Z', 'endedAt': null},
};

Map<String, dynamic> postJson(String id, String content) => {
      'id': id,
      'author': null,
      'content': content,
      'publishedAt': '2099-01-01T07:00:00.000Z',
      'createdAt': '2099-01-01T07:00:00.000Z',
    };

void main() {
  setUpAll(initItalianLocale);

  testWidgets('tornando sulla scheda il Canale Principale mostra i post pubblicati nel frattempo', (tester) async {
    var posts = [postJson('p1', 'Primo giorno del percorso')];
    final http = FakeHttp({
      '/api/users/me': (200, _member),
      _posts: (RequestOptions _) => (200, {'posts': posts, 'total': posts.length, 'page': 1, 'limit': 20}),
    });
    final container = ProviderContainer(overrides: [
      httpAdapterProvider.overrideWithValue(http),
      tokenStorageProvider.overrideWithValue(FakeTokenStorage(access: 'a', refresh: 'r')),
      pushServiceProvider.overrideWithValue(FakePush()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const App()));
    await tester.pumpAndSettle();
    expect(find.text('Primo giorno del percorso'), findsOneWidget);

    posts = [postJson('p2', 'Secondo giorno del percorso'), ...posts];
    await tester.tap(find.text('Profilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Secondo giorno del percorso'), findsOneWidget);
  });

  testWidgets('la home dice il giorno del percorso e i post non mostrano l\'autore', (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(days: 2));
    await _openHome(tester, {
      '/api/users/me': (200, {
        ...userJson('user'),
        'group': {'id': 'g1', 'startedAt': startedAt.toUtc().toIso8601String(), 'endedAt': null, 'durationDays': 30},
      }),
      _posts: (200, {
        'posts': [
          {...postJson('p1', 'Un post'), 'author': {'id': 'u-admin', 'name': 'Anna', 'surname': 'Bianchi'}},
        ],
        'total': 1,
        'page': 1,
        'limit': 20,
      }),
    });

    expect(find.text('Giorno 3 di 30'), findsOneWidget);
    expect(find.text('Un post'), findsOneWidget);
    expect(find.textContaining('Anna'), findsNothing);
  });

  testWidgets('a cerchio chiuso la home non mostra l\'ingresso', (tester) async {
    await _openHome(tester, {_status: (200, {'status': 'closed'})});

    expect(find.text('Il cerchio è aperto'), findsNothing);
  });

  testWidgets('toccare l\'ingresso nella home fa entrare nel cerchio', (tester) async {
    var joined = false;
    final app = await _openHome(tester, {
      _status: (RequestOptions _) => (200, {
            'status': 'open',
            'channelId': 'ch1',
            'scheduledClosedAt': '2099-01-01T10:00:00.000Z',
            'joined': joined,
            'memberCount': joined ? 1 : 0,
          }),
      _join: (RequestOptions _) {
        joined = true;
        return (200, {'joined': true, 'history': <Object>[]});
      },
      '/api/sharing-channel/posts': (200, <Object>[]),
    });

    await tester.tap(find.text('Il cerchio è aperto'));
    await tester.pumpAndSettle();

    expect(app.http.calls(_join), 1);
    expect(find.text('1 persona è nel cerchio'), findsOneWidget);
    expect(find.byTooltip('Esci dal cerchio'), findsOneWidget);
    // The circle reloads itself: stop it before the test ends.
    await tester.pumpWidget(const SizedBox());
    app.container.dispose();
  });
}

const _status = '/api/sharing-channel/status';
const _join = '/api/sharing-channel/join';

Future<({ProviderContainer container, FakeHttp http})> _openHome(WidgetTester tester, Map<String, Object> routes) async {
  final http = FakeHttp({
    '/api/users/me': (200, _member),
    _posts: (200, {'posts': <Object>[], 'total': 0, 'page': 1, 'limit': 20}),
    ...routes,
  });
  final container = ProviderContainer(overrides: [
    httpAdapterProvider.overrideWithValue(http),
    tokenStorageProvider.overrideWithValue(FakeTokenStorage(access: 'a', refresh: 'r')),
    pushServiceProvider.overrideWithValue(FakePush()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const App()));
  await tester.pumpAndSettle();
  return (container: container, http: http);
}
