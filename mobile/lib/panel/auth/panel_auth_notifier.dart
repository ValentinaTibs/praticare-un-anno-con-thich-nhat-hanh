import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_errors.dart';
import '../../core/models/user.dart';
import '../../core/storage/token_storage.dart';
import 'panel_firebase.dart';

enum PanelAuthStatus { loading, signedOut, signedIn }

class PanelAuthState {
  final PanelAuthStatus status;
  final User? user;

  /// Why the session ended, shown on the login page (e.g. role not allowed).
  final String? message;

  const PanelAuthState._(this.status, {this.user, this.message});

  const PanelAuthState.loading() : this._(PanelAuthStatus.loading);
  const PanelAuthState.signedOut([String? message]) : this._(PanelAuthStatus.signedOut, message: message);
  const PanelAuthState.signedIn(User user) : this._(PanelAuthStatus.signedIn, user: user);
}

const notAdminMessage = 'Il pannello è riservato agli amministratori.';
const emailNotVerifiedMessage =
    'Conferma la tua email con il link che hai ricevuto, poi accedi di nuovo.';

/// Session of the admin panel. Only admin and super_admin users get in: any
/// other session is closed right away, on the backend too.
class PanelAuthNotifier extends StateNotifier<PanelAuthState> {
  final ApiClient _api;
  final TokenStorage _storage;
  final PanelFirebase _firebase;

  PanelAuthNotifier(this._api, this._storage, this._firebase) : super(const PanelAuthState.loading()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (await _storage.getAccessToken() == null) {
      state = const PanelAuthState.signedOut();
      return;
    }
    final User user;
    try {
      user = User.fromJson(await _api.get('/api/users/me') as Map<String, dynamic>);
    } catch (_) {
      await _storage.clear();
      state = const PanelAuthState.signedOut();
      return;
    }
    if (user.isAdmin) {
      state = PanelAuthState.signedIn(user);
    } else {
      // E.g. an admin demoted since the last visit.
      await _endSession(notAdminMessage);
    }
  }

  /// Email and password login on Firebase, then exchange of the Firebase token
  /// for the backend's own tokens. Throws with an Italian message on failure:
  /// see [authErrorMessage].
  Future<void> signIn(String email, String password) async {
    try {
      final idToken = await _firebase.signIn(email, password);
      if (idToken == null) throw AuthFlowException(emailNotVerifiedMessage);
      final Map<String, dynamic> result;
      try {
        result = await _api.post('/api/auth/verify-firebase', data: {'idToken': idToken}) as Map<String, dynamic>;
      } on ApiException catch (e) {
        if (e.code == 'email_not_verified') throw AuthFlowException(emailNotVerifiedMessage);
        rethrow;
      }
      await _startSession(result);
    } finally {
      // The panel keeps only the backend session.
      await _firebase.signOut();
    }
  }

  /// Development-only login without Firebase (see PanelConfig.devLogin).
  Future<void> devLogin(String email) async {
    final result = await _api.post('/api/auth/dev-login', data: {'email': email}) as Map<String, dynamic>;
    await _startSession(result);
  }

  Future<void> sendPasswordReset(String email) => _firebase.sendPasswordReset(email);

  Future<void> logout() => _endSession();

  Future<void> _startSession(Map<String, dynamic> result) async {
    // 'register': a verified email with no account on the backend.
    if (result['status'] != 'ok') throw AuthFlowException(notAdminMessage);
    await _storage.saveTokens(
      access: result['accessToken'] as String,
      refresh: result['refreshToken'] as String,
    );
    final user = User.fromJson(result['user'] as Map<String, dynamic>);
    if (!user.isAdmin) {
      await _endSession(notAdminMessage);
      throw AuthFlowException(notAdminMessage);
    }
    state = PanelAuthState.signedIn(user);
  }

  /// Revokes the refresh token on the backend and clears the stored tokens.
  Future<void> _endSession([String? message]) async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.post('/api/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await _storage.clear();
    state = PanelAuthState.signedOut(message);
  }
}

// ── Providers ──────────────────────────────────────────────────────────────────

final panelTokenStorageProvider = Provider<TokenStorage>((_) => TokenStorage());
final panelApiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(panelTokenStorageProvider)));
final panelFirebaseProvider = Provider<PanelFirebase>((_) => FirebasePanelAuth());

final panelAuthProvider = StateNotifierProvider<PanelAuthNotifier, PanelAuthState>((ref) => PanelAuthNotifier(
      ref.watch(panelApiClientProvider),
      ref.watch(panelTokenStorageProvider),
      ref.watch(panelFirebaseProvider),
    ));
