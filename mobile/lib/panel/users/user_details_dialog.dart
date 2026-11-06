import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';
import 'user_actions.dart';
import 'users_notifier.dart';

const _goneMessage = 'Questo utente non esiste più: forse un altro admin l\'ha rimosso.';

/// A user's card: details, motivation and the actions the viewer may take.
/// The outcome of an action appears in the card, along with the user's new
/// state: the modal barrier hides a SnackBar from screen readers. A SnackBar is
/// only for when the card is gone: after a removal, which closes it, or if it
/// was closed meanwhile.
class UserDetailsDialog extends ConsumerStatefulWidget {
  final User user;
  final String groupLabel;

  /// Runs an action and reloads the list behind the card. Throws on failure.
  /// By default, that of the "Utenti" tab.
  final Future<void> Function(UserAction action, User user)? act;

  const UserDetailsDialog({super.key, required this.user, required this.groupLabel, this.act});

  @override
  ConsumerState<UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends ConsumerState<UserDetailsDialog> {
  late User _user = widget.user;
  bool _busy = false;
  String? _error;

  /// The last action that succeeded, as said to the viewer.
  String? _done;

  /// The user no longer exists, e.g. another admin removed them: no actions left.
  bool _gone = false;

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
      _done = null;
    });
    try {
      await (widget.act ?? ref.read(usersProvider.notifier).act)(action, _user);
      // The card may have been dismissed meanwhile: then there is nothing to update.
      if (!mounted || action == UserAction.remove) {
        messenger.showSnackBar(SnackBar(content: Text(action.done)));
        if (mounted) navigator.pop();
        return;
      }
      setState(() {
        _busy = false;
        _done = action.done;
        _user = action.applyTo(_user);
      });
    } catch (e) {
      final message = e is ApiException ? e.message : 'Si è verificato un errore. Riprova.';
      if (!mounted) {
        // After a 401 the session is over, and the login page says so.
        if (!(e is ApiException && e.statusCode == 401)) messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      // The action may have failed because the user changed meanwhile, e.g.
      // another admin suspended them.
      final current = e is ApiException && e.statusCode == 404 ? null : await _current();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _gone = current == null;
        _error = _gone ? _goneMessage : message;
        _user = current ?? _user;
      });
    }
  }

  /// [_user] as the backend has them now, or null if they no longer exist. The
  /// users list can't tell: they may be on another page or out of its filters.
  Future<User?> _current() async {
    try {
      return User.fromJson(await ref.read(panelApiClientProvider).get('/api/users/${_user.id}') as Map<String, dynamic>);
    } catch (e) {
      return e is ApiException && e.statusCode == 404 ? null : _user;
    }
  }

  Future<bool> _confirm(UserAction action, String question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          semanticLabel: question,
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
    final actions = viewer == null || _gone ? const <UserAction>[] : actionsFor(viewer, _user);
    final restriction = viewer == null || _gone ? null : restrictionFor(viewer, _user);
    final lastConfirmed = _user.lastConfirmedAt;
    // Confirmation rounds are for group members, admins excluded: for anyone else
    // the date would only repeat the registration or a reactivation.
    final confirms = _user.groupId != null && !_user.isAdmin;
    final createdAt = _user.createdAt;
    final motivation = _user.motivation?.trim() ?? '';

    return AlertDialog(
      semanticLabel: _name,
      title: Text(_name),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          // Plain Texts rather than SelectableText: on the web a screen reader
          // would find it an empty text field.
          // On the web the selection area holds a platform view with a focus of its
          // own: without the exclusion, an invisible stop of the Tab key.
          child: ExcludeFocusTraversal(
            child: SelectionArea(
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
                  if (confirms)
                    _Detail(label: 'Ultima conferma il', value: lastConfirmed == null ? 'Mai' : formatDate(lastConfirmed)),
                  const SizedBox(height: 16),
                  Semantics(header: true, child: Text('Motivazione', style: theme.textTheme.titleSmall)),
                  const SizedBox(height: 4),
                  Text(motivation.isEmpty ? 'Nessuna motivazione' : motivation),
                  if (restriction != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            restriction,
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null || _done != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? _done!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _error != null ? theme.colorScheme.error : theme.colorScheme.primary,
                        ),
                      ),
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
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
