import 'package:community_app/app.dart';
import 'package:community_app/features/auth/auth_notifier.dart';
import 'package:community_app/features/sharing_channel/sharing_channel_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../panel/fakes.dart';
import 'app_fakes.dart';

const _status = '/api/sharing-channel/status';
const _posts = '/api/sharing-channel/posts';

final _member = {
  ...userJson('user'),
  'group': {'id': 'g1', 'startedAt': '2026-01-01T00:00:00.000Z', 'endedAt': null},
};

const _openJoined = {
  'status': 'open',
  'channelId': 'ch1',
  'openedAt': '2099-01-01T09:00:00.000Z',
  'scheduledClosedAt': '2099-01-01T10:00:00.000Z',
  'joined': true,
};

Map<String, dynamic> postJson(String id, String content, {String authorId = 'u-user', String name = 'Giulia'}) => {
      'id': id,
      'sharingChannelId': 'ch1',
      'author': {'id': authorId, 'name': name, 'surname': 'Rossi'},
      'content': content,
      'createdAt': '2099-01-01T09:05:00.000Z',
    };

// Opens the app on the circle tab, as a member of an active group.
Future<({ProviderContainer container, FakeHttp http})> openCircle(WidgetTester tester, Map<String, Object> routes) async {
  final http = FakeHttp({
    '/api/users/me': (200, _member),
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
  await tester.tap(find.text('Condivisione'));
  await tester.pumpAndSettle();
  return (container: container, http: http);
}

// Closing the app stops the circle's periodic reload.
Future<void> closeApp(WidgetTester tester, ({ProviderContainer container, FakeHttp http}) app) async {
  await tester.pumpWidget(const SizedBox());
  app.container.dispose();
}

void main() {
  setUpAll(initItalianLocale);

  testWidgets('il messaggio inviato compare subito a chi l\'ha scritto', (tester) async {
    final app = await openCircle(tester, {
      _status: (200, _openJoined),
      _posts: (RequestOptions options) =>
          options.method == 'POST' ? (201, postJson('p1', options.data['content'] as String)) : (200, <Object>[]),
    });

    await tester.enterText(find.byType(TextField), 'Buongiorno a tutti');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Buongiorno a tutti'), findsOneWidget);
    await closeApp(tester, app);
  });

  testWidgets('i messaggi degli altri compaiono al ricaricamento periodico', (tester) async {
    var posts = <Object>[];
    final app = await openCircle(tester, {
      _status: (200, _openJoined),
      _posts: (RequestOptions _) => (200, posts),
    });
    expect(find.text('Ciao dal cerchio'), findsNothing);

    posts = [postJson('p2', 'Ciao dal cerchio', authorId: 'u-other', name: 'Marco')];
    await tester.pump(SharingChannelNotifier.refreshInterval);
    await tester.pumpAndSettle();

    expect(find.text('Ciao dal cerchio'), findsOneWidget);
    await closeApp(tester, app);
  });

  testWidgets('se l\'invio non riesce il testo resta e un avviso lo dice', (tester) async {
    final app = await openCircle(tester, {
      _status: (200, _openJoined),
      _posts: (RequestOptions options) =>
          options.method == 'POST' ? (403, {'message': 'Prima entra nel canale'}) : (200, <Object>[]),
    });

    await tester.enterText(find.byType(TextField), 'Non arriva');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Messaggio non inviato. Riprova.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Non arriva');
    await closeApp(tester, app);
  });

  testWidgets('lasciata la schermata il cerchio non si ricarica più', (tester) async {
    final app = await openCircle(tester, {
      _status: (200, _openJoined),
      _posts: (200, <Object>[]),
    });

    await tester.tap(find.text('Profilo'));
    await tester.pumpAndSettle();
    final calls = app.http.calls(_status);
    await tester.pump(SharingChannelNotifier.refreshInterval * 3);

    expect(app.http.calls(_status), calls);
    await closeApp(tester, app);
  });
}
