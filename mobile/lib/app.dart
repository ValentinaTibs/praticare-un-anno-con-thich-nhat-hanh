import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/auth_notifier.dart';
import 'features/auth/screens/phone_screen.dart';
import 'features/auth/screens/otp_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/main_channel/screens/main_channel_screen.dart';
import 'features/sharing_channel/screens/sharing_channel_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/admin/screens/admin_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/auth/phone',
    redirect: (context, state) {
      final isAuth = authState.status == AuthStatus.authenticated;
      final isLoading = authState.status == AuthStatus.loading;
      final onAuth = state.matchedLocation.startsWith('/auth');

      if (isLoading) return null;
      if (!isAuth && !onAuth) return '/auth/phone';
      if (isAuth && onAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (_, state) => OtpScreen(phoneNumber: state.extra as String),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, state) {
          final extra = state.extra as Map<String, String>;
          return RegisterScreen(phoneNumber: extra['phone']!, otpCode: extra['code']!);
        },
      ),
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
      (path: '/home/sharing', icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Sharing'),
      (path: '/home/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
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
