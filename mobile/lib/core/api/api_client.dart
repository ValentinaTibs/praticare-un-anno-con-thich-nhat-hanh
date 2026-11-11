import 'package:dio/dio.dart';
import '../constants.dart';
import '../storage/token_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? contact;
  final String? code;

  ApiException({required this.statusCode, required this.message, this.contact, this.code});

  /// The server could not be reached or could not answer: nothing was decided
  /// about the request, which may well work later.
  bool get isTemporary => statusCode == 0 || statusCode == 429 || statusCode >= 500;

  @override
  String toString() => message;
}

class ApiClient {
  final Dio _dio;
  final TokenStorage _storage;

  /// [onSessionExpired] runs when the backend refuses the refresh token, once
  /// the tokens are cleared. [onForbidden] runs on every 403. [adapter] replaces
  /// the HTTP transport in tests.
  ApiClient(
    this._storage, {
    void Function()? onSessionExpired,
    void Function()? onForbidden,
    HttpClientAdapter? adapter,
  }) : _dio = _newDio(adapter) {
    _dio.interceptors.add(_AuthInterceptor(_storage, _dio, _newDio(adapter), onSessionExpired, onForbidden));
  }

  static Dio _newDio(HttpClientAdapter? adapter) {
    final dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    if (adapter != null) dio.httpClientAdapter = adapter;
    return dio;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    try {
      final res = await _dio.post(path, data: data);
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    try {
      final res = await _dio.put(path, data: data);
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<dynamic> patch(String path, {dynamic data}) async {
    try {
      final res = await _dio.patch(path, data: data);
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<dynamic> delete(String path, {dynamic data}) async {
    try {
      final res = await _dio.delete(path, data: data);
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    final fallback = e.response == null
        ? 'Impossibile contattare il server. Controlla la connessione.'
        : 'Si è verificato un errore.';
    final message = data is Map ? (data['message'] ?? fallback) : fallback;
    final contact = data is Map ? data['contact'] as String? : null;
    final code = data is Map ? data['code'] as String? : null;
    return ApiException(
      statusCode: e.response?.statusCode ?? 0,
      message: message.toString(),
      contact: contact,
      code: code,
    );
  }
}

class _AuthInterceptor extends Interceptor {
  /// Marks a request already repeated with new tokens: a second 401 is final.
  static const _retried = 'authRetried';

  final TokenStorage _storage;
  final Dio _dio;

  /// Without interceptors: the answer to a refresh must not trigger another one.
  final Dio _refreshDio;
  final void Function()? _onSessionExpired;
  final void Function()? _onForbidden;

  /// The refresh under way. The backend rotates the refresh token, so requests
  /// failing together have to share one refresh: a second one would be refused.
  Future<bool>? _refreshing;

  _AuthInterceptor(this._storage, this._dio, this._refreshDio, this._onSessionExpired, this._onForbidden);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    if (status == 403) _onForbidden?.call();
    final request = err.requestOptions;
    if (status != 401 || request.extra[_retried] == true) return handler.next(err);
    try {
      if (!await _hasNewTokens(request)) return handler.next(err);
      request.extra[_retried] = true;
      handler.resolve(await _dio.fetch(request));
    } on DioException catch (e) {
      // This failure is the one that counts, not the 401 that led here: the
      // answer to the repeated request (e.g. a 409), or a refresh that could not
      // be done, which says nothing about the session.
      handler.next(e);
    }
  }

  Future<bool> _hasNewTokens(RequestOptions failed) async {
    // Another request already refreshed them while this one was on its way.
    final token = await _storage.getAccessToken();
    if (token != null && failed.headers['Authorization'] != 'Bearer $token') return true;
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final res = await _refreshDio.post('/api/auth/refresh', data: {'refreshToken': refreshToken});
      await _storage.saveTokens(
        access: res.data['accessToken'] as String,
        refresh: res.data['refreshToken'] as String,
      );
      return true;
    } on DioException catch (e) {
      // Only the backend's refusal ends the session: a network or server error
      // may pass, and the tokens are still good for the next attempt.
      if (e.response?.statusCode != 401) rethrow;
      await _storage.clear();
      _onSessionExpired?.call();
      return false;
    } catch (_) {
      // E.g. an answer without tokens. Letting it through would hang the request.
      return false;
    }
  }
}
