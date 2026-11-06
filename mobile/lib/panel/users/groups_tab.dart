import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../format.dart';
import '../widgets/error_retry.dart';
import 'group.dart';

/// Active and archived groups; opening one lists its members.
class GroupsTab extends ConsumerWidget {
  final void Function(PanelGroup group) onOpenGroup;

  const GroupsTab({super.key, required this.onOpenGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(groupsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            message: e is ApiException ? e.message : 'Impossibile caricare i gruppi.',
            onRetry: () => ref.invalidate(groupsProvider),
          ),
          data: (groups) {
            final active = groups.where((g) => !g.isArchived).toList();
            final archived = groups.where((g) => g.isArchived).toList();
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                _GroupList(title: 'Gruppi attivi', empty: 'Nessun gruppo attivo', groups: active, onOpen: onOpenGroup),
                const SizedBox(height: 32),
                _GroupList(
                  title: 'Gruppi archiviati',
                  empty: 'Nessun gruppo archiviato',
                  groups: archived,
                  onOpen: onOpenGroup,
                ),
              ],
            );
          },
        );
  }
}

class _GroupList extends StatelessWidget {
  final String title;
  final String empty;
  final List<PanelGroup> groups;
  final void Function(PanelGroup group) onOpen;

  const _GroupList({required this.title, required this.empty, required this.groups, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(title, style: theme.textTheme.titleLarge)),
            const SizedBox(height: 8),
            if (groups.isEmpty)
              Text(empty, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              for (final g in groups)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(g.label),
                    subtitle: Text(
                      g.isArchived ? '${g.membersLabel} · archiviato il ${formatDate(g.endedAt!)}' : g.membersLabel,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpen(g),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
