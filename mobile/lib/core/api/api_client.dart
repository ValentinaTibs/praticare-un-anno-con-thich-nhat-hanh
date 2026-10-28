import 'package:dio/dio.dart';
import '../constants.dart';
import '../storage/token_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? contact;
  final String? code;

  ApiException({required this.statusCode, required this.message, this.contact, this.code});

  @override
  String toString() => message;
}

class ApiClient {
  final Dio _dio;
  final TokenStorage _storage;

  ApiClient(this._storage)
      : _dio = Dio(BaseOptions(
          baseUrl: AppConstants.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )) {
    _dio.interceptors.add(_AuthInterceptor(_storage, _dio));
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
  final TokenStorage _storage;
  final Dio _dio;

  _AuthInterceptor(this._storage, this._dio);

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
    if (err.response?.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final token = await _storage.getAccessToken();
        err.requestOptions.headers['Authorization'] = 'Bearer $token';
        try {
          final res = await _dio.fetch(err.requestOptions);
          return handler.resolve(res);
        } catch (_) {}
      }
    }
    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final res = await _dio.post('/api/auth/refresh', data: {'refreshToken': refreshToken});
      await _storage.saveTokens(
        access: res.data['accessToken'] as String,
        refresh: res.data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      await _storage.clear();
      return false;
    }
  }
}
