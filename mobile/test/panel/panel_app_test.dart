import 'dart:io';

import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:community_app/panel/panel_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

/// Starts the panel with a stored session belonging to [role], or none.
Future<ProviderContainer> pumpPanel(WidgetTester tester, {String? role}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    panelApiClientProvider.overrideWithValue(FakeApiClient({
      if (role != null) '/api/users/me': userJson(role),
      '/api/auth/logout': {'message': 'Disconnesso'},
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

void main() {
  testWidgets('senza sessione mostra la pagina di accesso', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Accedi'), findsOneWidget);
    expect(find.text('Utenti e gruppi'), findsNothing);
  });

  testWidgets('un admin vede le sezioni comuni ma non quelle del Super Admin', (tester) async {
    await pumpPanel(tester, role: 'admin');
    expect(find.text('Utenti e gruppi'), findsWidgets);
    expect(find.text('Frasi del giorno'), findsOneWidget);
    expect(find.text('Cicli'), findsNothing);
    expect(find.text('Ruoli'), findsNothing);
    expect(find.text('Testi'), findsNothing);
  });

  testWidgets('un admin che apre una pagina del Super Admin torna alla prima sezione', (tester) async {
    final container = await pumpPanel(tester, role: 'admin');
    container.read(panelRouterProvider).go('/ruoli');
    await tester.pumpAndSettle();
    expect(find.text('Promozione e declassamento degli admin.'), findsNothing);
    expect(container.read(panelRouterProvider).routerDelegate.currentConfiguration.uri.path, '/utenti');
  });

  testWidgets('il Super Admin vede anche cicli, ruoli e testi', (tester) async {
    final container = await pumpPanel(tester, role: 'super_admin');
    expect(find.text('Cicli'), findsOneWidget);
    expect(find.text('Ruoli'), findsOneWidget);
    expect(find.text('Testi'), findsOneWidget);

    await tester.tap(find.text('Ruoli'));
    await tester.pumpAndSettle();
    expect(find.text('Promozione e declassamento degli admin.'), findsOneWidget);
    expect(container.read(panelRouterProvider).routerDelegate.currentConfiguration.uri.path, '/ruoli');
  });

  testWidgets('le voci del menu sono accessibili ai lettori di schermo', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPanel(tester, role: 'admin');
    expect(find.bySemanticsLabel(RegExp('Frasi del giorno')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Utenti e gruppi')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('dopo l\'uscita torna alla pagina di accesso', (tester) async {
    await pumpPanel(tester, role: 'admin');
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(find.text('Accedi'), findsOneWidget);
  });

  test('il pannello non importa le schermate dell\'app', () {
    final files = Directory('lib/panel').listSync(recursive: true).whereType<File>().toList()
      ..add(File('lib/main_panel.dart'));
    final offending = [
      for (final f in files)
        if (RegExp(r"import '([^']*/)?(features/[^']*|app\.dart)'").hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(offending, isEmpty, reason: 'lib/panel può importare solo da lib/core');
  });
}
