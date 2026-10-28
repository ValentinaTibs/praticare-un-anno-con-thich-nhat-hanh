import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'features/auth/auth_notifier.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/signup_screen.dart';
import 'features/auth/screens/verify_email_screen.dart';
import 'features/main_channel/screens/main_channel_screen.dart';
import 'features/sharing_channel/screens/sharing_channel_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/admin/screens/admin_screen.dart';

/// The app is Italian-only: DateFormat and the Material widgets (date and time
/// pickers included) all use this locale. Call before runApp.
Future<void> initItalianLocale() async {
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');
}

final _routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/auth/login',
    redirect: (context, state) {
      final isAuth = authState.status == AuthStatus.authenticated;
      final isLoading = authState.status == AuthStatus.loading;
      final onAuth = state.matchedLocation.startsWith('/auth');

      if (isLoading) return null;
      if (!isAuth && !onAuth) return '/auth/login';
      if (isAuth && onAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/auth/verify-email', builder: (_, __) => const VerifyEmailScreen()),
      GoRoute(path: '/auth/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (_, state, child) => _HomeShell(child: child, location: state.matchedLocation),
        routes: [
          GoRoute(path: '/home', redirect: (_, __) => '/home/main-channel'),
          GoRoute(path: '/home/main-channel', builder: (_, __) => const MainChannelScreen()),
          GoRoute(path: '/home/sharing', builder: (_, __) => const SharingChannelScreen()),
          GoRoute(path: '/home/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/home/admin', builder: (_, __) => const AdminScreen()),
        ],
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: 'Community',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C6BC0)),
        useMaterial3: true,
      ),
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}

class _HomeShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const _HomeShell({required this.child, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin ?? false;

    final tabs = [
      (path: '/home/main-channel', icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
      (path: '/home/sharing', icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Condivisione'),
      (path: '/home/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profilo'),
      if (isAdmin)
        (path: '/home/admin', icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings, label: 'Admin'),
    ];

    final currentIndex = tabs.indexWhere((t) => location.startsWith(t.path));

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.activeIcon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}
