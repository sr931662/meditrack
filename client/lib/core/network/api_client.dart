import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_store.dart';

/// Every failure surfaces as this type so UI code never handles raw Dio errors.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code, this.isNetwork = false, this.details});
  final String message;
  final int? status;
  final String? code;
  final bool isNetwork;
  final List<dynamic>? details;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, required this._tokens, Dio? dio, this.onSessionExpired})
      : _dio = dio ?? Dio(),
        _refreshDio = Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..validateStatus = (s) => s != null && s < 500; // 4xx handled in _unwrap, 5xx surfaces as DioException
    _refreshDio.options.baseUrl = baseUrl;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _attach, onError: _onError));
  }

  final TokenStore _tokens;
  final Dio _dio;
  final Dio _refreshDio;
  final void Function()? onSessionExpired;
  Completer<bool>? _refreshing;

  /// Lets tests plug in a fake transport.
  Dio get rawDio => _dio;
  Dio get rawRefreshDio => _refreshDio;

  Future<void> _attach(RequestOptions o, RequestInterceptorHandler h) async {
    final t = await _tokens.read();
    if (t != null && o.extra['skipAuth'] != true) o.headers['Authorization'] = 'Bearer ${t.access}';
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async => h.next(e);

  /// Single-flight refresh: concurrent 401s share one refresh call (refresh tokens rotate, so a second
  /// concurrent call would otherwise be treated as token reuse and kill the session).
  Future<bool> _refresh() {
    if (_refreshing != null) return _refreshing!.future;
    final c = _refreshing = Completer<bool>();
    () async {
      try {
        final t = await _tokens.read();
        if (t == null) return c.complete(false);
        final r = await _refreshDio.post('/auth/refresh', data: {'refresh_token': t.refresh});
        if (r.statusCode == 200) {
          await _tokens.write(Tokens(r.data['access_token'], r.data['refresh_token']));
          c.complete(true);
        } else {
          c.complete(false);
        }
      } catch (_) {
        c.complete(false);
      } finally {
        _refreshing = null;
      }
    }();
    return c.future;
  }

  Future<dynamic> request(String method, String path,
      {Object? data, Map<String, dynamic>? query, bool auth = true}) async {
    Future<Response<dynamic>> send() => _dio.request(path,
        data: data, queryParameters: query, options: Options(method: method, extra: {'skipAuth': !auth}));
    try {
      var r = await send();
      if (r.statusCode == 401 && auth) {
        if (await _refresh()) {
          r = await send();
        } else {
          await _tokens.clear();
          onSessionExpired?.call();
        }
      }
      return _unwrap(r);
    } on DioException catch (e) {
      throw ApiException(
        e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout
            ? 'Can\'t reach the server. Check your connection.'
            : 'Something went wrong. Please try again.',
        isNetwork: e.type != DioExceptionType.badResponse,
      );
    }
  }

  dynamic _unwrap(Response<dynamic> r) {
    final s = r.statusCode ?? 0;
    if (s >= 200 && s < 300) return r.data;
    final err = (r.data is Map ? r.data['error'] : null) as Map?;
    throw ApiException(
      (err?['message'] as String?) ?? 'Request failed ($s)',
      status: s,
      code: err?['code'] as String?,
      details: err?['details'] as List?,
    );
  }

  Future<dynamic> get(String p, {Map<String, dynamic>? query}) => request('GET', p, query: query);
  Future<dynamic> post(String p, {Object? data, bool auth = true}) => request('POST', p, data: data, auth: auth);
  Future<dynamic> put(String p, {Object? data}) => request('PUT', p, data: data);
  Future<dynamic> patch(String p, {Object? data}) => request('PATCH', p, data: data);
  Future<dynamic> delete(String p) => request('DELETE', p);
}
