import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../../core/widgets/error_retry.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';
import '../users/user_actions.dart';
import '../users/user_details_dialog.dart';
import '../users/users_notifier.dart';
import '../users/users_tab.dart';
import 'requesters.dart';

final _waitingUsersProvider = StateNotifierProvider.autoDispose<UsersNotifier, UsersState>((ref) => UsersNotifier(
      ref.watch(panelApiClientProvider),
      filters: const UserFilters(onlyWaiting: true),
    ));

/// "In attesa" section: who asked to join the next journey and every waiting user.
class WaitingPage extends ConsumerWidget {
  const WaitingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Both lists live as long as the page, not as long as the tab showing them.
    ref.watch(_waitingUsersProvider.notifier);
    ref.listen(requestedJourneysProvider, (_, __) {});

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('In attesa', style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 12),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'Richiedenti'), Tab(text: 'Utenti in attesa')],
            ),
            const Expanded(child: TabBarView(children: [_RequestersTab(), _WaitingUsersTab()])),
          ],
        ),
      ),
    );
  }
}

/// A person of this section, whose card acts as in the users list and then
/// updates both tabs: a user may be in both.
class _PersonCard extends ConsumerWidget {
  final User user;

  const _PersonCard({required this.user});

  // Through the container: the card outlives this row, which a reload can replace.
  Future<void> _act(ProviderContainer container, UserAction action, User target) async {
    try {
      await action.run(container.read(panelApiClientProvider), target.id);
    } finally {
      container.invalidate(requestedJourneysProvider);
      await container.read(_waitingUsersProvider.notifier).retry();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = '${user.name} ${user.surname}';
    final motivation = user.motivation?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      if (!user.reviewedByAdmin) const ToReviewBadge(),
                      if (!user.isActive) Text(user.statusLabel, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ),
                  Text(user.email ?? '—', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(motivation.isEmpty ? 'Nessuna motivazione' : motivation),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Apri la scheda di $name',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UserDetailsDialog(
                  user: user,
                  groupLabel: 'In attesa',
                  act: (action, target) => _act(ProviderScope.containerOf(context, listen: false), action, target),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestersTab extends ConsumerWidget {
  const _RequestersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(requestedJourneysProvider).when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            message: e is ApiException ? e.message : 'Impossibile caricare i richiedenti.',
            onRetry: () => ref.invalidate(requestedJourneysProvider),
          ),
          data: (journeys) => journeys.isEmpty
              ? const Center(child: Text('Nessun percorso in programma'))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  children: [for (final j in journeys) _Journey(journey: j)],
                ),
        );
  }
}

class _Journey extends StatelessWidget {
  final RequestedJourney journey;

  const _Journey({required this.journey});

  String get _requests {
    final closes = journey.scheduledClosedAt;
    if (!journey.open) return 'Richieste chiuse';
    return closes == null ? 'Richieste aperte' : 'Richieste aperte fino al ${formatDateTime(closes)}';
  }

  String get _count {
    final total = journey.requesters.length;
    final requesters = total == 1 ? '1 richiedente' : '$total richiedenti';
    return journey.toReview == 0 ? requesters : '$requesters · ${journey.toReview} da revisionare';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Percorso dal ${formatDate(journey.startsAt)}', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 4),
              Text(_requests, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(_count, style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              if (journey.requesters.isEmpty) const Text('Nessuna richiesta'),
              for (final u in journey.requesters) _PersonCard(user: u),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingUsersTab extends ConsumerWidget {
  const _WaitingUsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_waitingUsersProvider);
    final notifier = ref.read(_waitingUsersProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            state.loading || state.error != null
                ? ''
                : state.total == 1
                    ? '1 utente in attesa'
                    : '${state.total} utenti in attesa',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body(state, notifier)),
        if (state.pageCount > 1 && state.error == null) UsersPagination(state: state, onPage: notifier.goToPage),
      ],
    );
  }

  Widget _body(UsersState state, UsersNotifier notifier) {
    if (state.error != null) return ErrorRetry(message: state.error!, onRetry: notifier.retry);
    if (state.users.isEmpty) {
      return state.loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Nessun utente in attesa'));
    }
    return ListView(
      children: [
        for (final u in state.users)
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _PersonCard(user: u)),
          ),
      ],
    );
  }
}
