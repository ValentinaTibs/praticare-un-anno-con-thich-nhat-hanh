import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// out "Gruppo iniziato il", for the table's "Gruppo" column. Only for users from
/// /api/users, which always sends groupId: null there means waiting.
String groupLabelFor(User user, Map<String, PanelGroup> groupsById, {bool short = false}) {
  if (user.groupId == null) return 'In attesa';
  final group = groupsById[user.groupId];
  return group == null ? '—' : _groupLabel(group, short: short);
}

String _groupLabel(PanelGroup group, {required bool short}) {
  final label = short ? formatDate(group.startedAt) : group.label;
  return group.isArchived ? '$label (archiviato)' : label;
}

/// Searchable, filterable list of every user; a button on each row opens the user's card.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  late final TextEditingController _search;
  final _searchFocus = FocusNode();
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
    _searchFocus.dispose();
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
    // The clear button, which has the focus, is about to go away.
    _searchFocus.requestFocus();
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
                focusNode: _searchFocus,
                // The longest search the backend accepts.
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
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
              width: 280,
              // A group not loaded yet can't be selected in the menu.
              value: selectedGroup?.id,
              items: {
                null: 'Tutti i gruppi',
                for (final g in groups) g.id: _groupLabel(g, short: true),
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

/// Below this width the table scrolls sideways rather than squeezing its columns.
const _minTableWidth = 860.0;

class _UsersTable extends StatefulWidget {
  final List<User> users;
  final Map<String, PanelGroup> groupsById;
  final void Function(User user) onOpen;

  const _UsersTable({required this.users, required this.groupsById, required this.onOpen});

  @override
  State<_UsersTable> createState() => _UsersTableState();
}

class _UsersTableState extends State<_UsersTable> {
  final _sideways = ScrollController();

  @override
  void dispose() {
    _sideways.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      // Sideways outside and vertical inside, so that the sideways scrollbar stays
      // at the bottom of the visible area instead of below the last row.
      builder: (context, constraints) => Scrollbar(
        controller: _sideways,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _sideways,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: max(constraints.maxWidth, _minTableWidth),
            height: constraints.maxHeight,
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Scheda')),
                  // The columns that may hold long texts share the width left by the
                  // others and cut their text, so that no value pushes the rest away.
                  DataColumn(label: _FlexLabel('Nome e cognome'), columnWidth: FlexColumnWidth(3)),
                  DataColumn(label: _FlexLabel('Email'), columnWidth: FlexColumnWidth(4.5)),
                  DataColumn(label: _FlexLabel('Gruppo'), columnWidth: FlexColumnWidth(2.5)),
                  DataColumn(label: Text('Ruolo')),
                  DataColumn(label: Text('Stato')),
                  DataColumn(label: Text('Revisione')),
                ],
                rows: [
                  for (final u in widget.users)
                    DataRow(
                      cells: [
                        // The only way into the card: a clickable row would make each
                        // of its cells a stop of the Tab key.
                        DataCell(IconButton(
                          tooltip: 'Apri la scheda di ${u.name} ${u.surname}',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => widget.onOpen(u),
                        )),
                        DataCell(_CutText('${u.name} ${u.surname}')),
                        DataCell(_CutText(u.email ?? '—')),
                        DataCell(_CutText(groupLabelFor(u, widget.groupsById, short: true))),
                        DataCell(Text(u.roleLabel)),
                        DataCell(Text(
                          u.statusLabel,
                          style: u.isActive ? null : TextStyle(color: theme.colorScheme.error),
                        )),
                        DataCell(u.reviewedByAdmin ? const Text('Revisionato') : const _ToReviewBadge()),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The heading of a column whose width depends on the space left: cut if needed.
class _FlexLabel extends StatelessWidget {
  final String text;

  const _FlexLabel(this.text);

  @override
  Widget build(BuildContext context) => Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis));
}

/// One line of text, cut if it doesn't fit: the tooltip shows all of it.
class _CutText extends StatelessWidget {
  final String text;

  const _CutText(this.text);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: text,
        excludeFromSemantics: true,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class _ToReviewBadge extends StatelessWidget {
  const _ToReviewBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('Da revisionare', style: TextStyle(color: colors.onTertiaryContainer)),
      ),
    );
  }
}

class _Pagination extends StatefulWidget {
  final UsersState state;
  final void Function(int page) onPage;

  const _Pagination({required this.state, required this.onPage});

  @override
  State<_Pagination> createState() => _PaginationState();
}

class _PaginationState extends State<_Pagination> {
  final _previous = FocusNode();
  final _next = FocusNode();

  int get _page => widget.state.page;
  bool get _hasPrevious => _page > 1;
  bool get _hasNext => _page < widget.state.pageCount;

  @override
  void didUpdateWidget(_Pagination oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A disabled button loses the focus, which would land in the middle of the
    // table: it moves to the other button once this one is enabled.
    final target = _next.hasFocus && !_hasNext
        ? _previous
        : _previous.hasFocus && !_hasPrevious
            ? _next
            : null;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) target.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _previous.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The buttons stay enabled while a page loads, not to lose the focus: the
    // notifier only keeps the answer to the latest request.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Pagina precedente',
            icon: const Icon(Icons.chevron_left),
            focusNode: _previous,
            onPressed: _hasPrevious ? () => widget.onPage(_page - 1) : null,
          ),
          Semantics(liveRegion: true, child: Text('Pagina $_page di ${widget.state.pageCount}')),
          IconButton(
            tooltip: 'Pagina successiva',
            icon: const Icon(Icons.chevron_right),
            focusNode: _next,
            onPressed: _hasNext ? () => widget.onPage(_page + 1) : null,
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
