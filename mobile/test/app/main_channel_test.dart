import 'package:community_app/app.dart';
import 'package:community_app/features/auth/auth_notifier.dart';
import 'package:dio/dio.dart';
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
}
