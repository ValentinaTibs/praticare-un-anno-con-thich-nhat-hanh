import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_errors.dart';
import '../../core/models/user.dart';
import '../../core/services/push_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/token_storage.dart';

export '../../core/auth/auth_errors.dart';

enum AuthStatus { loading, unauthenticated, authenticated, unavailable }

/// Where the sign-in flow has to go next after a Firebase / backend step.
enum AuthStep {
  /// Backend session created: the router redirect takes the user to /home.
  loggedIn,

  /// The Firebase email is not verified yet: show the verify-email screen.
  verifyEmail,

  /// Verified email unknown to the backend: show the register screen.
  register,
}

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? error;

  const AuthState({required this.status, this.user, this.error});

  const AuthState.loading() : this(status: AuthStatus.loading);
  const AuthState.unauth() : this(status: AuthStatus.unauthenticated);
  AuthState.authed(User user) : this(status: AuthStatus.authenticated, user: user);
  AuthState.err(String msg) : this(status: AuthStatus.unauthenticated, error: msg);

  /// The stored session could not be checked: the server did not answer.
  const AuthState.unavailable() : this(status: AuthStatus.unavailable);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final TokenStorage _storage;
  final SocketService _socket;
  final PushService _push;

  AuthNotifier(this._api, this._storage, this._socket, this._push) : super(const AuthState.loading()) {
    _restoreSession();
  }

  /// FirebaseAuth is resolved lazily: the app still starts when Firebase has
  /// not been configured, only login is unavailable.
  fb.FirebaseAuth get _firebase {
    if (Firebase.apps.isEmpty) {
      throw AuthFlowException('Accesso non disponibile: Firebase non è configurato.');
    }
    return fb.FirebaseAuth.instance;
  }

  fb.User get _currentFirebaseUser {
    final user = _firebase.currentUser;
    if (user == null) {
      throw AuthFlowException('Sessione scaduta: accedi di nuovo.');
    }
    return user;
  }

  /// Email of the signed-in Firebase user, if any.
  String? get firebaseEmail => Firebase.apps.isEmpty ? null : fb.FirebaseAuth.instance.currentUser?.email;

  Future<void> _restoreSession() async {
    if (await _storage.getAccessToken() == null) {
      state = const AuthState.unauth();
      return;
    }
    final User user;
    try {
      user = User.fromJson(await _api.get('/api/users/me') as Map<String, dynamic>);
    } catch (e) {
      // A refused refresh has already ended the session, with its message.
      if (state.status != AuthStatus.loading) return;
      if (e is ApiException && e.isTemporary) {
        // The session may well be good: keep it for when the server answers.
        state = const AuthState.unavailable();
      } else {
        // E.g. a user suspended since the last visit.
        await _endSession(e is ApiException && e.statusCode == 403 ? authErrorMessage(e) : null);
      }
      return;
    }
    // Read only now: the request above may have refreshed the token.
    final token = await _storage.getAccessToken();
    if (token != null) _socket.connect(token);
    try {
      await _push.init();
    } catch (_) {
      // Missing notifications are no reason to lose the session.
    }
    state = AuthState.authed(user);
  }

  /// Checks the stored session again.
  Future<void> retry() async {
    state = const AuthState.loading();
    await _restoreSession();
  }

  /// Email + password sign-in on Firebase, then session exchange with the backend.
  Future<AuthStep> signIn(String email, String password) async {
    final cred = await _firebase.signInWithEmailAndPassword(email: email, password: password);
    final user = cred.user;
    if (user == null) throw AuthFlowException('Accesso non riuscito. Riprova.');
    if (!user.emailVerified) return AuthStep.verifyEmail;
    return _exchangeFirebaseToken(user);
  }

  /// Creates the Firebase account and sends the verification email.
  Future<void> signUp(String email, String password) async {
    final cred = await _firebase.createUserWithEmailAndPassword(email: email, password: password);
    await cred.user?.sendEmailVerification();
  }

  Future<void> resendVerificationEmail() async {
    await _currentFirebaseUser.sendEmailVerification();
  }

  /// Called after the user says they clicked the verification link.
  Future<AuthStep> continueAfterVerification() async {
    final user = _currentFirebaseUser;
    await user.reload();
    final refreshed = _firebase.currentUser ?? user;
    if (!refreshed.emailVerified) return AuthStep.verifyEmail;
    return _exchangeFirebaseToken(refreshed);
  }

  Future<void> sendPasswordReset(String email) async {
    await _firebase.sendPasswordResetEmail(email: email);
  }

  /// Signs out of Firebase only (no backend session exists yet).
  Future<void> signOutFirebase() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  /// Always forces a refresh so the token carries the current email_verified claim.
  Future<String> _freshIdToken(fb.User user) async {
    final idToken = await user.getIdToken(true);
    if (idToken == null) throw AuthFlowException('Sessione scaduta: accedi di nuovo.');
    return idToken;
  }

  Future<AuthStep> _exchangeFirebaseToken(fb.User user) async {
    final idToken = await _freshIdToken(user);
    try {
      final data = await _api.post('/api/auth/verify-firebase', data: {'idToken': idToken});
      final result = data as Map<String, dynamic>;
      if (result['status'] == 'register') return AuthStep.register;
      await _startSession(result);
      return AuthStep.loggedIn;
    } on ApiException catch (e) {
      if (e.code == 'email_not_verified') return AuthStep.verifyEmail;
      rethrow;
    }
  }

  /// Registers the verified Firebase user with the backend, using a fresh ID token.
  Future<AuthStep> register({
    required String name,
    required String surname,
    required String motivation,
  }) async {
    final idToken = await _freshIdToken(_currentFirebaseUser);
    try {
      final data = await _api.post('/api/auth/register', data: {
        'idToken': idToken,
        'name': name,
        'surname': surname,
        'motivation': motivation,
      });
      await _startSession(data as Map<String, dynamic>);
      return AuthStep.loggedIn;
    } on ApiException catch (e) {
      if (e.code == 'email_not_verified') return AuthStep.verifyEmail;
      rethrow;
    }
  }

  Future<void> _startSession(Map<String, dynamic> result) async {
    await _storage.saveTokens(
      access: result['accessToken'] as String,
      refresh: result['refreshToken'] as String,
    );
    final user = User.fromJson(result['user'] as Map<String, dynamic>);
    _socket.connect(result['accessToken'] as String);
    await _push.init();
    state = AuthState.authed(user);
  }

  Future<void> logout() => _endSession();

  /// The backend refused the refresh token and the tokens are gone.
  void sessionExpired() {
    if (state.status == AuthStatus.unauthenticated) return;
    _socket.disconnect();
    signOutFirebase();
    state = AuthState.err(sessionExpiredMessage);
  }

  /// Revokes the refresh token on the backend, as far as possible, and clears
  /// the session here. [error] is shown on the login screen.
  Future<void> _endSession([String? error]) async {
    try {
      await _push.unregisterToken();
    } catch (_) {}
    // Read only now: the request above may have rotated the refresh token.
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.post('/api/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    _socket.disconnect();
    await signOutFirebase();
    await _storage.clear();
    state = error == null ? const AuthState.unauth() : AuthState.err(error);
  }

  /// Reads the user again: a group may have started or ended meanwhile. The state
  /// changes only if the group did, because the router restarts when it changes.
  Future<void> refreshUser() async {
    try {
      final user = User.fromJson(await _api.get('/api/users/me') as Map<String, dynamic>);
      final current = state.user;
      if (state.status != AuthStatus.authenticated || current == null) return;
      if (user.groupId != current.groupId || user.groupEndedAt != current.groupEndedAt) {
        state = AuthState.authed(user);
      }
    } on ApiException catch (e) {
      // Suspended or banned meanwhile. Anything else can wait for the next try.
      if (e.statusCode == 403 && state.status == AuthStatus.authenticated) await _endSession(authErrorMessage(e));
    } catch (_) {}
  }

  Future<void> confirm() async {
    await _api.post('/api/confirmations/confirm');
    final data = await _api.get('/api/users/me');
    state = AuthState.authed(User.fromJson(data as Map<String, dynamic>));
  }
}

// ── Providers ──────────────────────────────────────────────────────────────────

final tokenStorageProvider = Provider<TokenStorage>((_) => TokenStorage());
final socketServiceProvider = Provider<SocketService>((_) => SocketService());

/// The HTTP transport of the app, replaced in tests.
final httpAdapterProvider = Provider<HttpClientAdapter?>((_) => null);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      ref.watch(tokenStorageProvider),
      adapter: ref.watch(httpAdapterProvider),
      onSessionExpired: () => ref.read(authProvider.notifier).sessionExpired(),
    ));
final pushServiceProvider = Provider<PushService>((ref) => PushService(ref.watch(apiClientProvider)));

final StateNotifierProvider<AuthNotifier, AuthState> authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(
      ref.watch(apiClientProvider),
      ref.watch(tokenStorageProvider),
      ref.watch(socketServiceProvider),
      ref.watch(pushServiceProvider),
    ));
