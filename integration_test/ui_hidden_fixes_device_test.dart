import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/sync/cloud_recovery_point.dart';
import 'package:pacta/src/sync/cloud_snapshot_history_page.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_card.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';

/// 隐秘 UI 缺陷整改的 7 状态真机截图夹具。
///
/// 一次运行依次复现本轮 7 处整改的可见结果：登录页双按钮、国策树详细卡
/// `LV0`/`LV1` 与同轴页头、下必为例分段卡 + 扩展 FAB、历史备份原子徽标、
/// 20:9 长屏顶对齐的强化要求与编辑资料、专注历史溢出菜单。
///
/// Windows（RepaintBoundary 写入 UI_HIDDEN_FIXES_CAPTURE_DIR，默认
/// Size(393, 873) 的 20:9 长屏逻辑尺寸）：
///   flutter test integration_test/ui_hidden_fixes_device_test.dart -d windows
///
/// Android（surface 截图交给共享证据驱动）：
///   flutter drive --driver=test_driver/ui_layout_acceptance_test.dart
///     --target=integration_test/ui_hidden_fixes_device_test.dart -d DEVICE_ID
///   with UI_EVIDENCE_SUBDIR=ui-hidden-fixes.
///
/// 双端通用 dart-define：UI_HIDDEN_FIXES_THEME=light|dark|system。
const _user = 'ui-hidden-fixes-device';
const _cloudDeviceName = '2206123SC (Android)';
const _cloudRowCount = 201;
const _captureDir = String.fromEnvironment(
  'UI_HIDDEN_FIXES_CAPTURE_DIR',
  defaultValue: 'build/ui-layout-evidence/ui-hidden-fixes',
);
const _theme = String.fromEnvironment(
  'UI_HIDDEN_FIXES_THEME',
  defaultValue: 'system',
);

/// 20:9 长屏逻辑尺寸：16:9 模拟器看不到顶部居中留下的那一大截空白。
const _tallLogicalSize = Size(393, 873);

/// 本轮必须产出的 7 张截图（文件名即状态名）。
const _expectedShots = <String>[
  '01-auth-screen',
  '02-tree-detailed-lv',
  '03-precedent-rules',
  '04-cloud-history',
  '05-strengthening-tall',
  '06-profile-edit-tall',
  '07-focus-history-menu-open',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('隐秘 UI 缺陷 7 状态真机截图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 11, 25, 9);
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    final profile = LocalProfileRepository(
      database: database,
      userId: _user,
      now: () => now,
    );
    final cloudRemote = InMemoryCloudSnapshotRemote();
    final cloud = CloudSnapshotRepository(
      database: database,
      remote: cloudRemote,
      userId: _user,
      deviceId: 'ui-hidden-fixes-device-id',
      deviceName: _cloudDeviceName,
      now: () => now,
    );
    final boundaryKey = GlobalKey();
    final capturedNames = <String>{};
    var androidSurfaceReady = false;

    Future<void> shot(String state) async {
      // 无网络夹具里数据同步卡会弹一次「云端检查失败」提示：截图只留被验收的
      // 页面本身，进入截图前先清掉浮层提示。
      final scaffolds = find.byType(Scaffold);
      if (scaffolds.evaluate().isNotEmpty) {
        ScaffoldMessenger.maybeOf(tester.element(scaffolds.last))
            ?.clearSnackBars();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      if (!capturedNames.add(state)) fail('截图名重复：$state');
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(state);
      } else if (Platform.isWindows) {
        final object = boundaryKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          fail('截图「$state」未找到 RepaintBoundary');
        }
        final image = await object.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) fail('截图「$state」PNG 编码失败');
          final directory = Directory(_captureDir);
          await directory.create(recursive: true);
          final file = File(
            '${directory.path}${Platform.pathSeparator}$state.png',
          );
          if (await file.exists()) {
            fail('拒绝覆盖截图文件：${file.absolute.path}');
          }
          await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
      } else {
        fail(
          '此 fixture 只支持 Android 与 Windows；当前平台为 ${Platform.operatingSystem}',
        );
      }
      debugPrint(
        '[ui-hidden-fixes] platform=${Platform.operatingSystem} shot=$state',
      );
      expect(tester.takeException(), isNull, reason: '截图 $state 不应抛异常');
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapFinder(Finder target, String label) async {
      expect(target, findsWidgets, reason: '找不到「$label」');
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
      await tester.tap(target.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '操作「$label」不应抛异常');
    }

    Future<void> tapText(String label) => tapFinder(find.text(label), label);

    Future<void> tapKey(String value) =>
        tapFinder(find.byKey(ValueKey(value)), value);

    Future<void> openDestination(String label) async {
      final target = find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is NavigationBar || widget is NavigationRail,
        ),
        matching: find.text(label),
      );
      await tapFinder(target, '目的地 $label');
      await settle(tester);
    }

    Future<void> back() async {
      // 中文系统里 BackButton 的 tooltip 是「返回」，pageBack() 找不到英文
      // 'Back'；先命中栈顶页面的 BackButton，兜底才退回 pageBack。
      final button = find.byType(BackButton);
      if (button.evaluate().isNotEmpty) {
        await tapFinder(button.last, '返回');
      } else {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: '返回上一页不应抛异常');
    }

    Future<NationalFocusCard> createTreeCard({
      required String name,
      required String action,
      List<String> levels = const [],
    }) async {
      final created = await tree.createCard(
        NationalFocusCardDraft(name: name, action: action),
      );
      now = now.add(const Duration(seconds: 1));
      await tree.placeCard(cardId: created.id, parentId: null);
      await tree.lightCard(created.id);
      for (final level in levels) {
        await tree.saveStrengtheningLevel(
          cardId: created.id,
          draft: NationalFocusStrengtheningLevelDraft(action: level),
        );
        now = now.add(const Duration(seconds: 1));
      }
      return tree.getCard(created.id);
    }

    try {
      if (_theme == 'light' || _theme == 'dark') {
        tester.platformDispatcher.platformBrightnessTestValue =
            _theme == 'light' ? Brightness.light : Brightness.dark;
      } else if (_theme != 'system') {
        fail('UI_HIDDEN_FIXES_THEME 只支持 light、dark 或 system');
      }
      // 20:9 长屏：Windows 端显式收成 393×873 逻辑像素，Android 用真机尺寸。
      if (Platform.isWindows) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            _tallLogicalSize * tester.view.devicePixelRatio;
      }

      // ---- 01 登录页：未登录 → 底部并排「受邀注册 + 登录」，无顶部分段控件 ----
      final signedOut = FakeAuthRepository();
      await tester.pumpWidget(
        Platform.isWindows
            ? RepaintBoundary(
                key: boundaryKey,
                child: PactaApp(authRepository: signedOut),
              )
            : PactaApp(authRepository: signedOut),
      );
      await settle(tester);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      await shot('01-auth-screen');

      // 切换到已登录壳：之后的 6 个状态都走真实 PactaApp 导航。
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '交付今天的重点',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理材料',
          classification: TaskClassification.regular,
        ),
      );
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      now = session.endsAt;
      await focus.settleDueSessions();
      await focus.createPrecedentRule(text: '接听家人电话时允许短暂离开，回来后继续。');
      await focus.createPrecedentRule(text: '喝水或去洗手间可以暂停，回来再继续。');

      final lv0Card = await createTreeCard(
        name: '晨光校准',
        action: '闹钟第一次响起时打开床边灯，或拉开伸手可及的床帘。',
      );
      final lv1Card = await createTreeCard(
        name: '写今日第一步',
        action: '坐到书桌前，写下今天最重要的第一步。',
        levels: const ['坐到书桌前，写下今天最重要的第一步，并读一遍今天的计划。'],
      );
      await tree.selectStrengtheningLevel(cardId: lv1Card.id, levelNumber: 1);

      // 云端历史：记录数精确凑到 201，徽标文案才是「201 条记录」。
      var cloudState = await cloud.captureLocalState();
      if (cloudState.rowCount < _cloudRowCount) {
        final missing = _cloudRowCount - cloudState.rowCount;
        await database.batch((batch) {
          batch.insertAll(database.localGoals, [
            for (var index = 0; index < missing; index++)
              LocalGoalsCompanion.insert(
                userId: _user,
                id: 'hidden-fixes-goal-$index',
                title: '归档目标 ${index + 1}',
                classification: 'regular',
                createdAt: now,
                updatedAt: now,
              ),
          ]);
        });
        cloudState = await cloud.captureLocalState();
      }
      expect(cloudState.rowCount, _cloudRowCount, reason: '云端快照必须正好 201 条记录');
      await cloud.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: cloudState.fingerprint,
      );
      await DriftCloudRecoveryPointStore(database).save(
        CloudRecoveryPoint(
          id: 'hidden-fixes-point-1',
          userId: _user,
          createdAt: DateTime.utc(2026, 11, 24, 20),
          reason: CloudRecoveryReason.beforeCloudRestore,
          dataUpdatedAt: cloudState.dataUpdatedAt,
          rowCount: cloudState.rowCount,
          payload: cloudState.payload,
        ),
      );

      final app = PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        focusNotificationService: DisabledFocusNotificationService(),
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
        profileRepositoryFactory: (_) => profile,
        cloudSnapshotRepositoryFactory: (_) => cloud,
        chainSignalsRepositoryFactory: (_) => ChainSignalsRepository(
          database: database,
          userId: _user,
          now: () => now,
        ),
        displayClock: () => now,
      );
      await tester.pumpWidget(
        Platform.isWindows
            ? RepaintBoundary(key: boundaryKey, child: app)
            : app,
      );
      await settle(tester);

      // ---- 02 国策树详细视图：LV0 + LV1 同屏，页头/工具栏/结算同一纵轴 ----
      await openDestination('国策树');
      await tapText('简洁视图');
      await tapText('详细视图');
      expect(
        find.byKey(const ValueKey('national-focus-node-level-badge')),
        findsWidgets,
      );
      expect(find.text('LV0'), findsWidgets);
      expect(find.text('LV1'), findsOneWidget);
      expect(
        find.byKey(ValueKey('national-focus-node-${lv0Card.id}')),
        findsOneWidget,
        reason: '未强化的 LV0 卡与 LV1 卡同屏',
      );
      expect(
        find.byKey(const ValueKey('national-focus-checkpoint-summary')),
        findsOneWidget,
      );
      await shot('02-tree-detailed-lv');

      // ---- 05 强化要求：节点 → 查看详情 → 编辑 → 强化要求（20:9 顶对齐） ----
      await tester.ensureVisible(
        find.byKey(ValueKey('national-focus-node-${lv1Card.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('national-focus-node-${lv1Card.id}')),
      );
      await tester.pumpAndSettle();
      await tapText('查看详情');
      await tapKey('national-focus-detail-edit');
      await tapKey('national-focus-editor-strengthening-entry');
      expect(find.text('可用要求'), findsOneWidget);
      await shot('05-strengthening-tall');
      await back();
      await back();
      await back();

      // ---- 03 下必为例：AppBar ⓘ + 分段列表 + 扩展 FAB ----
      await openDestination('专注链');
      await tapText('下必为例');
      expect(
        find.byKey(const ValueKey('precedent-rules-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('precedent-rules-create')),
        findsOneWidget,
      );
      await shot('03-precedent-rules');
      await back();

      // ---- 07 专注历史：打开溢出菜单，目检对称留白与同字号红色危险项 ----
      await tapKey('focus-history-entry');
      await tapText('普通链');
      await tapFinder(find.byTooltip('更多操作'), '更多操作');
      expect(find.text('编辑节点备注'), findsOneWidget);
      expect(find.text('判定为失败'), findsOneWidget);
      await shot('07-focus-history-menu-open');
      // 先点空白处收起溢出菜单：菜单未关时点 AppBar 返回会被模态屏障拦下。
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await back();

      // ---- 06 编辑资料：我的 → 名片（20:9 顶对齐） ----
      await openDestination('我的');
      await tapFinder(find.byTooltip('编辑资料'), '编辑资料');
      expect(find.byKey(const Key('profile-avatar')), findsOneWidget);
      await shot('06-profile-edit-tall');
      await back();

      // ---- 04 历史备份：我的 → 数据同步 → 历史备份 ----
      // 后台云版本检查失败时数据同步卡会退化成「重试云端检查」，本夹具刻意不
      // 联网：先试真实入口，弹层没出现就直接从同一个 Navigator 进历史备份页，
      // 页面与数据仍是真实实现（真实仓储 + 内存远端）。
      await tapText('数据同步');
      if (find.text('历史备份').evaluate().isEmpty) {
        Navigator.of(tester.element(find.byType(CloudSyncCard))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CloudSnapshotHistoryPage(repository: cloud),
          ),
        );
        await settle(tester);
      } else {
        await tapText('历史备份');
      }
      expect(find.byKey(const ValueKey('cloud-history-list')), findsOneWidget);
      expect(find.text(_cloudDeviceName), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cloud-history-list')),
          matching: find.text('$_cloudRowCount 条记录'),
        ),
        findsOneWidget,
        reason: '云端快照徽标必须是一枚不拆字的「201 条记录」',
      );
      expect(
        find.byKey(const ValueKey('local-recovery-points-list')),
        findsOneWidget,
      );
      await shot('04-cloud-history');
      await back();

      expect(
        capturedNames,
        containsAll(_expectedShots),
        reason: '7 个整改状态都必须留下截图',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await profile.dispose();
      await tree.dispose();
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    }
  });
}
