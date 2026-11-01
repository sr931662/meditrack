import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/core/network/api_client.dart';
import 'package:meditrack/core/storage/token_store.dart';

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions o);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Handler handler;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  late MemoryTokenStore tokens;
  late int expired;

  setUp(() async {
    tokens = MemoryTokenStore();
    await tokens.write(const Tokens('old-access', 'old-refresh'));
    expired = 0;
  });

  ApiClient make(FakeAdapter api, FakeAdapter refresh) {
    final c = ApiClient(baseUrl: 'http://x/api/v1', tokens: tokens, onSessionExpired: () => expired++);
    c.rawDio.httpClientAdapter = api;
    c.rawRefreshDio.httpClientAdapter = refresh;
    return c;
  }

  test('attaches the bearer token', () async {
    final api = FakeAdapter((o) => json(200, {'ok': true}));
    await make(api, FakeAdapter((o) => json(500, {}))).get('/auth/me');
    expect(api.calls.single.headers['Authorization'], 'Bearer old-access');
  });

  test('401 triggers one refresh, stores the rotated tokens and retries', () async {
    final api = FakeAdapter((o) => o.headers['Authorization'] == 'Bearer new-access' ? json(200, {'ok': 1}) : json(401, {'error': {'message': 'expired'}}));
    final refresh = FakeAdapter((o) => json(200, {'access_token': 'new-access', 'refresh_token': 'new-refresh'}));
    final r = await make(api, refresh).get('/auth/me');
    expect(r['ok'], 1);
    expect((await tokens.read())!.refresh, 'new-refresh');
    expect(refresh.calls.length, 1);
  });

  test('concurrent 401s share a single refresh (rotation would otherwise look like token theft)', () async {
    final api = FakeAdapter((o) => o.headers['Authorization'] == 'Bearer new-access' ? json(200, {}) : json(401, {}));
    final refresh = FakeAdapter((o) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return json(200, {'access_token': 'new-access', 'refresh_token': 'new-refresh'});
    });
    final c = make(api, refresh);
    await Future.wait([c.get('/a'), c.get('/b'), c.get('/c')]);
    expect(refresh.calls.length, 1);
  });

  test('failed refresh clears the session and signals expiry', () async {
    final api = FakeAdapter((o) => json(401, {'error': {'message': 'no'}}));
    final refresh = FakeAdapter((o) => json(401, {}));
    await expectLater(make(api, refresh).get('/auth/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'unauthorized', true)));
    expect(await tokens.read(), isNull);
    expect(expired, 1);
  });

  test('server error bodies become readable ApiExceptions', () async {
    final api = FakeAdapter((o) => json(422, {'error': {'code': 'validation_error', 'message': 'Request validation failed', 'details': []}}));
    await expectLater(
        make(api, FakeAdapter((o) => json(500, {}))).post('/x', data: {}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'validation_error').having((e) => e.status, 'status', 422)));
  });

  test('network failures are flagged so the app can fall back to offline mode', () async {
    final api = FakeAdapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline'));
    await expectLater(make(api, FakeAdapter((o) => json(500, {}))).get('/x'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
  });

  test('login does not send or require a bearer token', () async {
    final api = FakeAdapter((o) => json(200, {'access_token': 'a', 'refresh_token': 'r'}));
    await make(api, FakeAdapter((o) => json(500, {}))).post('/auth/login', data: {}, auth: false);
    expect(api.calls.single.headers.containsKey('Authorization'), isFalse);
  });
}
