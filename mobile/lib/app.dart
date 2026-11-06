import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/constants.dart';
import 'core/widgets/session_unavailable.dart';
import 'features/auth/auth_notifier.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/signup_screen.dart';
import 'features/auth/screens/verify_email_screen.dart';
import 'features/main_channel/screens/main_channel_screen.dart';
import 'features/sharing_channel/screens/sharing_channel_screen.dart';
import 'features/waiting/next_journey.dart';
import 'features/waiting/screens/waiting_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/admin/screens/admin_screen.dart';

export 'core/locale.dart';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C6BC0)),
  useMaterial3: true,
);

const _waitingPath = '/home/waiting';

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
      if (!isAuth) return null;

      // Waiting users have no Main Channel and no sharing channel.
      final location = state.matchedLocation;
      final waiting = authState.user?.isWaiting ?? false;
      if (waiting && (location.startsWith('/home/main-channel') || location.startsWith('/home/sharing'))) {
        return _waitingPath;
      }
      if (!waiting && location.startsWith(_waitingPath)) return '/home/main-channel';
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
          GoRoute(path: _waitingPath, builder: (_, __) => const WaitingScreen()),
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
    if (ref.watch(authProvider).status == AuthStatus.unavailable) {
      final auth = ref.read(authProvider.notifier);
      return MaterialApp(
        title: AppConstants.appName,
        theme: _theme,
        home: SessionUnavailable(onRetry: auth.retry, onLogout: auth.logout),
      );
    }
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: _theme,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}

class _HomeShell extends ConsumerStatefulWidget {
  final Widget child;
  final String location;

  const _HomeShell({required this.child, required this.location});

  @override
  ConsumerState<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<_HomeShell> {
  // A group may have started or ended while the app was in the background.
  late final _lifecycle = AppLifecycleListener(onResume: () {
    ref.read(authProvider.notifier).refreshUser();
    ref.invalidate(nextJourneyProvider);
  });

  @override
  void initState() {
    super.initState();
    _lifecycle; // created here: late fields start only when read
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin ?? false;
    final waiting = user?.isWaiting ?? false;
    final location = widget.location;

    final tabs = [
      if (waiting)
        (path: _waitingPath, icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home')
      else ...[
        (path: '/home/main-channel', icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
        (path: '/home/sharing', icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Condivisione'),
      ],
      (path: '/home/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profilo'),
      if (isAdmin)
        (path: '/home/admin', icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings, label: 'Admin'),
    ];

    final currentIndex = tabs.indexWhere((t) => location.startsWith(t.path));

    return Scaffold(
      body: widget.child,
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
