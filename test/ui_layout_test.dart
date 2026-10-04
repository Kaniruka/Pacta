import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart' as focus;
import 'package:pacta/src/focus/focus_repository.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('亮暗主题正文与主要操作达到4.5对比度', (tester) async {
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpWidget(PactaApp(authRepository: auth));
      await tester.pumpAndSettle();
      final colors = Theme.of(tester.element(find.text('今天先做什么'))).colorScheme;
      for (final pair in [
        (colors.onSurface, colors.surface),
        (colors.onSurfaceVariant, colors.surface),
        (colors.onPrimary, colors.primary),
      ]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字可访问四个入口且页面不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();
    for (final label in ['看板', '专注链', '我的', '国策树']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('宽屏以侧边导航访问页面并跟随系统深色', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('layout-user'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('layout-user'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('专注历史和用户管理从入口进入可返回的二级页面', (tester) async {
    final auth = FakeAuthRepository()
      ..signedInUser = 'layout-user'
      ..administrator = true;
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('专注链'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-history-entry')));
    await tester.pumpAndSettle();
    expect(find.text('完成或结束专注后，记录会显示在这里。'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus-history-entry')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('个人数据仅属于你'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('用户管理'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('admin-users-entry')));
    await tester.pumpAndSettle();
    expect(find.text('管理员：用户停用与恢复'), findsOneWidget);
    expect(find.text('管理员：注册资格'), findsOneWidget);
    expect(find.text('管理员：重置用户密码'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-users-entry')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('保存节点备注后再次编辑会显示最新内容', (tester) async {
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    final focusRepository = _HistoryFocusRepository();
    await tester.pumpWidget(
      PactaApp(
        authRepository: auth,
        focusRepositoryFactory: (_) => focusRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('专注链'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-history-entry')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑节点备注'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '旧备注',
    );
    await tester.enterText(find.byType(TextField), '更新后的备注');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑节点备注'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '更新后的备注',
    );
    expect(focusRepository.note, '更新后的备注');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _HistoryFocusRepository extends UnavailableFocusRepository {
  String note = '旧备注';

  @override
  Stream<List<focus.FocusSession>> watchSessions() => Stream.value([
    focus.FocusSession(
      id: 'session',
      taskId: 'task',
      mode: focus.FocusChainMode.regular,
      durationSeconds: 600,
      startedAt: DateTime.utc(2026, 10, 4, 8),
      endsAt: DateTime.utc(2026, 10, 4, 8, 10),
      status: focus.FocusSessionStatus.completed,
      completedAt: DateTime.utc(2026, 10, 4, 8, 10),
      effectiveSeconds: 600,
    ),
  ]);

  @override
  Future<List<focus.FocusNode>> getNodes() async => [
    focus.FocusNode(
      id: 'node',
      sessionId: 'session',
      taskId: 'task',
      mode: focus.FocusChainMode.regular,
      createdAt: DateTime.utc(2026, 10, 4, 8, 10),
      effectiveSeconds: 600,
      note: note,
    ),
  ];

  @override
  Future<void> updateNodeNote({
    required String nodeId,
    required String note,
  }) async {
    this.note = note;
  }
}
