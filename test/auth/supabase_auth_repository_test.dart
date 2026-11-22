import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// 与 GoTrue session 结构一致的登录响应：changePassword 需要
/// `auth.currentUser.email` 已存在，才能按当前密码复核身份。
const _sessionBody = {
  'access_token': 'access-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh-token',
  'user': {
    'id': 'user-id',
    'email': 'user@example.com',
    'created_at': '2026-01-01T00:00:00Z',
  },
};

http.Response _json(Object body, int status, http.BaseRequest request) =>
    http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: _jsonHeaders,
      request: request,
    );

/// 记录每一次请求的客户端；[tokenResponse] 决定 token 端点的回答，
/// 便于测试把“当前密码复核成功/失败”与“更新密码”分开断言。
SupabaseClient _client(
  List<http.Request> requests, {
  http.Response Function(http.Request request)? tokenResponse,
  http.Response Function(http.Request request)? userResponse,
}) {
  final client = SupabaseClient(
    'https://pacta-test.supabase.co',
    'publishable-test-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/token') {
        return tokenResponse?.call(request) ??
            _json(_sessionBody, 200, request);
      }
      if (request.url.path == '/auth/v1/user') {
        return userResponse?.call(request) ??
            _json(_sessionBody['user']!, 200, request);
      }
      return _json('{"message":"unexpected path"}', 404, request);
    }),
  );
  addTearDown(client.dispose);
  return client;
}

/// 已登录客户端：先用一次真实 signInWithPassword 建立会话，再清空请求记录，
/// 让后续断言只覆盖被测方法自己发出的请求。
Future<SupabaseClient> _signedInClient(List<http.Request> requests) async {
  final client = _client(requests);
  await SupabaseAuthRepository(client)
      .signIn(email: 'user@example.com', password: 'current-secret');
  requests.clear();
  return client;
}

void main() {
  group('changePassword 本地校验', () {
    Future<SupabaseClient> unauthenticatedClient(
      List<http.Request> requests,
    ) async => _client(requests);

    test('空当前密码在发请求前被拒绝', () async {
      final requests = <http.Request>[];
      final repository = SupabaseAuthRepository(
        await unauthenticatedClient(requests),
      );

      await expectLater(
        repository.changePassword(
          currentPassword: '',
          newPassword: 'new-secret-123',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '请输入当前密码。',
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('新密码不足 8 位在发请求前被拒绝', () async {
      final requests = <http.Request>[];
      final repository = SupabaseAuthRepository(
        await unauthenticatedClient(requests),
      );

      await expectLater(
        repository.changePassword(
          currentPassword: 'current-secret',
          newPassword: 'short',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '新密码至少需要 8 个字符。',
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('新密码超过 256 位在发请求前被拒绝', () async {
      final requests = <http.Request>[];
      final repository = SupabaseAuthRepository(
        await unauthenticatedClient(requests),
      );

      await expectLater(
        repository.changePassword(
          currentPassword: 'current-secret',
          newPassword: 'a' * 257,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '新密码长度不能超过 256 个字符。',
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('新密码与当前密码相同在发请求前被拒绝', () async {
      final requests = <http.Request>[];
      final repository = SupabaseAuthRepository(
        await unauthenticatedClient(requests),
      );

      await expectLater(
        repository.changePassword(
          currentPassword: 'current-secret',
          newPassword: 'current-secret',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '新密码不能与当前密码相同。',
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('未登录时抛出可读的 StateError', () async {
      final requests = <http.Request>[];
      final repository = SupabaseAuthRepository(
        await unauthenticatedClient(requests),
      );

      await expectLater(
        repository.changePassword(
          currentPassword: 'current-secret',
          newPassword: 'new-secret-123',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '当前未登录或缺少账号邮箱，请重新登录后再试。',
          ),
        ),
      );
      expect(requests, isEmpty);
    });
  });

  test('先以当前密码复核 token，再 PUT /auth/v1/user 更新密码', () async {
    final requests = <http.Request>[];
    final client = await _signedInClient(requests);

    await SupabaseAuthRepository(client).changePassword(
      currentPassword: 'current-secret',
      newPassword: 'new-secret-123',
    );

    expect(requests, hasLength(2));
    final reauth = requests.first;
    expect(reauth.method, 'POST');
    expect(reauth.url.path, '/auth/v1/token');
    expect(reauth.url.queryParameters['grant_type'], 'password');
    final reauthBody = jsonDecode(reauth.body) as Map<String, Object?>;
    expect(reauthBody['email'], 'user@example.com');
    expect(reauthBody['password'], 'current-secret');

    final update = requests.last;
    expect(update.method, 'PUT');
    expect(update.url.path, '/auth/v1/user');
    expect(update.headers['authorization'], 'Bearer access-token');
    expect(
      (jsonDecode(update.body) as Map<String, Object?>)['password'],
      'new-secret-123',
    );
  });

  test('400 invalid login credentials 映射为当前密码不正确的中文提示', () async {
    final requests = <http.Request>[];
    var tokenCalls = 0;
    final client = _client(
      requests,
      tokenResponse: (request) {
        tokenCalls++;
        if (tokenCalls == 1) return _json(_sessionBody, 200, request);
        return _json(
          {
            'error': 'invalid_grant',
            'error_description': 'Invalid login credentials',
          },
          400,
          request,
        );
      },
    );
    await SupabaseAuthRepository(client)
        .signIn(email: 'user@example.com', password: 'current-secret');

    await expectLater(
      SupabaseAuthRepository(client).changePassword(
        currentPassword: 'wrong-secret',
        newPassword: 'new-secret-123',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '当前密码不正确，请重新输入。',
        ),
      ),
    );
    expect(
      requests.where((request) => request.method == 'PUT'),
      isEmpty,
      reason: '当前密码未通过复核时不得更新密码',
    );
  });

  test('非凭据类 400 保留 AuthException，不误报当前密码错误', () async {
    final requests = <http.Request>[];
    var tokenCalls = 0;
    final client = _client(
      requests,
      tokenResponse: (request) {
        tokenCalls++;
        if (tokenCalls == 1) return _json(_sessionBody, 200, request);
        return _json(
          {
            'error': 'user_banned',
            'error_code': 'user_banned',
            'msg': 'User is banned',
          },
          400,
          request,
        );
      },
    );
    await SupabaseAuthRepository(client)
        .signIn(email: 'user@example.com', password: 'current-secret');

    await expectLater(
      SupabaseAuthRepository(client).changePassword(
        currentPassword: 'current-secret',
        newPassword: 'new-secret-123',
      ),
      throwsA(
        isA<AuthException>()
            .having((error) => error.statusCode, 'statusCode', '400')
            .having(
              (error) => error.message.toLowerCase(),
              'message',
              contains('banned'),
            ),
      ),
    );
    expect(
      requests.where((request) => request.method == 'PUT'),
      isEmpty,
      reason: '账号停用不是密码错误，也不该继续更新密码',
    );
  });

  test('清除回执查询只返回精确 UUID 的 completed 回执', () async {
    Uri? requestedUri;
    Map<String, Object?>? requestBody;
    final client = SupabaseClient(
      'https://pacta-test.supabase.co',
      'publishable-test-key',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'user_id': 'different-user-id',
            'status': 'completed',
            'purged_at': '2026-09-26T05:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final receipt = await SupabaseAuthRepository(client)
        .lookupPurgeReceipt('old-user-id');

    expect(requestedUri?.path, '/rest/v1/rpc/user_purge_receipt');
    expect(requestBody, {'p_user_id': 'old-user-id'});
    expect(receipt, isNull);
  });

  test('清除回执查询保留普通服务端异常', () async {
    final client = SupabaseClient(
      'https://pacta-test.supabase.co',
      'publishable-test-key',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"message":"server unavailable"}',
          503,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseAuthRepository(client).lookupPurgeReceipt('old-user-id'),
      throwsA(anything),
    );
  });
}
