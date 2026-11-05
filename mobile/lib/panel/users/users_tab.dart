import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import '../format.dart';
import '../widgets/error_retry.dart';
import 'group.dart';
import 'user_details_dialog.dart';
import 'users_notifier.dart';

const _statusFilters = <String?, String>{
  null: 'Tutti',
  'active': 'Attivi',
  'suspended': 'Sospesi',
  'banned': 'Bannati',
};

/// The user's group, named by its start date, or "In attesa". [short] leaves
/// out "Gruppo iniziato il", for the table's "Gruppo" column.
String groupLabelFor(User user, Map<String, PanelGroup> groupsById, {bool short = false}) {
  if (user.isWaiting) return 'In attesa';
  final group = groupsById[user.groupId];
  if (group == null) return '—';
  final label = short ? formatDate(group.startedAt) : group.label;
  return group.isArchived ? '$label (archiviato)' : label;
}

/// Searchable, filterable list of every user; a row opens the user's card.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  late final TextEditingController _search;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(usersProvider).filters.search);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String text) {
    setState(() {}); // shows or hides the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => ref.read(usersProvider.notifier).setSearch(text));
  }

  void _searchNow(String text) {
    _debounce?.cancel();
    ref.read(usersProvider.notifier).setSearch(text);
  }

  void _clearSearch() {
    _search.clear();
    setState(() {});
    _searchNow('');
  }

  void _open(User user, Map<String, PanelGroup> groupsById) {
    showDialog<void>(
      context: context,
      builder: (_) => UserDetailsDialog(user: user, groupLabel: groupLabelFor(user, groupsById)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(usersProvider);
    final notifier = ref.read(usersProvider.notifier);
    final groups = ref.watch(groupsProvider).valueOrNull ?? const <PanelGroup>[];
    final groupsById = {for (final g in groups) g.id: g};
    final selectedGroup = groupsById[state.filters.groupId];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                controller: _search,
                onChanged: _searchChanged,
                onSubmitted: _searchNow,
                decoration: InputDecoration(
                  labelText: 'Cerca per nome, cognome o email',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella la ricerca',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            _Dropdown<String?>(
              label: 'Gruppo',
              width: 320,
              // A group not loaded yet can't be selected in the menu.
              value: selectedGroup?.id,
              items: {
                null: 'Tutti i gruppi',
                for (final g in groups) g.id: g.isArchived ? '${g.label} (archiviato)' : g.label,
              },
              onChanged: notifier.setGroup,
            ),
            _Dropdown<String?>(
              label: 'Stato',
              width: 180,
              value: state.filters.status,
              items: _statusFilters,
              onChanged: notifier.setStatus,
            ),
            FilterChip(
              label: const Text('Solo da revisionare'),
              selected: state.filters.onlyToReview,
              onSelected: notifier.setOnlyToReview,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            [
              if (selectedGroup != null) 'Membri del gruppo iniziato il ${formatDate(selectedGroup.startedAt)}',
              if (!state.loading && state.error == null) state.total == 1 ? '1 utente' : '${state.total} utenti',
            ].join(' · '),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 4, child: state.loading && state.users.isNotEmpty ? const LinearProgressIndicator() : null),
        Expanded(child: _body(state, groupsById)),
        if (state.pageCount > 1 && state.error == null) _Pagination(state: state, onPage: notifier.goToPage),
      ],
    );
  }

  Widget _body(UsersState state, Map<String, PanelGroup> groupsById) {
    if (state.error != null) {
      return ErrorRetry(message: state.error!, onRetry: ref.read(usersProvider.notifier).retry);
    }
    if (state.users.isEmpty) {
      return state.loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Nessun utente trovato'));
    }
    return _UsersTable(users: state.users, groupsById: groupsById, onOpen: (u) => _open(u, groupsById));
  }
}

class _UsersTable extends StatelessWidget {
  final List<User> users;
  final Map<String, PanelGroup> groupsById;
  final void Function(User user) onOpen;

  const _UsersTable({required this.users, required this.groupsById, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 32,
              columns: const [
                DataColumn(label: Text('Scheda')),
                DataColumn(label: Text('Nome e cognome')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Gruppo')),
                DataColumn(label: Text('Ruolo')),
                DataColumn(label: Text('Stato')),
                DataColumn(label: Text('Revisione')),
              ],
              rows: [
                for (final u in users)
                  DataRow(
                    onSelectChanged: (_) => onOpen(u),
                    cells: [
                      // First, so it stays in view when the table scrolls sideways.
                      DataCell(IconButton(
                        tooltip: 'Apri la scheda di ${u.name} ${u.surname}',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => onOpen(u),
                      )),
                      DataCell(Text('${u.name} ${u.surname}')),
                      DataCell(Text(u.email ?? '—')),
                      DataCell(Text(groupLabelFor(u, groupsById, short: true))),
                      DataCell(Text(u.roleLabel)),
                      DataCell(Text(
                        u.statusLabel,
                        style: u.isActive ? null : TextStyle(color: theme.colorScheme.error),
                      )),
                      DataCell(
                        u.reviewedByAdmin
                            ? const Text('Revisionato')
                            : Chip(
                                label: const Text('Da revisionare'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: theme.colorScheme.tertiaryContainer,
                                side: BorderSide.none,
                              ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final UsersState state;
  final void Function(int page) onPage;

  const _Pagination({required this.state, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final page = state.page;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Pagina precedente',
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 1 && !state.loading ? () => onPage(page - 1) : null,
          ),
          Text('Pagina $page di ${state.pageCount}'),
          IconButton(
            tooltip: 'Pagina successiva',
            icon: const Icon(Icons.chevron_right),
            onPressed: page < state.pageCount && !state.loading ? () => onPage(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// A labelled drop-down whose value always follows [value].
class _Dropdown<T> extends StatelessWidget {
  final String label;
  final double width;
  final T value;
  final Map<T, String> items;
  final void Function(T value) onChanged;

  const _Dropdown({
    required this.label,
    required this.width,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            items: [
              for (final e in items.entries)
                DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => onChanged(v as T),
          ),
        ),
      ),
    );
  }
}
