import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../../core/services/push_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/token_storage.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

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

  AuthNotifier(this._api, this._storage, this._socket, this._push)
      : super(const AuthState.loading()) {
    _restoreSession();
  }

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

  Future<void> sendOtp(String phoneNumber) async {
    await _api.post('/api/auth/send-otp', data: {'phoneNumber': phoneNumber});
  }

  /// Returns 'ok' if logged in, 'register' if the phone is new.
  Future<String> verifyOtp(String phoneNumber, String code) async {
    final data = await _api.post('/api/auth/verify-otp', data: {
      'phoneNumber': phoneNumber,
      'code': code,
    });
    final result = data as Map<String, dynamic>;
    if (result['status'] == 'ok') {
      await _storage.saveTokens(
        access: result['accessToken'] as String,
        refresh: result['refreshToken'] as String,
      );
      final user = User.fromJson(result['user'] as Map<String, dynamic>);
      _socket.connect(result['accessToken'] as String);
      await _push.init();
      state = AuthState.authed(user);
    }
    return result['status'] as String;
  }

  Future<void> register({
    required String phoneNumber,
    required String code,
    required String name,
    required String surname,
    required String motivation,
  }) async {
    final data = await _api.post('/api/auth/register', data: {
      'phoneNumber': phoneNumber,
      'code': code,
      'name': name,
      'surname': surname,
      'motivation': motivation,
    });
    final result = data as Map<String, dynamic>;
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
