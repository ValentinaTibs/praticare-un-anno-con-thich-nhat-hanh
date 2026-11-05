import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';
import 'user_actions.dart';
import 'users_notifier.dart';

/// A user's card: details, motivation and the actions the viewer may take.
/// A successful action closes the card and is confirmed on the page; a failed
/// one shows the backend's message in the card.
class UserDetailsDialog extends ConsumerStatefulWidget {
  final User user;
  final String groupLabel;

  const UserDetailsDialog({super.key, required this.user, required this.groupLabel});

  @override
  ConsumerState<UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends ConsumerState<UserDetailsDialog> {
  bool _busy = false;
  String? _error;

  User get _user => widget.user;
  String get _name => '${_user.name} ${_user.surname}';

  Future<void> _run(UserAction action) async {
    final question = action.question(_name);
    if (question != null && !await _confirm(action, question)) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(usersProvider.notifier).act(action, _user);
      // The card may have been dismissed meanwhile: then there is nothing to close.
      if (mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(action.done)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : 'Si è verificato un errore. Riprova.';
      });
    }
  }

  Future<bool> _confirm(UserAction action, String question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(question),
          content: Text(action.consequence),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            FilledButton(
              style: action.destructive
                  ? FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action.label),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewer = ref.watch(panelAuthProvider).user;
    final actions = viewer == null ? const <UserAction>[] : actionsFor(viewer, _user);
    final restriction = viewer == null ? null : restrictionFor(viewer, _user);
    final lastConfirmed = _user.lastConfirmedAt;
    final createdAt = _user.createdAt;
    final motivation = _user.motivation?.trim() ?? '';

    return AlertDialog(
      title: Text(_name),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Detail(label: 'Email', value: _user.email ?? '—'),
              _Detail(label: 'Ruolo', value: _user.roleLabel),
              _Detail(label: 'Stato', value: _user.statusLabel),
              _Detail(label: 'Gruppo', value: widget.groupLabel),
              _Detail(label: 'Revisione', value: _user.reviewedByAdmin ? 'Revisionato' : 'Da revisionare'),
              if (createdAt != null) _Detail(label: 'Registrato il', value: formatDate(createdAt)),
              _Detail(label: 'Ultima conferma il', value: lastConfirmed == null ? 'Mai' : formatDate(lastConfirmed)),
              const SizedBox(height: 16),
              Semantics(header: true, child: Text('Motivazione', style: theme.textTheme.titleSmall)),
              const SizedBox(height: 4),
              SelectableText(motivation.isEmpty ? 'Nessuna motivazione' : motivation),
              if (restriction != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(restriction, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        for (final action in actions)
          action.destructive
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: _busy ? null : () => _run(action),
                  child: Text(action.label),
                )
              : OutlinedButton(onPressed: _busy ? null : () => _run(action), child: Text(action.label)),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Chiudi')),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
