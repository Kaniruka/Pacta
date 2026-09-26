import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('密码重置只调用受 JWT 保护的管理员 Edge Function', () async {
    Uri? requestedUri;
    Map<String, Object?>? requestBody;
    final client = SupabaseClient(
      'https://pacta-test.supabase.co',
      'publishable-test-key',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    await SupabaseAuthRepository(client).adminResetUserPassword(
      targetEmail: ' User@Example.com ',
      newPassword: 'new-secret-123',
      manualVerificationConfirmed: true,
    );

    expect(requestedUri?.path, '/functions/v1/admin-reset-user-password');
    expect(requestBody, {
      'email': 'user@example.com',
      'new_password': 'new-secret-123',
      'manual_verification_confirmed': true,
    });
  });

  test('普通用户不能绕过 UI 省略人工核实声明', () async {
    final client = SupabaseClient(
      'https://pacta-test.supabase.co',
      'publishable-test-key',
      httpClient: MockClient(
        (_) async => http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseAuthRepository(client).adminResetUserPassword(
        targetEmail: 'user@example.com',
        newPassword: 'new-secret-123',
        manualVerificationConfirmed: false,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('管理员清除调用按旧 UUID 请求 Edge Function 并核对完成回执', () async {
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
            'user_id': 'old-user-id',
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
        .purgeUser('old-user-id');

    expect(requestedUri?.path, '/functions/v1/admin-purge-user');
    expect(requestBody, {'user_id': 'old-user-id'});
    expect(receipt.confirmsPurgedUser('old-user-id'), isTrue);
  });

  test('管理员清除不接受绑定到另一 UUID 的成功响应', () async {
    final client = SupabaseClient(
      'https://pacta-test.supabase.co',
      'publishable-test-key',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'user_id': 'different-user-id',
            'status': 'completed',
            'purged_at': '2026-09-26T05:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseAuthRepository(client).purgeUser('old-user-id'),
      throwsA(isA<StateError>()),
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
