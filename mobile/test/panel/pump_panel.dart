import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:community_app/panel/panel_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

/// Starts the panel with a stored session belonging to [role], or none, on a
/// backend answering [responses] on top of an empty list of groups and users.
/// The backend is `container.read(panelApiClientProvider) as FakeApiClient`.
Future<ProviderContainer> pumpPanel(
  WidgetTester tester, {
  String? role,
  Map<String, Object> responses = const {},
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    panelApiClientProvider.overrideWithValue(FakeApiClient({
      if (role != null) '/api/users/me': userJson(role),
      '/api/auth/logout': {'message': 'Disconnesso'},
      '/api/groups': <Object>[],
      '/api/users': usersPageJson([]),
      ...responses,
    })),
    panelTokenStorageProvider.overrideWithValue(
      role == null ? FakeTokenStorage() : FakeTokenStorage(access: 'a', refresh: 'r'),
    ),
    panelFirebaseProvider.overrideWithValue(FakePanelFirebase()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const PanelApp()));
  await tester.pumpAndSettle();
  return container;
}
