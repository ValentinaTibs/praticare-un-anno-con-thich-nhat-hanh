import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../../core/services/push_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/token_storage.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

/// Where the sign-in flow has to go next after a Firebase / backend step.
enum AuthStep {
  /// Backend session created: the router redirect takes the user to /home.
  loggedIn,

  /// The Firebase email is not verified yet: show the verify-email screen.
  verifyEmail,

  /// Verified email unknown to the backend: show the register screen.
  register,
}

/// Raised for auth problems that are not a [fb.FirebaseAuthException] nor an
/// [ApiException] (Firebase not configured, no signed-in Firebase user).
class AuthFlowException implements Exception {
  final String message;
  AuthFlowException(this.message);

  @override
  String toString() => message;
}

/// Short Italian message for any error coming out of the auth flow.
String authErrorMessage(Object error) {
  if (error is fb.FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        'Email o password non corretti.',
      'email-already-in-use' => 'Esiste già un account con questa email.',
      'weak-password' => 'Password troppo debole: usa almeno 6 caratteri.',
      'invalid-email' => 'Indirizzo email non valido.',
      'too-many-requests' => 'Troppi tentativi. Riprova tra qualche minuto.',
      'user-disabled' => 'Questo account è stato disabilitato.',
      'network-request-failed' => 'Errore di rete. Controlla la connessione.',
      _ => 'Errore di autenticazione (${error.code}).',
    };
  }
  if (error is ApiException) {
    if (error.code == 'registrations_closed') {
      return 'Le iscrizioni sono chiuse in questo momento. Riprova quando si apre il prossimo ciclo.';
    }
    return error.contact != null ? '${error.message}\nContatto: ${error.contact}' : error.message;
  }
  if (error is AuthFlowException) return error.message;
  return 'Si è verificato un errore. Riprova.';
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
    final token = await _storage.getAccessToken();
    if (token == null) {
      state = const AuthState.unauth();
      return;
    }
    try {
      final data = await _api.get('/api/users/me');
      final user = User.fromJson(data as Map<String, dynamic>);
      _socket.connect(token);
      await _push.init();
      state = AuthState.authed(user);
    } catch (_) {
      await _storage.clear();
      state = const AuthState.unauth();
    }
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

  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _push.unregisterToken();
        await _api.post('/api/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    _socket.disconnect();
    await signOutFirebase();
    await _storage.clear();
    state = const AuthState.unauth();
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
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStorageProvider)));
final pushServiceProvider = Provider<PushService>((ref) => PushService(ref.watch(apiClientProvider)));

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(
      ref.watch(apiClientProvider),
      ref.watch(tokenStorageProvider),
      ref.watch(socketServiceProvider),
      ref.watch(pushServiceProvider),
    ));
