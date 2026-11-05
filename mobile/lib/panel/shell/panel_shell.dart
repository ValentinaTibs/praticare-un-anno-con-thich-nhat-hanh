import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/panel_auth_notifier.dart';
import '../sections.dart';

/// Frame of every signed-in page: side navigation and top bar with the user.
class PanelShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const PanelShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(panelAuthProvider).user;
    if (user == null) return const SizedBox.shrink();
    final sections = sectionsFor(user);
    final selected = sections.indexWhere((s) => location.startsWith(s.path));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pannello di amministrazione'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text('${user.name} ${user.surname} · ${user.roleLabel}')),
          ),
          TextButton.icon(
            onPressed: () => ref.read(panelAuthProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Esci'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            selectedIndex: selected < 0 ? null : selected,
            onDestinationSelected: (i) => context.go(sections[i].path),
            destinations: [
              for (final s in sections) NavigationRailDestination(icon: Icon(s.icon), label: Text(s.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          // The page is the ShellRoute's nested Navigator, whose route barrier
          // blocks the semantics of whatever was painted before it in the same
          // container: without its own container the side menu would be
          // invisible to screen readers.
          Expanded(child: Semantics(container: true, child: child)),
        ],
      ),
    );
  }
}

/// Stand-in for a section whose page has not been built yet.
class SectionPlaceholder extends StatelessWidget {
  final PanelSection section;

  const SectionPlaceholder({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.label, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(section.description, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          Text('Questa sezione è in preparazione.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
