import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/admin_password_reset_card.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('普通用户看不到管理员密码重置表单', (tester) async {
    final repository = FakeAuthRepository()..signedInUser = 'user@example.com';

    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('管理员：重置用户密码'), findsNothing);
  });

  testWidgets('管理员可从 My 页面指定目标用户', (tester) async {
    final repository = FakeAuthRepository()
      ..signedInUser = 'admin@example.com'
      ..administrator = true;

    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('管理员：重置用户密码'), findsOneWidget);
    expect(find.byKey(const Key('reset-target-email')), findsOneWidget);
  });

  testWidgets('管理员需指定目标并确认线下人工核实后重置密码', (tester) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminPasswordResetCard(repository: repository)),
      ),
    );

    expect(find.text('管理员：重置用户密码'), findsOneWidget);
    expect(find.textContaining('应用不会验证邮箱所有权'), findsOneWidget);
    final resetButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '重置密码'),
    );
    expect(resetButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('reset-target-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('reset-new-password')),
      'new-secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('reset-confirm-password')),
      'new-secret-123',
    );
    await tester.tap(find.byKey(const Key('manual-verification-confirmation')));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '重置密码'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pumpAndSettle();

    expect(repository.passwordResetEmail, 'user@example.com');
    expect(repository.passwordResetValue, 'new-secret-123');
    expect(repository.passwordResetManualVerificationConfirmed, isTrue);
    expect(find.textContaining('密码已重置'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('manual-verification-confirmation')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '重置密码'))
          .onPressed,
      isNull,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'new-secret-123',
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('reset-new-password')))
          .obscureText,
      isTrue,
    );
  });

  testWidgets('密码确认不一致时不提交', (tester) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminPasswordResetCard(repository: repository)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('reset-target-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('reset-new-password')),
      'new-secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('reset-confirm-password')),
      'different-secret',
    );
    await tester.tap(find.byKey(const Key('manual-verification-confirmation')));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '重置密码'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致。'), findsOneWidget);
    expect(repository.passwordResetEmail, isNull);
  });

  testWidgets('服务端拒绝时保留表单并显示错误', (tester) async {
    final repository = FakeAuthRepository()
      ..passwordResetError = StateError('管理员权限不足');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminPasswordResetCard(repository: repository)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('reset-target-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('reset-new-password')),
      'new-secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('reset-confirm-password')),
      'new-secret-123',
    );
    await tester.tap(find.byKey(const Key('manual-verification-confirmation')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pumpAndSettle();

    expect(find.textContaining('管理员权限不足'), findsOneWidget);
    expect(repository.passwordResetEmail, 'user@example.com');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('reset-new-password')))
          .controller!
          .text,
      'new-secret-123',
    );
  });
}
