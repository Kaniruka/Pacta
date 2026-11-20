import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/ui/pacta_error_text.dart';

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
    expect(
      formatUserError(Exception('SocketException: Failed host lookup')),
      '云端服务接口尚未就绪或网络异常，请稍后重试。',
    );
    expect(
      formatUserError(
        Exception('HandshakeException: certificate verify failed'),
      ),
      '云端服务接口尚未就绪或网络异常，请稍后重试。',
    );
  });

  test('空串回退到统一兜底文案', () {
    expect(formatUserError(''), '操作未完成，请稍后重试。');
    expect(formatUserError('   '), '操作未完成，请稍后重试。');
    expect(formatUserError('', fallback: '稍后再试。'), '稍后再试。');
  });

  test('非技术英文错误保持原文，便于登录等既有提示', () {
    expect(
      formatUserError(StateError('Invalid login credentials')),
      'Invalid login credentials',
    );
  });
}
