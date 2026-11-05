import '../../core/api/api_client.dart';
import '../../core/models/user.dart';

/// What an admin can do to an account from its card in the panel.
enum UserAction {
  review(label: 'Segna come revisionato', done: 'Utente revisionato'),
  reactivate(label: 'Riattiva', done: 'Utente riattivato'),
  suspend(label: 'Sospendi', done: 'Utente sospeso'),
  ban(label: 'Banna', done: 'Utente bannato'),
  unban(label: 'Revoca il ban', done: 'Ban revocato'),
  remove(label: 'Rimuovi', done: 'Utente rimosso');

  final String label;

  /// Confirmation shown once the action succeeded.
  final String done;

  const UserAction({required this.label, required this.done});

  /// Bans and removals can't be undone by an admin: they get a warning colour.
  bool get destructive => this == UserAction.ban || this == UserAction.remove;

  /// The question asked before acting on [name], or null when no confirmation is needed.
  String? question(String name) => switch (this) {
        UserAction.suspend => 'Sospendere $name?',
        UserAction.ban => 'Bannare $name?',
        UserAction.unban => 'Revocare il ban a $name?',
        UserAction.remove => 'Rimuovere $name?',
        _ => null,
      };

  /// [user] as the backend leaves them once the action succeeded.
  User applyTo(User user) => switch (this) {
        UserAction.review => user.copyWith(reviewedByAdmin: true),
        // The backend counts reactivating as a confirmation.
        UserAction.reactivate || UserAction.unban => user.copyWith(status: 'active', lastConfirmedAt: DateTime.now()),
        UserAction.suspend => user.copyWith(status: 'suspended'),
        UserAction.ban => user.copyWith(status: 'banned'),
        UserAction.remove => user,
      };

  /// What follows from the action, shown under [question].
  String get consequence => switch (this) {
        UserAction.suspend => 'Non potrà usare l\'app finché un admin non lo riattiva.',
        UserAction.ban =>
          'L\'account resta bloccato e la sua email non potrà più registrarsi. Solo il Super Admin può revocare il ban.',
        UserAction.unban => 'Tornerà attivo e la sua email sarà sbloccata.',
        UserAction.remove => 'L\'account e tutti i suoi dati verranno eliminati. L\'operazione non si può annullare.',
        _ => '',
      };

  Future<void> run(ApiClient api, String userId) => this == UserAction.remove
      ? api.delete('/api/admin/$userId')
      : api.patch('/api/admin/$userId/$name');
}

int _rank(String role) => switch (role) {
      'super_admin' => 2,
      'admin' => 1,
      _ => 0,
    };

/// The backend lets an admin suspend, ban or remove only users of lower rank: an
/// admin plain users, the Super Admin also admins. Never oneself or the Super Admin.
bool _outranks(User viewer, User target) => _rank(viewer.role) > _rank(target.role);

/// The actions [viewer] may take on [target] in its current state.
List<UserAction> actionsFor(User viewer, User target) {
  final canAct = _outranks(viewer, target);
  return [
    // Reviewing is harmless and final: any admin reviews anyone but themselves.
    if (!target.reviewedByAdmin && viewer.id != target.id) UserAction.review,
    // Any admin reactivates anyone, admins and the Super Admin included: whoever is
    // suspended can't do it themselves.
    if (target.isSuspended && viewer.id != target.id) UserAction.reactivate,
    if (canAct && target.isActive) UserAction.suspend,
    if (canAct && !target.isBanned) UserAction.ban,
    if (canAct && target.isBanned && viewer.isSuperAdmin) UserAction.unban,
    if (canAct && !target.isBanned) UserAction.remove,
  ];
}

/// Why [viewer] can't suspend, ban or remove [target], or null when they can.
String? restrictionFor(User viewer, User target) {
  if (viewer.id == target.id) return 'Questo è il tuo account.';
  if (target.isSuperAdmin) return 'Nessuno può sospendere, bannare o rimuovere il Super Admin.';
  if (!_outranks(viewer, target)) return 'Solo il Super Admin può sospendere, bannare o rimuovere un admin.';
  return null;
}
