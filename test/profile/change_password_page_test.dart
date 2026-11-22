import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/profile/change_password_page.dart';

import '../support/fake_auth_repository.dart';

class _FakeLifecycleRepository implements UserLifecycleStatusRepository {
  _FakeLifecycleRepository({this.cached, this.refreshed, this.refreshError});

  UserLifecycleStatus? cached;
  UserLifecycleStatus? refreshed;
  Object? refreshError;
  int refreshCalls = 0;

  @override
  Future<UserLifecycleStatus?> readCachedStatus() async => cached;

  @override
  Stream<UserLifecycleStatus?> watchStatus() => Stream.value(cached);

  @override
  Future<UserLifecycleStatus> refresh() async {
    refreshCalls++;
    final error = refreshError;
    if (error != null) throw error;
    return refreshed ??
        UserLifecycleStatus(
          isSuspended: false,
          checkedAt: DateTime.utc(2026, 11, 1),
        );
  }
}

/// 修改密码请求停在途中：进度条与禁用态只在请求未完成时存在。
class _GatedAuthRepository extends FakeAuthRepository {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await gate.future;
    await super.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}

UserLifecycleStatus _suspended() => UserLifecycleStatus(
  isSuspended: true,
  suspendedAt: DateTime.utc(2026, 10, 1),
  checkedAt: DateTime.utc(2026, 11, 1),
);

Future<FakeAuthRepository> _openPage(
  WidgetTester tester, {
  UserLifecycleStatusRepository? lifecycle,
  Object? changePasswordError,
  FakeAuthRepository? repository,
}) async {
  final auth = repository ?? FakeAuthRepository();
  auth.changePasswordError = changePasswordError;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ChangePasswordPage(
                    authRepository: auth,
                    lifecycleRepository: lifecycle,
                  ),
                ),
              ),
              child: const Text('打开修改密码'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开修改密码'));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _fill(
  WidgetTester tester, {
  String current = 'current-secret',
  String next = 'new-secret-123',
  String? confirm,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('change-password-current')),
    current,
  );
  await tester.enterText(
    find.byKey(const ValueKey('change-password-new')),
    next,
  );
  await tester.enterText(
    find.byKey(const ValueKey('change-password-confirm')),
    confirm ?? next,
  );
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('change-password-submit'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空当前密码不调用修改密码', (tester) async {
    final auth = await _openPage(tester);
    await _fill(tester, current: '');
    await _submit(tester);

    expect(find.text('请输入当前密码。'), findsOneWidget);
    expect(auth.changePasswordCalls, 0);
  });

  testWidgets('新密码不足 8 位不调用修改密码', (tester) async {
    final auth = await _openPage(tester);
    await _fill(tester, next: 'short');
    await _submit(tester);

    expect(find.text('新密码至少需要 8 个字符。'), findsOneWidget);
    expect(auth.changePasswordCalls, 0);
  });

  testWidgets('新密码超过 256 位不调用修改密码', (tester) async {
    final auth = await _openPage(tester);
    await _fill(tester, next: 'a' * 257);
    await _submit(tester);

    expect(find.text('新密码长度不能超过 256 个字符。'), findsOneWidget);
    expect(auth.changePasswordCalls, 0);
  });

  testWidgets('新密码与当前密码相同不调用修改密码', (tester) async {
    final auth = await _openPage(tester);
    await _fill(tester, next: 'current-secret');
    await _submit(tester);

    expect(find.text('新密码不能与当前密码相同。'), findsOneWidget);
    expect(auth.changePasswordCalls, 0);
  });

  testWidgets('两次输入的新密码不一致不调用修改密码', (tester) async {
    final auth = await _openPage(tester);
    await _fill(tester, confirm: 'new-secret-124');
    await _submit(tester);

    expect(find.text('两次输入的新密码不一致。'), findsOneWidget);
    expect(auth.changePasswordCalls, 0);
  });

  testWidgets('当前密码错误只显示中文原因，不带 FormatException 前缀', (tester) async {
    final auth = await _openPage(
      tester,
      changePasswordError: const FormatException('当前密码不正确，请重新输入。'),
    );
    await _fill(tester);
    await _submit(tester);

    expect(auth.changePasswordCalls, 1);
    expect(find.text('当前密码不正确，请重新输入。'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.byType(ChangePasswordPage), findsOneWidget);
  });

  testWidgets('缓存显示停用但服务端已恢复时放行修改密码', (tester) async {
    final lifecycle = _FakeLifecycleRepository(
      cached: _suspended(),
      refreshed: UserLifecycleStatus(
        isSuspended: false,
        checkedAt: DateTime.utc(2026, 11, 2),
      ),
    );
    final auth = await _openPage(tester, lifecycle: lifecycle);
    await _fill(tester);
    await _submit(tester);

    expect(lifecycle.refreshCalls, 1, reason: '刷新优先于本机缓存');
    expect(auth.changePasswordCalls, 1);
    expect(find.text('密码已更新。'), findsOneWidget);
    expect(find.textContaining('用户已停用'), findsNothing);
  });

  testWidgets('缓存显示停用且刷新失败时拦在修改密码之前', (tester) async {
    final lifecycle = _FakeLifecycleRepository(
      cached: _suspended(),
      refreshError: StateError('network down'),
    );
    final auth = await _openPage(tester, lifecycle: lifecycle);
    await _fill(tester);
    await _submit(tester);

    expect(lifecycle.refreshCalls, 1);
    expect(auth.changePasswordCalls, 0);
    expect(find.textContaining('用户已停用'), findsOneWidget);
  });

  testWidgets('刷新到停用状态时在修改密码前拦下', (tester) async {
    final lifecycle = _FakeLifecycleRepository(refreshed: _suspended());
    final auth = await _openPage(tester, lifecycle: lifecycle);
    await _fill(tester);
    await _submit(tester);

    expect(lifecycle.refreshCalls, 1);
    expect(auth.changePasswordCalls, 0);
    expect(find.textContaining('用户已停用'), findsOneWidget);
  });

  testWidgets('无缓存且刷新失败时按不可核验拦下', (tester) async {
    final lifecycle = _FakeLifecycleRepository(
      refreshError: StateError('network down'),
    );
    final auth = await _openPage(tester, lifecycle: lifecycle);
    await _fill(tester);
    await _submit(tester);

    expect(lifecycle.refreshCalls, 1);
    expect(auth.changePasswordCalls, 0);
    expect(find.text('暂时无法核验账号状态，请联网后重试。'), findsOneWidget);
  });

  testWidgets('未配置账号状态仓储时直接调用修改密码', (tester) async {
    final auth = await _openPage(
      tester,
      lifecycle: const UnavailableUserLifecycleStatusRepository(),
    );
    await _fill(tester);
    await _submit(tester);

    expect(auth.changePasswordCalls, 1);
    expect(find.text('密码已更新。'), findsOneWidget);
  });

  testWidgets('显隐按钮只在密文与明文之间切换当前密码框', (tester) async {
    await _openPage(tester);
    final field = find.byKey(const ValueKey('change-password-current'));
    expect(tester.widget<TextField>(field).obscureText, isTrue);

    await tester.tap(
      find.descendant(of: field, matching: find.byTooltip('显示密码')),
    );
    await tester.pump();
    expect(tester.widget<TextField>(field).obscureText, isFalse);
    expect(
      find.descendant(of: field, matching: find.byTooltip('隐藏密码')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: field, matching: find.byTooltip('隐藏密码')),
    );
    await tester.pump();
    expect(tester.widget<TextField>(field).obscureText, isTrue);
  });

  testWidgets('修改成功后提示并返回上一页，页面不留密码文本', (tester) async {
    final auth = await _openPage(tester);
    await _fill(tester);
    await _submit(tester);

    expect(auth.changePasswordCalls, 1);
    expect(auth.lastCurrentPassword, 'current-secret');
    expect(auth.lastNewPassword, 'new-secret-123');
    expect(find.text('密码已更新。'), findsOneWidget);
    expect(find.byType(ChangePasswordPage), findsNothing);
    expect(find.text('打开修改密码'), findsOneWidget);
    for (final secret in ['current-secret', 'new-secret-123']) {
      expect(find.text(secret), findsNothing);
      expect(find.textContaining(secret), findsNothing);
    }
  });

  testWidgets('修改密码进行中禁用输入并显示进度', (tester) async {
    final auth = _GatedAuthRepository();
    await _openPage(tester, repository: auth);
    await _fill(tester);
    final button = find.byKey(const ValueKey('change-password-submit'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('change-password-current')),
          )
          .enabled,
      isFalse,
    );

    auth.gate.complete();
    await tester.pumpAndSettle();
    expect(auth.changePasswordCalls, 1);
    expect(find.text('密码已更新。'), findsOneWidget);
  });
}
