import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../auth/auth_notifier.dart';
import '../../../core/models/user.dart';

final _usersProvider = FutureProvider.family<List<User>, String?>((ref, filter) async {
  final api = ref.watch(apiClientProvider);
  final query = <String, String>{'limit': '50'};
  if (filter != null) query['reviewed'] = filter;
  final data = await api.get('/api/users', query: query);
  return ((data as Map)['users'] as List).map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
});

final _cycleProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/api/cycles/status');
  return data as Map<String, dynamic>;
});

final _sharingStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/api/sharing-channel/status');
  return data as Map<String, dynamic>;
});

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amministrazione'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Utenti'),
            Tab(text: 'Condivisione'),
            Tab(text: 'Cicli'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _UsersTab(),
          _SharingTab(),
          _CyclesTab(),
        ],
      ),
    );
  }
}

// ── Users tab ─────────────────────────────────────────────────────────────────

const _actionDone = {
  'review': 'Utente segnato come revisionato',
  'reactivate': 'Utente riattivato',
  'suspend': 'Utente sospeso',
  'ban': 'Utente bannato',
  'unban': 'Ban revocato',
  'remove': 'Utente rimosso',
  'promote': 'Utente promosso ad admin',
  'demote': 'Utente riportato a utente',
};

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  String? _filter; // null=all, 'false'=unreviewed

  Future<void> _act(String userId, String action) async {
    final api = ref.read(apiClientProvider);
    try {
      if (action == 'remove') {
        await api.delete('/api/admin/$userId');
      } else {
        await api.patch('/api/admin/$userId/$action');
      }
      ref.invalidate(_usersProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_actionDone[action] ?? 'Fatto')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(_usersProvider(_filter));
    final me = ref.watch(authProvider).user;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('Tutti')),
              ButtonSegment(value: 'false', label: Text('Da revisionare')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Errore: $e')),
            data: (users) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(_usersProvider),
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (_, i) => _UserTile(
                  user: users[i],
                  isMe: me?.id == users[i].id,
                  isSuperAdmin: me?.isSuperAdmin ?? false,
                  onAction: _act,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  final bool isMe;
  final bool isSuperAdmin;
  final Future<void> Function(String userId, String action) onAction;

  const _UserTile({
    required this.user,
    required this.isMe,
    required this.isSuperAdmin,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text(user.name[0].toUpperCase())),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: '${user.name} ${user.surname}'),
        if (!user.reviewedByAdmin)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Da revisionare',
                child: Icon(Icons.new_releases, size: 16, color: Colors.orange[700]),
              ),
            ),
          ),
      ])),
      subtitle: Text([
        if (user.email != null) user.email!,
        '${user.roleLabel} · ${user.statusLabel}',
      ].join('\n')),
      isThreeLine: user.email != null,
      trailing: isMe
          ? null
          : PopupMenuButton<String>(
              onSelected: (a) => onAction(user.id, a),
              itemBuilder: (_) => [
                if (!user.reviewedByAdmin)
                  const PopupMenuItem(value: 'review', child: Text('Segna come revisionato')),
                if (user.status == 'suspended')
                  const PopupMenuItem(value: 'reactivate', child: Text('Riattiva'))
                else if (user.status == 'active')
                  const PopupMenuItem(value: 'suspend', child: Text('Sospendi')),
                if (user.status != 'banned')
                  const PopupMenuItem(value: 'ban', child: Text('Banna', style: TextStyle(color: Colors.red))),
                const PopupMenuItem(value: 'remove', child: Text('Rimuovi', style: TextStyle(color: Colors.red))),
                if (isSuperAdmin) ...[
                  if (user.status == 'banned')
                    const PopupMenuItem(value: 'unban', child: Text('Revoca ban')),
                  if (user.role == 'user')
                    const PopupMenuItem(value: 'promote', child: Text('Promuovi ad admin'))
                  else if (user.role == 'admin')
                    const PopupMenuItem(value: 'demote', child: Text('Riporta a utente')),
                ],
              ],
            ),
    );
  }
}

// ── Sharing tab ───────────────────────────────────────────────────────────────

// The channel opens and closes by itself following the weekly schedule, so this tab only shows its state.
class _SharingTab extends ConsumerWidget {
  const _SharingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_sharingStatusProvider);

    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (status) {
        final isOpen = status['status'] == 'open';
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stato attuale', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Chip(
                label: Text(isOpen ? 'Aperto' : 'Chiuso', style: const TextStyle(color: Colors.white)),
                backgroundColor: isOpen ? Colors.green : Colors.grey,
              ),
              if (isOpen && status['scheduledClosedAt'] != null) ...[
                const SizedBox(height: 4),
                Text('Chiusura prevista: ${DateFormat('d MMM HH:mm').format(DateTime.parse(status['scheduledClosedAt'] as String).toLocal())}'),
              ],
              const Divider(height: 40),
              const Text('Il cerchio si apre e si chiude da solo, secondo la programmazione settimanale impostata dal pannello web.'),
            ],
          ),
        );
      },
    );
  }
}

// ── Cycles tab ────────────────────────────────────────────────────────────────

class _CyclesTab extends ConsumerWidget {
  const _CyclesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).user;
    if (!(me?.isSuperAdmin ?? false)) {
      return const Center(child: Text('Riservato ai super admin'));
    }

    final cycleAsync = ref.watch(_cycleProvider);

    return cycleAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (cycle) {
        final isOpen = cycle['open'] as bool;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ciclo di iscrizioni', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Chip(
                label: Text(isOpen ? 'Aperto' : 'Chiuso', style: const TextStyle(color: Colors.white)),
                backgroundColor: isOpen ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 24),
              const Text('I cicli si gestiscono dal pannello web.'),
            ],
          ),
        );
      },
    );
  }
}
