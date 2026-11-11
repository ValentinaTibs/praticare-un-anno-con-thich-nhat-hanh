import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/error_retry.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';
import 'circle.dart';

/// "Cerchio" section: the weekly appointment of every group's circle and the
/// moderation of the open ones.
class CirclePage extends ConsumerWidget {
  const CirclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      children: [
        Semantics(
          header: true,
          child: Text('Cerchio', style: Theme.of(context).textTheme.headlineMedium),
        ),
        const SizedBox(height: 16),
        const _ScheduleCard(),
        const SizedBox(height: 24),
        const _OpenCircles(),
      ],
    );
  }
}

String _count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// The open circles of every group, with the members and messages of the selected one.
class _OpenCircles extends ConsumerStatefulWidget {
  const _OpenCircles();

  @override
  ConsumerState<_OpenCircles> createState() => _OpenCirclesState();
}

class _OpenCirclesState extends ConsumerState<_OpenCircles> {
  /// Moderation is not real time: the page reloads at this pace, or on «Aggiorna».
  static const refreshEvery = Duration(seconds: 10);

  String? _selected;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(openCirclesProvider);
    ref.invalidate(circleDetailProvider);
  }

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(openCirclesProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Cerchi aperti', style: theme.textTheme.titleLarge),
            const SizedBox(width: 16),
            OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Aggiorna')),
          ],
        ),
        const SizedBox(height: 12),
        circles.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorRetry(
            message: e is ApiException ? e.message : 'Impossibile caricare i cerchi aperti.',
            onRetry: _refresh,
          ),
          data: (list) {
            if (list.isEmpty) return const Text('Nessun cerchio aperto');
            // A circle that closed in the meantime is no longer shown.
            final selected = list.any((c) => c.id == _selected) ? _selected : null;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    children: [
                      for (final c in list)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            selected: c.id == selected,
                            title: Text('Gruppo dal ${formatDate(c.groupStartedAt)}'),
                            subtitle: Text(
                              'Chiude il ${formatDateTime(c.scheduledClosedAt)} · '
                              '${_count(c.memberCount, 'membro', 'membri')} · '
                              '${_count(c.postCount, 'messaggio', 'messaggi')}',
                            ),
                            onTap: () => setState(() => _selected = c.id),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: selected == null
                      ? const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text('Scegli un cerchio per vederne membri e messaggi.'),
                        )
                      : _CircleDetailView(id: selected),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CircleDetailView extends ConsumerWidget {
  final String id;

  const _CircleDetailView({required this.id});

  Future<void> _delete(BuildContext context, WidgetRef ref, CircleMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Cancellare il messaggio?'),
        content: Text('Il messaggio di ${message.author} sparirà per tutti i membri del cerchio.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Cancella')),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(panelApiClientProvider).delete('/api/sharing-channel/posts/${message.id}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Impossibile cancellare il messaggio.')),
        );
      }
    }
    ref.invalidate(circleDetailProvider(id));
    ref.invalidate(openCirclesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(id));
    final theme = Theme.of(context);

    return detail.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorRetry(
        message: e is ApiException ? e.message : 'Impossibile caricare il cerchio.',
        onRetry: () => ref.invalidate(circleDetailProvider(id)),
      ),
      data: (d) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Membri (${d.members.length})', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (d.members.isEmpty) const Text('Nessuno è ancora entrato.'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in d.members) Chip(label: Text(m))],
              ),
              const Divider(height: 32),
              Text('Messaggi (${d.messages.length})', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (d.messages.isEmpty) const Text('Nessun messaggio.'),
              for (final m in d.messages)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.author),
                  subtitle: Text(m.content),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat('HH:mm').format(m.createdAt.toLocal())),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => _delete(context, ref, m), child: const Text('Cancella')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(circleScheduleProvider);
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Programmazione', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                schedule.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorRetry(
                    message: e is ApiException ? e.message : 'Impossibile caricare la programmazione.',
                    onRetry: () => ref.invalidate(circleScheduleProvider),
                  ),
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s?.description ?? 'Nessuna programmazione: il cerchio non si apre finché non la imposti.',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vale per i cerchi di tutti i gruppi, in ora italiana. Una modifica vale dal prossimo '
                        'appuntamento: un cerchio aperto finisce all\'orario previsto.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      // Rebuilt from scratch whenever the saved schedule changes.
                      _ScheduleForm(key: ValueKey(s?.description), schedule: s),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleForm extends ConsumerStatefulWidget {
  final CircleSchedule? schedule;

  const _ScheduleForm({super.key, required this.schedule});

  @override
  ConsumerState<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends ConsumerState<_ScheduleForm> {
  int? _dayOfWeek;
  String? _startTime;
  late final TextEditingController _duration;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dayOfWeek = widget.schedule?.dayOfWeek;
    _startTime = widget.schedule?.startTime;
    _duration = TextEditingController(text: widget.schedule?.durationMinutes.toString() ?? '');
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parts = (_startTime ?? '09:00').split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() => _startTime = '${two(picked.hour)}:${two(picked.minute)}');
  }

  String? _missing(int? duration) {
    if (_dayOfWeek == null) return 'Scegli il giorno della settimana.';
    if (_startTime == null) return 'Scegli l\'ora di inizio.';
    if (duration == null || duration <= 0) return 'Indica la durata in minuti.';
    return null;
  }

  Future<void> _save() async {
    final duration = int.tryParse(_duration.text.trim());
    final missing = _missing(duration);
    if (missing != null) return setState(() => _error = missing);

    final schedule = CircleSchedule(dayOfWeek: _dayOfWeek!, startTime: _startTime!, durationMinutes: duration!);
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(panelApiClientProvider).put('/api/sharing-channel/schedule', data: schedule.toJson());
      ref.invalidate(circleScheduleProvider);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Impossibile salvare la programmazione.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<int>(
                initialValue: _dayOfWeek,
                decoration: const InputDecoration(labelText: 'Giorno'),
                items: [
                  for (var day = 1; day <= 7; day++)
                    DropdownMenuItem(value: day, child: Text(weekdayNames[day - 1])),
                ],
                onChanged: (day) => setState(() => _dayOfWeek = day),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(_startTime == null ? 'Scegli l\'ora' : 'Ore $_startTime'),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Durata in minuti'),
              ),
            ),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Salva')),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}
