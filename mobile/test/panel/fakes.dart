import 'dart:convert';
import 'dart:typed_data';

import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/storage/token_storage.dart';
import 'package:community_app/panel/auth/panel_firebase.dart';
import 'package:dio/dio.dart';

Map<String, dynamic> userJson(String role) => {
      'id': 'u-$role',
      'name': 'Giulia',
      'surname': 'Rossi',
      'email': '$role@prova.local',
      'role': role,
      'status': 'active',
    };

/// A user as GET /api/users lists it.
Map<String, dynamic> listedUserJson(
  String id, {
  String name = 'Anna',
  String surname = 'Bianchi',
  String role = 'user',
  String status = 'active',
  bool reviewed = true,
  String? groupId,
  String motivation = 'Voglio praticare con costanza.',
}) =>
    {
      'id': id,
      'name': name,
      'surname': surname,
      'email': '$id@prova.local',
      'motivation': motivation,
      'role': role,
      'status': status,
      'reviewedByAdmin': reviewed,
      'lastConfirmedAt': '2027-01-20T10:00:00.000Z',
      'groupId': groupId,
      'createdAt': '2027-01-10T10:00:00.000Z',
    };

/// The GET /api/users answer for [users].
Map<String, dynamic> usersPageJson(List<Map<String, dynamic>> users, {int? total, int page = 1}) =>
    {'users': users, 'total': total ?? users.length, 'page': page, 'limit': 50};

Map<String, dynamic> sessionJson(String role) => {
      'status': 'ok',
      'accessToken': 'access-$role',
      'refreshToken': 'refresh-$role',
      'user': userJson(role),
    };

/// An answer computed at call time, e.g. from the query or from earlier calls.
typedef FakeResponder = Object? Function(String method, Map<String, dynamic>? query);

/// In-memory backend: answers are set per path, either fixed or as a
/// [FakeResponder]. Calls are recorded with their query, e.g.
/// 'GET /api/users?page=1&reviewed=false'.
class FakeApiClient implements ApiClient {
  final Map<String, Object> responses;
  final List<String> calls = [];

  /// The data sent by each POST and PATCH, in order.
  final List<dynamic> bodies = [];

  FakeApiClient(this.responses);

  dynamic _answer(String method, String path, [Map<String, dynamic>? query]) {
    final q = query == null || query.isEmpty
        ? ''
        : '?${Uri(queryParameters: query.map((k, v) => MapEntry(k, '$v'))).query}';
    calls.add('$method $path$q');
    var r = responses[path];
    if (r is FakeResponder) r = r(method, query);
    if (r == null) throw ApiException(statusCode: 404, message: 'Non trovato');
    if (r is ApiException) throw r;
    return r;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => _answer('GET', path, query);

  @override
  Future<dynamic> post(String path, {dynamic data}) async {
    bodies.add(data);
    return _answer('POST', path);
  }

  @override
  Future<dynamic> patch(String path, {dynamic data}) async {
    bodies.add(data);
    return _answer('PATCH', path);
  }

  @override
  Future<dynamic> delete(String path, {dynamic data}) async => _answer('DELETE', path);
}

/// An HTTP status and its JSON body.
typedef FakeHttpAnswer = (int, Object?);

/// HTTP transport for the real [ApiClient]: answers by path, either fixed or
/// computed from the request by a function that may also throw or be asynchronous.
class FakeHttp implements HttpClientAdapter {
  final Map<String, Object> routes;
  final List<RequestOptions> requests = [];

  FakeHttp(this.routes);

  /// How many requests reached [path].
  int calls(String path) => requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    Object? route = routes[options.path];
    if (route is Function) route = await (route as dynamic)(options);
    final (status, body) = route as FakeHttpAnswer? ?? (404, {'message': 'Elemento non trovato'});
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
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
