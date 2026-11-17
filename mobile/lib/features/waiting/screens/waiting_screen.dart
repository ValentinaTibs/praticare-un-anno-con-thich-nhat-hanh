import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/theme/lanterna_theme.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/lanterna_marks.dart';
import '../../auth/auth_notifier.dart';
import '../../daily_quote/daily_quote.dart';
import '../next_journey.dart';

const _gutter = 24.0;

// Fixed until the Super Admin can edit it from the panel (#34).
const _closedMessage = 'Le richieste di partecipazione sono chiuse.';
const _removedMessage = 'Potrai chiedere di partecipare dal prossimo percorso.';
const _requestedMessage = 'La tua richiesta è arrivata. Un admin la leggerà.';

String _requestersLabel(int count) => switch (count) {
      0 => 'Nessuno ha ancora chiesto di partecipare.',
      1 => '1 persona ha chiesto di partecipare.',
      _ => '$count persone hanno chiesto di partecipare.',
    };

/// "Martedì 17 novembre".
String _today() {
  final text = DateFormat('EEEE d MMMM').format(DateTime.now());
  return text[0].toUpperCase() + text.substring(1);
}

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

  @override
  Widget build(BuildContext context) {
    final journey = ref.watch(nextJourneyProvider);
    final quote = ref.watch(dailyQuoteProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, _gutter),
                sliver: SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: const Text(
                                AppConstants.appName,
                                style: TextStyle(fontFamily: LanternaFonts.serif, fontSize: 17, color: LanternaColors.text),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => context.go('/home/profile'),
                            tooltip: 'Profilo',
                            icon: const Icon(Icons.person_outline, color: LanternaColors.muted),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Lantern(),
                                const SizedBox(height: 18),
                                Text(_today(), style: LanternaText.caption),
                                if (quote != null) ...[
                                  const SizedBox(height: 22),
                                  DailyQuoteText(quote, style: LanternaText.quoteLarge),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: LanternaColors.surface, borderRadius: BorderRadius.circular(20)),
                        child: journey.when(
                          skipLoadingOnRefresh: true,
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => ErrorRetry(
                            message: e is ApiException ? e.message : 'Impossibile caricare il prossimo percorso.',
                            onRetry: _reload,
                          ),
                          data: _nextJourney,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The "Prossimo percorso" box: start date, requests so far and the button.
  Widget _nextJourney(NextJourney journey) {
    final theme = Theme.of(context);
    final startsAt = journey.startsAt;
    final closeAt = journey.requestsCloseAt;
    final requesters = startsAt == null
        ? null
        : [
            _requestersLabel(journey.requesters),
            if (journey.open && journey.canRequest && !journey.requested && closeAt != null)
              'Richieste aperte fino al ${DateFormat('d MMMM').format(closeAt.toLocal())}.',
          ].join(' ');
    final status = switch (journey) {
      NextJourney(requested: true) => _requestedMessage,
      NextJourney(startsAt: null) || NextJourney(open: false) => _closedMessage,
      NextJourney(canRequest: false) => _removedMessage,
      _ => null,
    };
    final muted = theme.textTheme.bodyMedium?.copyWith(color: LanternaColors.muted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Prossimo percorso', style: theme.textTheme.titleMedium)),
        if (startsAt != null) ...[
          const SizedBox(height: 4),
          Text(
            DateFormat('d MMMM y').format(startsAt.toLocal()),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LanternaColors.accent),
          ),
        ],
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (requesters != null) Text(requesters, style: muted),
              if (requesters != null && status != null) const SizedBox(height: 8),
              if (status != null) Text(status, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 20),
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
