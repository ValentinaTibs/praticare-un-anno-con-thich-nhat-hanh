import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/storage/token_storage.dart';
import 'package:community_app/panel/auth/panel_firebase.dart';

Map<String, dynamic> userJson(String role) => {
      'id': 'u-$role',
      'name': 'Giulia',
      'surname': 'Rossi',
      'email': '$role@prova.local',
      'role': role,
      'status': 'active',
    };

Map<String, dynamic> sessionJson(String role) => {
      'status': 'ok',
      'accessToken': 'access-$role',
      'refreshToken': 'refresh-$role',
      'user': userJson(role),
    };

/// In-memory backend: answers are set per path, calls are recorded.
class FakeApiClient implements ApiClient {
  final Map<String, Object> responses;
  final List<String> calls = [];

  FakeApiClient(this.responses);

  dynamic _answer(String method, String path) {
    calls.add('$method $path');
    final r = responses[path];
    if (r == null) throw ApiException(statusCode: 404, message: 'Non trovato');
    if (r is ApiException) throw r;
    return r;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => _answer('GET', path);

  @override
  Future<dynamic> post(String path, {dynamic data}) async => _answer('POST', path);

  @override
  Future<dynamic> patch(String path, {dynamic data}) async => _answer('PATCH', path);

  @override
  Future<dynamic> delete(String path, {dynamic data}) async => _answer('DELETE', path);
}

class FakeTokenStorage implements TokenStorage {
  String? access;
  String? refresh;

  FakeTokenStorage({this.access, this.refresh});

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class FakePanelFirebase implements PanelFirebase {
  /// Token returned by [signIn]; null means email not verified.
  String? idToken;
  bool signedOut = false;

  FakePanelFirebase({this.idToken = 'firebase-token'});

  @override
  Future<String?> signIn(String email, String password) async => idToken;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => signedOut = true;
}
