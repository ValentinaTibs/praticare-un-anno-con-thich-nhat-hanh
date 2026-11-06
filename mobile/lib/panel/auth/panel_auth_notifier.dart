import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_errors.dart';
import '../../core/models/user.dart';
import '../../core/storage/token_storage.dart';
import 'panel_firebase.dart';

enum PanelAuthStatus { loading, signedOut, signedIn, unavailable }

class PanelAuthState {
  final PanelAuthStatus status;
  final User? user;

  /// Why the session ended, shown on the login page (e.g. role not allowed).
  final String? message;

  const PanelAuthState._(this.status, {this.user, this.message});

  const PanelAuthState.loading() : this._(PanelAuthStatus.loading);
  const PanelAuthState.signedOut([String? message]) : this._(PanelAuthStatus.signedOut, message: message);
  const PanelAuthState.signedIn(User user) : this._(PanelAuthStatus.signedIn, user: user);

  /// The stored session could not be checked: the server did not answer.
  const PanelAuthState.unavailable() : this._(PanelAuthStatus.unavailable);
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
  bool _recheckingSession = false;

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
    } catch (e) {
      // A refused refresh has already ended the session, with its message.
      if (state.status != PanelAuthStatus.loading) return;
      if (e is ApiException && e.isTemporary) {
        // The session may well be good: keep it for when the server answers.
        state = const PanelAuthState.unavailable();
      } else {
        // E.g. an admin suspended since the last visit.
        await _endSession(e is ApiException && e.statusCode == 403 ? e.message : null);
      }
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

  /// Checks the stored session again.
  Future<void> retry() async {
    state = const PanelAuthState.loading();
    await _restoreSession();
  }

  /// The backend refused the refresh token and the tokens are gone.
  void sessionExpired() {
    if (state.status != PanelAuthStatus.signedOut) state = const PanelAuthState.signedOut(sessionExpiredMessage);
  }

  /// A request got a 403, which may be about that request only (e.g. a user who
  /// can't be touched) or about the viewer: the backend says which on
  /// /api/users/me. A suspended or banned admin gets a 403 there too; a demoted
  /// one no longer has an admin role.
  Future<void> recheckSession() async {
    if (_recheckingSession || state.status != PanelAuthStatus.signedIn) return;
    _recheckingSession = true;
    try {
      final user = User.fromJson(await _api.get('/api/users/me') as Map<String, dynamic>);
      if (!user.isAdmin) {
        await _endSession(notAdminMessage);
      } else if (user.role != state.user?.role) {
        state = PanelAuthState.signedIn(user);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 403) await _endSession(e.message);
    } finally {
      _recheckingSession = false;
    }
  }

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

/// The HTTP transport of the panel, replaced in tests.
final panelHttpAdapterProvider = Provider<HttpClientAdapter?>((_) => null);

final panelApiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      ref.watch(panelTokenStorageProvider),
      adapter: ref.watch(panelHttpAdapterProvider),
      onSessionExpired: () => ref.read(panelAuthProvider.notifier).sessionExpired(),
      onForbidden: () => ref.read(panelAuthProvider.notifier).recheckSession(),
    ));
final panelFirebaseProvider = Provider<PanelFirebase>((_) => FirebasePanelAuth());

final StateNotifierProvider<PanelAuthNotifier, PanelAuthState> panelAuthProvider =
    StateNotifierProvider<PanelAuthNotifier, PanelAuthState>((ref) => PanelAuthNotifier(
      ref.watch(panelApiClientProvider),
      ref.watch(panelTokenStorageProvider),
      ref.watch(panelFirebaseProvider),
    ));
