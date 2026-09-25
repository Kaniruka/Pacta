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
}
