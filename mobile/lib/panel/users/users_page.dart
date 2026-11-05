import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'group.dart';
import 'groups_tab.dart';
import 'users_notifier.dart';
import 'users_tab.dart';

/// "Utenti e gruppi" section: groups with their members, and every user with
/// review, suspension, ban and removal.
class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openGroup(PanelGroup group) {
    ref.read(usersProvider.notifier).showGroup(group.id);
    _tabs.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    // Groups and the users list with its filters live as long as the page,
    // not as long as the tab showing them: switching tab keeps the filters.
    ref.watch(usersProvider.notifier);
    ref.listen(groupsProvider, (_, __) {});

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Utenti e gruppi', style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [Tab(text: 'Gruppi'), Tab(text: 'Utenti')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [GroupsTab(onOpenGroup: _openGroup), const UsersTab()],
            ),
          ),
        ],
      ),
    );
  }
}
