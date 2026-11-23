import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// 与 GoTrue 会话结构一致：`currentUser` 才有邮箱与 id 可读。
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

/// [failLogout] 模拟离线：登出请求拿不到 2xx，GoTrue 会抛出鉴权异常。
SupabaseClient _client({
  bool failLogout = false,
  bool signUpWithoutSession = false,
}) {
  final client = SupabaseClient(
    'https://pacta-test.supabase.co',
    'publishable-test-key',
    // 纯内存夹具：关掉自动刷新，并显式声明 implicit 流程，
    // 否则 PKCE 会要求 [AsyncStorage] 实例。
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
    httpClient: MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        return _json(_sessionBody, 200, request);
      }
      if (request.url.path == '/auth/v1/signup') {
        // GoTrue 的 `AuthResponse.fromJson` 把整个响应体当 session 解析：
        // 会话字段必须在顶层，不能嵌在 `session` 里。
        // 需要邮箱确认时响应体只有 user、没有 access_token，解析结果就是
        // 「有用户、无会话」，注册不会被当成已登录。
        return _json(
          signUpWithoutSession ? {'user': _sessionBody['user']} : _sessionBody,
          200,
          request,
        );
      }
      if (request.url.path == '/auth/v1/logout') {
        if (failLogout) {
          return _json({'message': 'server unavailable'}, 503, request);
        }
        return http.Response('', 204, request: request);
      }
      return _json('{"message":"unexpected path"}', 404, request);
    }),
  );
  addTearDown(client.dispose);
  return client;
}

/// 仓储 + 可推事件的身份流；[emissions] 记录 `authState` 的每一次发射。
({
  SupabaseAuthRepository repository,
  StreamController<AuthSessionSignal> signals,
  List<String?> emissions,
})
_harness({
  SupabaseClient? client,
  String? retainedEmail,
  String? retainedUserId,
}) {
  final signals = StreamController<AuthSessionSignal>.broadcast();
  addTearDown(signals.close);
  final repository = SupabaseAuthRepository.withSignals(
    client ?? _client(),
    signals.stream,
    retainedEmail: retainedEmail,
    retainedUserId: retainedUserId,
  );
  addTearDown(repository.dispose);
  final emissions = <String?>[];
  final subscription = repository.authState.listen(emissions.add);
  addTearDown(subscription.cancel);
  return (repository: repository, signals: signals, emissions: emissions);
}

const _signedIn = AuthSessionSignal(
  email: 'user@example.com',
  userId: 'user-id',
);

void main() {
  test('离线空会话（token 刷新失败）保留已登录身份，不发射 null', () async {
    final harness = _harness(
      retainedEmail: 'user@example.com',
      retainedUserId: 'user-id',
    );

    // 重放：订阅瞬间就拿到当前身份，首帧不会被判成未登录。
    // 广播流是异步投递，重放值在微任务里才落到监听者手上。
    await pumpEventQueue();
    expect(harness.emissions, ['user@example.com']);

    harness.signals.add(const AuthSessionSignal.signedOut());
    await pumpEventQueue();

    expect(harness.repository.currentUserIdentifier, 'user@example.com');
    expect(harness.repository.currentUserId, 'user-id');
    expect(harness.emissions, [
      'user@example.com',
    ], reason: '离线刷新失败不是用户主动登出，界面必须留在原页面');
  });

  test('主动 signOut 后才回到未登录并清空本地保留身份', () async {
    final harness = _harness(
      retainedEmail: 'user@example.com',
      retainedUserId: 'user-id',
    );

    await harness.repository.signOut();
    await pumpEventQueue();

    expect(harness.repository.currentUserIdentifier, isNull);
    expect(harness.repository.currentUserId, isNull);
    expect(harness.emissions, ['user@example.com', null]);
  });

  test('离线时 signOut 请求失败也完成本地清理', () async {
    final harness = _harness(client: _client(failLogout: true));

    await harness.repository.signIn(
      email: 'user@example.com',
      password: 'current-secret',
    );
    expect(harness.repository.currentUserIdentifier, 'user@example.com');

    await expectLater(harness.repository.signOut(), completes);

    expect(harness.repository.currentUserIdentifier, isNull);
    expect(harness.repository.currentUserId, isNull);
    expect(harness.emissions.last, isNull);
  });

  test('同一身份重复事件只发射一次', () async {
    final harness = _harness(
      retainedEmail: 'user@example.com',
      retainedUserId: 'user-id',
    );

    harness.signals.add(_signedIn);
    await pumpEventQueue();
    expect(harness.emissions, ['user@example.com']);

    harness.signals.add(
      const AuthSessionSignal(email: 'other@example.com', userId: 'other-id'),
    );
    await pumpEventQueue();
    expect(harness.emissions, ['user@example.com', 'other@example.com']);
  });

  test('登录成功后重置主动登出标记，之后的空会话仍然保活', () async {
    final harness = _harness();

    await harness.repository.signOut();
    expect(harness.repository.currentUserIdentifier, isNull);

    await harness.repository.signIn(
      email: 'user@example.com',
      password: 'current-secret',
    );
    expect(harness.repository.currentUserIdentifier, 'user@example.com');

    harness.signals.add(const AuthSessionSignal.signedOut());
    await pumpEventQueue();

    expect(harness.repository.currentUserIdentifier, 'user@example.com');
    expect(harness.repository.currentUserId, 'user-id');
  });

  test('后到的订阅者先收到重放身份，再收到后续变化', () async {
    final harness = _harness(
      retainedEmail: 'user@example.com',
      retainedUserId: 'user-id',
    );
    final late = <String?>[];
    final subscription = harness.repository.authState.listen(late.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    expect(late, ['user@example.com']);

    await harness.repository.signOut();
    await pumpEventQueue();

    expect(late, ['user@example.com', null]);
  });

  test('signUp 返回会话时记录身份', () async {
    final harness = _harness();

    await harness.repository.signUp(
      email: 'user@example.com',
      password: 'current-secret',
    );
    // 广播流异步投递：先让事件落到监听者，再断言发射序列。
    await pumpEventQueue();

    expect(harness.repository.currentUserIdentifier, 'user@example.com');
    expect(harness.repository.currentUserId, 'user-id');
    expect(harness.emissions, [null, 'user@example.com']);
  });

  test('signUp 需要邮箱确认（无会话）时不提前认为已登录', () async {
    final harness = _harness(client: _client(signUpWithoutSession: true));

    await harness.repository.signUp(
      email: 'user@example.com',
      password: 'current-secret',
    );

    expect(harness.repository.currentUserIdentifier, isNull);
    expect(harness.repository.currentUserId, isNull);
  });
}
