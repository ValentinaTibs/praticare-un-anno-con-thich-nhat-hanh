import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/error_retry.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';
import 'cycle.dart';
import 'cycle_form_dialog.dart';

/// "Cicli" section, for the Super Admin: opens cycles, edits them until the
/// journey starts and closes requests early.
class CyclesPage extends ConsumerWidget {
  const CyclesPage({super.key});

  Future<void> _showForm(BuildContext context, WidgetRef ref, [PanelCycle? cycle]) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => CycleFormDialog(cycle: cycle));
    if (changed ?? false) ref.invalidate(cyclesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cycles = ref.watch(cyclesProvider);
    final hasOpenCycle = cycles.valueOrNull?.any((c) => c.isOpen) ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Cicli', style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: !cycles.hasValue || hasOpenCycle ? null : () => _showForm(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Apri un ciclo'),
          ),
          if (hasOpenCycle)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Può esserci un solo ciclo aperto alla volta.', style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: cycles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                message: e is ApiException ? e.message : 'Impossibile caricare i cicli.',
                onRetry: () => ref.invalidate(cyclesProvider),
              ),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Nessun ciclo'))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        for (final c in list)
                          Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: _CycleCard(cycle: c, onEdit: () => _showForm(context, ref, c)),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleCard extends ConsumerWidget {
  final PanelCycle cycle;
  final VoidCallback onEdit;

  const _CycleCard({required this.cycle, required this.onEdit});

  String get _status {
    if (cycle.hasStarted) return 'Percorso iniziato';
    return cycle.isOpen ? 'Richieste aperte' : 'Richieste chiuse';
  }

  String get _closing {
    final closedAt = cycle.closedAt;
    if (closedAt != null) return 'Richieste chiuse il ${formatDateTime(closedAt)}';
    final scheduled = cycle.scheduledClosedAt;
    return scheduled == null ? 'Nessuna data di chiusura' : 'Richieste aperte fino al ${formatDateTime(scheduled)}';
  }

  String get _people {
    if (cycle.hasStarted) {
      return cycle.participants == 1 ? '1 partecipante' : '${cycle.participants} partecipanti';
    }
    return cycle.requesters == 1 ? '1 richiedente' : '${cycle.requesters} richiedenti';
  }

  Future<void> _closeEarly(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Chiudere le richieste?'),
        content: const Text('Da subito nessuno potrà più chiedere di partecipare a questo percorso.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Chiudi le richieste')),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(panelApiClientProvider).post('/api/cycles/close');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Impossibile chiudere le richieste.')),
        );
      }
    }
    ref.invalidate(cyclesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Percorso dal ${formatDate(cycle.startsAt)}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_status, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Text(_people, style: theme.textTheme.titleSmall),
            Text('Durata: ${cycle.durationDays == 1 ? '1 giorno' : '${cycle.durationDays} giorni'}'),
            Text(_closing),
            if (!cycle.hasStarted)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit), label: const Text('Modifica')),
                    if (cycle.isOpen)
                      OutlinedButton.icon(
                        onPressed: () => _closeEarly(context, ref),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Chiudi le richieste'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
