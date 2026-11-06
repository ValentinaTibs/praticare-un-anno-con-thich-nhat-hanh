import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/session_unavailable.dart';
import 'auth/login_page.dart';
import 'auth/panel_auth_notifier.dart';
import 'cycles/cycles_page.dart';
import 'sections.dart';
import 'shell/panel_shell.dart';
import 'users/users_page.dart';

const _loginPath = '/accesso';
const _title = 'Pannello di amministrazione';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C6BC0)),
  useMaterial3: true,
);

/// Sections whose page is ready; the others show a placeholder.
const _sectionPages = <String, Widget>{
  '/utenti': UsersPage(),
  '/cicli': CyclesPage(),
};

final panelRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(panelAuthProvider);

  return GoRouter(
    initialLocation: panelSections.first.path,
    redirect: (context, state) {
      if (auth.status == PanelAuthStatus.loading) return null;
      final onLogin = state.matchedLocation == _loginPath;
      final user = auth.user;
      if (user == null) return onLogin ? null : _loginPath;
      final allowed = sectionsFor(user);
      if (onLogin || !allowed.any((s) => state.matchedLocation.startsWith(s.path))) {
        return allowed.first.path;
      }
      return null;
    },
    routes: [
      GoRoute(path: _loginPath, builder: (_, __) => const LoginPage()),
      ShellRoute(
        builder: (_, state, child) => PanelShell(location: state.matchedLocation, child: child),
        routes: [
          for (final s in panelSections)
            GoRoute(
              path: s.path,
              pageBuilder: (_, __) => NoTransitionPage(child: _sectionPages[s.path] ?? SectionPlaceholder(section: s)),
            ),
        ],
      ),
    ],
  );
});

class PanelApp extends ConsumerWidget {
  const PanelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(panelAuthProvider).status;
    if (status == PanelAuthStatus.loading) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    if (status == PanelAuthStatus.unavailable) {
      final auth = ref.read(panelAuthProvider.notifier);
      return MaterialApp(
        title: _title,
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: SessionUnavailable(onRetry: auth.retry, onLogout: auth.logout),
      );
    }
    return MaterialApp.router(
      title: _title,
      debugShowCheckedModeBanner: false,
      theme: _theme,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(panelRouterProvider),
    );
  }
}
