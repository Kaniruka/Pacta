import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/ui/pacta_error_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

void main() {
  test('保留中文业务提示并剥离前缀', () {
    expect(
      formatUserError(StateError('Bad state: 该标识没有可用的注册资格。')),
      '该标识没有可用的注册资格。',
    );
    expect(
      formatUserError(ArgumentError('Invalid argument(s): 请填写名称。')),
      '请填写名称。',
    );
    expect(formatUserError(Exception('Exception: 网络连接已断开。')), '网络连接已断开。');
  });

  test('PGRST202 与 Postgrest 错误脱敏为可重试提示', () {
    expect(
      formatUserError(
        Exception(
          'PGRST202: Could not find the function public.upsert_profile',
        ),
      ),
      '云端服务版本尚未同步最新接口，请稍后重试。',
    );
    expect(
      formatUserError(
        Exception('PostgrestException(message: schema cache miss)'),
      ),
      '云端服务版本尚未同步最新接口，请稍后重试。',
    );
  });

  test('网络与数据库层失败统一为无法连接云端服务', () {
    expect(
      formatUserError(Exception('SocketException: Failed host lookup')),
      '无法连接到云端服务，请检查网络后重试。',
    );
    expect(
      formatUserError(
        Exception('HandshakeException: certificate verify failed'),
      ),
      '无法连接到云端服务，请检查网络后重试。',
    );
    expect(
      formatUserError(Exception('ClientException: Connection refused')),
      '无法连接到云端服务，请检查网络后重试。',
    );
    expect(
      formatUserError(Exception('database error: connection refused')),
      '无法连接到云端服务，请检查网络后重试。',
    );
    expect(
      formatUserError(Exception('PostgrestException(status: 503)')),
      '无法连接到云端服务，请检查网络后重试。',
    );
  });

  test('空串回退到统一兜底文案', () {
    expect(formatUserError(''), '操作未完成，请稍后重试。');
    expect(formatUserError('   '), '操作未完成，请稍后重试。');
    expect(formatUserError('', fallback: '稍后再试。'), '稍后再试。');
  });

  test('已知鉴权失败映射为精准中文，不回显英文原文', () {
    expect(
      formatUserError(StateError('Invalid login credentials')),
      '邮箱或密码错误，请核对后重试。',
    );
    expect(
      formatUserError(
        AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      ),
      '邮箱或密码错误，请核对后重试。',
    );
    expect(
      formatUserError(StateError('User already registered')),
      '该邮箱已注册，请直接切换到「登录」。',
    );
    expect(formatUserError(StateError('User is banned')), '该账号已被停用，请联系管理员。');
    expect(
      formatUserError(StateError('over_request_rate_limit')),
      '操作过于频繁，请稍后再试。',
    );
  });

  test('无注册资格：code 与不含 eligib 的 message 都识别', () {
    expect(describeKnownFailure('signup_not_allowed'), '该邮箱尚未获得注册资格，请联系管理员开通。');
    expect(
      describeKnownFailure('Signups not allowed for this instance'),
      '该邮箱尚未获得注册资格，请联系管理员开通。',
    );
    expect(
      formatUserError(StateError('Signups not allowed for this instance')),
      '该邮箱尚未获得注册资格，请联系管理员开通。',
    );
    expect(
      formatUserError(
        AuthException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_not_allowed',
        ),
      ),
      '该邮箱尚未获得注册资格，请联系管理员开通。',
    );
    expect(
      formatUserError(
        AuthException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_not_allowed',
        ),
      ),
      isNot(contains('statusCode')),
    );
    expect(
      formatUserError(
        AuthException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_not_allowed',
        ),
      ),
      isNot(contains('signup_not_allowed')),
    );
  });
}
