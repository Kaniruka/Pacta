import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:pacta/src/ui/pacta_page_header.dart';
import 'package:pacta/src/focus/focus_models.dart' as focus;
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/change_password_page.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_models.dart';
import 'package:pacta/src/profile/profile_repository.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('亮暗主题正文与主要操作达到4.5对比度', (tester) async {
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpWidget(PactaApp(authRepository: auth));
      await tester.pumpAndSettle();
      final colors = Theme.of(
        tester.element(
          find.descendant(
            of: find.byType(PactaPageHeader),
            matching: find.text('看板'),
          ),
        ),
      ).colorScheme;
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

  testWidgets('窄屏大字可访问五个入口且页面不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();
    for (final label in ['看板', '计划', '国策树', '专注链', '我的']) {
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

  testWidgets('窄屏底栏只展开选中项标题，五个入口都可切换', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();

    // Material 3 原生行为：未选中的目的地只画图标，标题跟随选中动画淡入淡出。
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      bar.labelBehavior,
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
    expect(bar.destinations, hasLength(5));

    double labelOpacity(String label) {
      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          matching: find.byType(FadeTransition),
        ),
      );
      return fades
          .firstWhere((fade) => fade.alwaysIncludeSemantics)
          .opacity
          .value;
    }

    const labels = ['看板', '计划', '国策树', '专注链', '我的'];
    expect(labelOpacity('看板'), moreOrLessEquals(1, epsilon: 0.01));
    for (final label in ['计划', '国策树', '专注链', '我的', '看板']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        labels.indexOf(label),
        reason: label,
      );
      expect(labelOpacity(label), moreOrLessEquals(1, epsilon: 0.01));
      for (final other in labels.where((item) => item != label)) {
        expect(
          labelOpacity(other),
          lessThan(0.05),
          reason: '$label 选中时 $other 的标题应收起',
        );
      }
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开屏动画播完即卸载覆盖层且不残留 Ticker', (tester) async {
    // 测试绑定下默认零等待：未显式开启时直接渲染 child。
    await tester.pumpWidget(
      MaterialApp(
        home: PactaSplashGate(
          key: const ValueKey('splash-default'),
          child: const Scaffold(body: Text('主界面')),
        ),
      ),
    );
    expect(find.byKey(PactaSplashGate.overlayKey), findsNothing);
    expect(find.text('主界面'), findsOneWidget);

    // 显式开启：620ms 入场 + 260ms 淡出，结束后覆盖层与品牌字标一起消失。
    await tester.pumpWidget(
      MaterialApp(
        home: PactaSplashGate(
          key: const ValueKey('splash-forced'),
          enableSplash: true,
          child: const Scaffold(body: Text('主界面')),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(PactaSplashGate.overlayKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(PactaSplashGate.overlayKey), findsOneWidget);
    expect(find.text('Pacta'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(PactaSplashGate.overlayKey), findsNothing);
    expect(find.text('Pacta'), findsNothing);
    expect(find.text('主界面'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('PactaApp 开启开屏后动画完成即展现应用外壳', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth, enableSplash: true));
    await tester.pump();
    expect(find.byKey(PactaSplashGate.overlayKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(PactaSplashGate.overlayKey), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(PactaSplashGate.overlayKey), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PactaPageHeader),
        matching: find.text('看板'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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

  testWidgets('专注历史与我的一级页面可进入可返回，管理员入口已彻底下线', (tester) async {
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(
      PactaApp(
        authRepository: auth,
        profileRepositoryFactory: (_) =>
            _LayoutProfileRepository('layout-user'),
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
    expect(find.byTooltip('编辑资料'), findsOneWidget);
    final myScrollable = find
        .descendant(of: find.byType(MyPage), matching: find.byType(Scrollable))
        .first;
    // 管理入口整块下线：分组列表里的「用户管理」与它的 Key 都不再存在。
    await tester.scrollUntilVisible(
      find.text('通知与设备权限'),
      160,
      scrollable: myScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('用户管理'), findsNothing);
    expect(find.byKey(const ValueKey('admin-users-entry')), findsNothing);

    // 名片「专注」组直达专注历史，不再是已删除的统计明细页。
    await tester.scrollUntilVisible(
      find.byTooltip('编辑资料'),
      -160,
      scrollable: myScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('专注'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusHistoryPage), findsOneWidget);
    expect(find.text('专注历史'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 我的 -> 编辑资料 -> 修改密码 -> 返回：全链路零异常。
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditPage), findsOneWidget);
    final editScrollable = find
        .descendant(
          of: find.byType(ProfileEditPage),
          matching: find.byType(Scrollable),
        )
        .first;
    final entry = find.byKey(const ValueKey('profile-change-password-entry'));
    await tester.scrollUntilVisible(entry, 160, scrollable: editScrollable);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordPage), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MyPage), findsOneWidget);
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

  testWidgets('一级页面页头行高与标题 y 坐标在同一视口下完全一致', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    const destinations = [
      // 看板页头标题已改回「看板」，与底部导航同名：查找必须限定在页头内。
      ('看板', '看板'),
      ('计划', '计划'),
      ('国策树', '国策树'),
      ('专注链', '专注链'),
      ('我的', '我的'),
    ];
    for (final size in [const Size(360, 800), const Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(PactaApp(authRepository: auth));
      await tester.pumpAndSettle();
      final measured =
          <String, ({double height, double titleY, double titleX})>{};
      for (final (label, title) in destinations) {
        final host = find.byType(NavigationBar).evaluate().isNotEmpty
            ? find.byType(NavigationBar)
            : find.byType(NavigationRail);
        await tester.tap(find.descendant(of: host, matching: find.text(label)));
        await tester.pumpAndSettle();
        final header = find.byType(PactaPageHeader);
        expect(header, findsOneWidget, reason: '$label 应只有一个页头');
        final headerRect = tester.getRect(header);
        final titleRect = tester.getRect(
          find.descendant(of: header, matching: find.text(title)),
        );
        measured[label] = (
          height: headerRect.height,
          titleY: titleRect.top,
          titleX: titleRect.left,
        );
      }
      final first = measured.values.first;
      for (final entry in measured.entries) {
        expect(
          entry.value.height,
          moreOrLessEquals(first.height, epsilon: 0.01),
          reason: '${size.width} 宽 ${entry.key} 页头高度一致',
        );
        expect(
          entry.value.titleY,
          moreOrLessEquals(first.titleY, epsilon: 0.01),
          reason: '${size.width} 宽 ${entry.key} 标题 y 坐标一致',
        );
        expect(
          entry.value.titleX,
          moreOrLessEquals(first.titleX, epsilon: 0.01),
          reason: '${size.width} 宽 ${entry.key} 标题左边距一致',
        );
      }
      expect(first.height, 56, reason: '48dp 标题行 + 8dp 固定下间距');
      expect(
        first.titleY,
        moreOrLessEquals(24, epsilon: 0.1),
        reason: '16dp 页顶 + 48dp 行内居中',
      );
      if (size.width < 720) {
        expect(first.titleX, 16, reason: '移动页边距 16');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('我的把系统日历与提醒合并成一张《通知与设备权限》入口', (tester) async {
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(of: find.byType(MyPage), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.text('通知与设备权限'),
      160,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('通知与设备权限'), findsOneWidget);
    expect(find.text('日历块'), findsNothing, reason: '不再单列日历卡片');
    expect(find.text('提醒与通知'), findsNothing, reason: '不再单列提醒卡片');
    expect(
      find.textContaining('系统日历只读导入'),
      findsOneWidget,
      reason: '副标题说明这张卡片同时覆盖日历只读导入',
    );

    await tester.tap(find.text('通知与设备权限'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusNotificationSettingsPage), findsOneWidget);
    // 三个分组标题就是合并后页面的大纲。
    for (final section in ['后台运行与系统权限', '后台倒计时与专注通知', '定时提醒']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(find.text('系统日历只读导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// 已就绪的账号资料仓库：让「我的」名片的编辑入口可用，从而走通
/// 编辑资料 -> 修改密码 -> 返回的完整链路。
class _LayoutProfileRepository implements ProfileRepository {
  _LayoutProfileRepository(this._userId);

  final String _userId;

  ProfileAccount get _account => ProfileAccount(
    userId: _userId,
    displayName: '布局用户',
    updatedAt: DateTime.utc(2026, 11, 1),
  );

  @override
  Stream<ProfileAccount> watchProfile() => Stream.value(_account);

  @override
  Future<ProfileAccount> getProfile() async => _account;

  @override
  Future<ProfileAccount> saveProfile({
    required String displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
    String? timeZoneId,
  }) async => _account;

  @override
  Future<ProfileAccount> ensureDisplayTimeZone({
    String? deviceTimeZoneId,
  }) async => _account;

  @override
  Future<ProfileAccount> syncProfile() async => _account;

  @override
  Future<void> dispose() async {}
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
