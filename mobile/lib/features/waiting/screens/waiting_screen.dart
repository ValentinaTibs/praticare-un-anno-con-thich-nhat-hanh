import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/widgets/error_retry.dart';
import '../../auth/auth_notifier.dart';
import '../next_journey.dart';

// Fixed until the Super Admin can edit it from the panel (#34).
const _closedMessage = 'Le richieste di partecipazione sono chiuse.';
const _removedMessage = 'Potrai chiedere di partecipare dal prossimo percorso.';

String _date(DateTime date) => DateFormat('d MMMM y').format(date.toLocal());

String _requestersLabel(int count) => switch (count) {
      0 => 'Nessuno ha ancora chiesto di partecipare al prossimo percorso.',
      1 => '1 persona ha chiesto di partecipare al prossimo percorso.',
      _ => '$count persone hanno chiesto di partecipare al prossimo percorso.',
    };

/// The only screen of a user outside any active group, besides the profile.
class WaitingScreen extends ConsumerStatefulWidget {
  const WaitingScreen({super.key});

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen> {
  bool _busy = false;

  Future<void> _reload() async {
    await ref.read(authProvider.notifier).refreshUser();
    if (!mounted) return;
    ref.invalidate(nextJourneyProvider);
    try {
      await ref.read(nextJourneyProvider.future);
    } catch (_) {
      // The screen shows the error.
    }
  }

  Future<void> _write(Future<void> Function() request) async {
    setState(() => _busy = true);
    try {
      await request();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Si è verificato un errore. Riprova.')),
        );
      }
    }
    // After a refusal too: the cycle may have closed meanwhile.
    if (mounted) await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _ask() => _write(() => ref.read(apiClientProvider).post('/api/cycles/requests'));

  Future<void> _cancel(NextJourney journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Annullare la richiesta?'),
        content: Text(
          journey.open
              ? 'Potrai chiedere di nuovo di partecipare finché le richieste sono aperte.'
              : 'Le richieste sono chiuse: non potrai più chiedere di partecipare a questo percorso.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Indietro')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Annulla la richiesta')),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _write(() => ref.read(apiClientProvider).delete('/api/cycles/requests/mine'));
    }
  }

  String _status(NextJourney journey) {
    final startsAt = journey.startsAt;
    if (startsAt == null) return _closedMessage;
    final date = _date(startsAt);
    if (journey.requested) return 'Hai chiesto di partecipare al percorso che inizia il $date.';
    if (journey.open) {
      return journey.canRequest ? 'Sono aperte le richieste per il percorso che inizia il $date.' : _removedMessage;
    }
    return '$_closedMessage Il prossimo percorso inizia il $date.';
  }

  @override
  Widget build(BuildContext context) {
    final journey = ref.watch(nextJourneyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Semantics(
              header: true,
              child: Text('In attesa', style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 16),
            journey.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                message: e is ApiException ? e.message : 'Impossibile caricare il prossimo percorso.',
                onRetry: _reload,
              ),
              data: _content,
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(NextJourney journey) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(liveRegion: true, child: Text(_status(journey), style: theme.textTheme.bodyLarge)),
        if (journey.startsAt != null) ...[
          const SizedBox(height: 12),
          Text(_requestersLabel(journey.requesters), style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        if (journey.requested)
          OutlinedButton(
            onPressed: _busy ? null : () => _cancel(journey),
            child: const Text('Annulla la richiesta'),
          )
        else
          FilledButton(
            onPressed: _busy || !journey.canRequest ? null : _ask,
            child: const Text('Chiedi di partecipare'),
          ),
      ],
    );
  }
}
