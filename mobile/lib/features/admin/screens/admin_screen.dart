import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../auth/auth_notifier.dart';
import '../../../core/api/api_client.dart';
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
        title: const Text('Admin'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Sharing'),
            Tab(text: 'Cycles'),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Done: $action')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(value: 'false', label: Text('New')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
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
      title: Text('${user.name} ${user.surname}'),
      subtitle: Text('${user.role} · ${user.status}${!user.reviewedByAdmin ? ' · NEW' : ''}'),
      trailing: isMe
          ? null
          : PopupMenuButton<String>(
              onSelected: (a) => onAction(user.id, a),
              itemBuilder: (_) => [
                if (!user.reviewedByAdmin)
                  const PopupMenuItem(value: 'review', child: Text('Mark reviewed')),
                if (user.status == 'suspended')
                  const PopupMenuItem(value: 'reactivate', child: Text('Reactivate'))
                else if (user.status == 'active')
                  const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                if (user.status != 'banned')
                  const PopupMenuItem(value: 'ban', child: Text('Ban', style: TextStyle(color: Colors.red))),
                const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Colors.red))),
                if (isSuperAdmin) ...[
                  if (user.role == 'user')
                    const PopupMenuItem(value: 'promote', child: Text('Promote to Admin'))
                  else if (user.role == 'admin')
                    const PopupMenuItem(value: 'demote', child: Text('Demote to User')),
                ],
              ],
            ),
    );
  }
}

// ── Sharing tab ───────────────────────────────────────────────────────────────

class _SharingTab extends ConsumerStatefulWidget {
  const _SharingTab();

  @override
  ConsumerState<_SharingTab> createState() => _SharingTabState();
}

class _SharingTabState extends ConsumerState<_SharingTab> {
  DateTime? _selectedClose;

  Future<void> _pickCloseTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _selectedClose = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _open() async {
    if (_selectedClose == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a closing time first')));
      return;
    }
    final api = ref.read(apiClientProvider);
    await api.post('/api/sharing-channel/open', data: {
      'scheduledClosedAt': _selectedClose!.toUtc().toIso8601String(),
    });
    ref.invalidate(_sharingStatusProvider);
  }

  Future<void> _close() async {
    final api = ref.read(apiClientProvider);
    await api.post('/api/sharing-channel/close');
    ref.invalidate(_sharingStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
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
              Text('Current status', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Chip(
                label: Text(isOpen ? 'Open' : 'Closed', style: const TextStyle(color: Colors.white)),
                backgroundColor: isOpen ? Colors.green : Colors.grey,
              ),
              if (isOpen && status['scheduledClosedAt'] != null) ...[
                const SizedBox(height: 4),
                Text('Scheduled close: ${DateFormat('d MMM HH:mm').format(DateTime.parse(status['scheduledClosedAt'] as String).toLocal())}'),
              ],
              const Divider(height: 40),
              if (!isOpen) ...[
                Text('Open a new session', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickCloseTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(_selectedClose != null
                      ? 'Closes: ${DateFormat('d MMM HH:mm').format(_selectedClose!)}'
                      : 'Set closing time'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _open,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Open sharing channel'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _close,
                  icon: const Icon(Icons.stop),
                  label: const Text('Close now'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
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
      return const Center(child: Text('Super admin only'));
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
              Text('Registration cycle', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Chip(
                label: Text(isOpen ? 'Open' : 'Closed', style: const TextStyle(color: Colors.white)),
                backgroundColor: isOpen ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 24),
              if (!isOpen)
                FilledButton.icon(
                  onPressed: () async {
                    await ref.read(apiClientProvider).post('/api/cycles/open');
                    ref.invalidate(_cycleProvider);
                  },
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Open registrations'),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    await ref.read(apiClientProvider).post('/api/cycles/close');
                    ref.invalidate(_cycleProvider);
                  },
                  icon: const Icon(Icons.lock),
                  label: const Text('Close registrations'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                ),
              const SizedBox(height: 8),
              if (isOpen)
                Text(
                  'Opening a new cycle will unblock phones of previously removed users.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
            ],
          ),
        );
      },
    );
  }
}
