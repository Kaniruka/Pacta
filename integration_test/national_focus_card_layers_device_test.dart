// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';

/// Re-runnable screenshot fixture for the lightweight card layering (#91).
///
/// Runs the real [PactaApp] with its real theme, fake authentication and real
/// local repositories, then walks the card layers in the National Focus
/// destination: node sheet, detail, card editor and strengthening management.
///
/// Windows (RepaintBoundary into NF_CARD_LAYERS_CAPTURE_DIR):
///   flutter test integration_test/national_focus_card_layers_device_test.dart -d windows
///
/// Android (surface screenshot exported by the shared UI evidence driver):
///   flutter drive --driver=test_driver/ui_layout_acceptance_test.dart
///     --target=integration_test/national_focus_card_layers_device_test.dart -d DEVICE_ID
///   with UI_EVIDENCE_SUBDIR=national-focus-card-layers and, for a strict rerun,
///   UI_EVIDENCE_FAIL_ON_EXIST=1.
///
/// Optional dart-defines for both platforms: NF_CARD_LAYERS_THEME
/// (light|dark|system) and NF_CARD_LAYERS_WIDTH (logical pixels, >= 320).
const _user = 'national-focus-card-layers-device';
const _desktopCaptureDir = String.fromEnvironment(
  'NF_CARD_LAYERS_CAPTURE_DIR',
  defaultValue: 'build/ui-layout-evidence/national-focus-card-layers',
);
const _theme = String.fromEnvironment(
  'NF_CARD_LAYERS_THEME',
  defaultValue: 'system',
);
const _width = String.fromEnvironment('NF_CARD_LAYERS_WIDTH');
const _nativeHoldMs = int.fromEnvironment('NF_CARD_LAYERS_NATIVE_HOLD_MS');
const _mouseReview = bool.fromEnvironment('NF_CARD_LAYERS_MOUSE_REVIEW');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策卡轻量分层真实设备截图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 11, 13, 9);
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
    );
    final boundaryKey = GlobalKey();
    final capturedNames = <String>{};
    var androidSurfaceReady = false;

    Future<void> shot(String state) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final name = 'national-focus-card-layers-$state';
      if (!capturedNames.add(name)) fail('截图名重复：$name');
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else if (Platform.isWindows) {
        final object = boundaryKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          fail('截图「$name」未找到 RepaintBoundary');
        }
        final image = await object.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) fail('截图「$name」PNG 编码失败');
          final directory = Directory(_desktopCaptureDir);
          await directory.create(recursive: true);
          final file = File(
            '${directory.path}${Platform.pathSeparator}$name.png',
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
      print(
        '[national-focus-card-layers] platform=${Platform.operatingSystem} '
        'shot=$name',
      );
      if (Platform.isAndroid &&
          _nativeHoldMs > 0 &&
          (state == '05c-card-editor-exceptions-focused' ||
              state == '05c2-card-editor-exceptions-collapsed')) {
        print('[native-capture-ready] state=$state');
        final holdUntil = DateTime.now().add(
          Duration(milliseconds: _nativeHoldMs),
        );
        while (DateTime.now().isBefore(holdUntil)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
      }
      expect(tester.takeException(), isNull, reason: '截图 $name 不应抛异常');
    }

    Future<void> pumpUi() async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> settleNativeKeyboard({required bool visible}) async {
      if (!Platform.isAndroid) return;
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while ((tester.view.viewInsets.bottom > 0) != visible &&
          DateTime.now().isBefore(deadline)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(
        tester.view.viewInsets.bottom > 0,
        visible,
        reason: 'Wait for actual Android IME metrics before capturing the focused/collapsed state.',
      );
      // Let EditableText's caret scrolling settle after the native resize.
      for (var frame = 0; frame < 6; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      print(
        '[native-ime-metrics] visible=$visible bottom=${tester.view.viewInsets.bottom}',
      );
    }

    Future<NationalFocusCard> createTreeCard({
      required String name,
      required String action,
      String? exceptionNotes,
      List<String> levels = const [],
    }) async {
      final created = await tree.createCard(
        NationalFocusCardDraft(
          name: name,
          action: action,
          exceptionNotes: exceptionNotes,
        ),
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

    Future<void> openNode(NationalFocusCard card) async {
      final node = find.byKey(ValueKey('national-focus-node-${card.id}'));
      expect(node, findsOneWidget, reason: '国策节点「${card.name}」应在树中');
      await tester.ensureVisible(node);
      await tester.tap(
        node,
        kind: _mouseReview
            ? ui.PointerDeviceKind.mouse
            : ui.PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapText(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(
        target,
        kind: _mouseReview
            ? ui.PointerDeviceKind.mouse
            : ui.PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '操作「$label」不应抛异常');
    }

    Future<void> back() async {
      // 中文系统里 BackButton 的 tooltip 是「返回」，pageBack() 找不到英文
      // 'Back'；直接命中栈顶页面的 BackButton，找不到时才退回 pageBack。
      final button = find.byType(BackButton);
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button.last);
        await tester.pumpAndSettle();
        await tester.tap(
          button.last,
          kind: _mouseReview
              ? ui.PointerDeviceKind.mouse
              : ui.PointerDeviceKind.touch,
        );
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '返回上一页不应抛异常');
    }

    /// 顶栏动作没有文字标签时按 Key 命中，保持 48dp 命中区不变。
    Future<void> tapKey(String value) async {
      final target = find.byKey(ValueKey(value));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(
        target,
        kind: _mouseReview
            ? ui.PointerDeviceKind.mouse
            : ui.PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '操作「$value」不应抛异常');
    }

    try {
      if (_theme == 'light' || _theme == 'dark') {
        tester.platformDispatcher.platformBrightnessTestValue =
            _theme == 'light' ? Brightness.light : Brightness.dark;
      } else if (_theme != 'system') {
        fail('NF_CARD_LAYERS_THEME 只支持 light、dark 或 system');
      }
      if (_width.trim().isNotEmpty) {
        if (Platform.isAndroid) {
          fail('Android 窄屏验收请调整模拟器实际显示密度，不覆盖测试视图尺寸。');
        }
        final width = int.tryParse(_width.trim());
        if (width == null || width < 320) {
          fail('NF_CARD_LAYERS_WIDTH 必须是至少 320 的逻辑像素宽度');
        }
        tester.view.physicalSize = Size(
          width * tester.view.devicePixelRatio,
          tester.view.physicalSize.height,
        );
      }

      final morning = await createTreeCard(
        name: '晨光校准',
        action: '预定起床闹钟第一次响起时，打开床边灯，或拉开伸手可及的床帘；选最省力的一种即可。',
        exceptionNotes: '当天决定取消起床安排、继续休息，记“不适用”；正常触发却没有开灯或拉帘，记未完成。',
      );
      final strengthened = await createTreeCard(
        name: '写今日第一步',
        action: '坐到书桌前，写下今天最重要的第一步。',
        levels: const [
          '坐到书桌前，写下今天最重要的第一步，并读一遍今天的计划。',
          '坐到书桌前，写下今天最重要的第一步，读一遍计划并标注预计用时。',
        ],
      );
      await tree.selectStrengtheningLevel(
        cardId: strengthened.id,
        levelNumber: 1,
      );
      final atCap = await createTreeCard(
        name: '睡前复盘',
        action: '睡前用三分钟记下今天完成的事。',
        levels: const ['一级复盘', '二级复盘', '三级复盘', '四级复盘', '五级复盘'],
      );

      // 卡片库页签的截图样本：都不放入国策树，树视图、检查点结算与失败
      // 列表用例完全不受影响。
      final richLibraryCard = await tree.createCard(
        const NationalFocusCardDraft(
          name: '掩耳入夜',
          action: '每晚完成洗漱上铺准备入睡时（有课/工作日前夜 00:05 前，休息日前夜 01:55 前）。上铺躺平 5 分钟内即戴耳塞或开定时伴睡音，手机不再亮屏。',
          exceptionNotes: '发烧或等紧急电话时可记不适用。',
        ),
      );
      now = now.add(const Duration(seconds: 1));
      await tree.saveStrengtheningLevel(
        cardId: richLibraryCard.id,
        draft: const NationalFocusStrengtheningLevelDraft(
          action: '上铺躺平 3 分钟内即戴耳塞或开定时伴睡音，手机提前放至床尾。',
        ),
      );
      await tree.selectStrengtheningLevel(
        cardId: richLibraryCard.id,
        levelNumber: 1,
      );
      // 2 天成功日直接落库：卡片库外壳要展示进度摘要与内化轨，而不是空条。
      await (database.update(database.localNationalFocusCards)
            ..where((row) => row.userId.equals(_user))
            ..where((row) => row.id.equals(richLibraryCard.id)))
          .write(
            const LocalNationalFocusCardsCompanion(successfulDays: Value(2)),
          );
      now = now.add(const Duration(seconds: 1));

      final plainLibraryCard = await tree.createCard(
        const NationalFocusCardDraft(
          name: '手机先下班',
          action: '每晚准备上床入睡前，确认次日闹钟已开、插上充电线，将手机屏幕朝下放进床头挂袋，上床后不再拿回手中。',
        ),
      );
      now = now.add(const Duration(seconds: 1));

      final deletedLibraryCard = await tree.createCard(
        const NationalFocusCardDraft(name: '旧睡前整理', action: '睡前花五分钟把书桌收干净再关灯。'),
      );
      now = now.add(const Duration(seconds: 1));
      // 软删除样本：只改数据行，不经过删除流程，确保「已删除」页签有卡可截。
      await (database.update(database.localNationalFocusCards)
            ..where((row) => row.userId.equals(_user))
            ..where((row) => row.id.equals(deletedLibraryCard.id)))
          .write(
            LocalNationalFocusCardsCompanion(
              deletedAt: Value(now),
              successfulDays: const Value(12),
            ),
          );

      for (final libraryCard in [
        richLibraryCard,
        plainLibraryCard,
        deletedLibraryCard,
      ]) {
        expect(
          libraryCard.isInTree,
          isFalse,
          reason: '库样本「${libraryCard.name}」不能进入国策树',
        );
      }

      final app = PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        focusNotificationService: DisabledFocusNotificationService(),
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      );
      await tester.pumpWidget(
        Platform.isWindows
            ? RepaintBoundary(key: boundaryKey, child: app)
            : app,
      );
      await pumpUi();
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is NavigationBar || widget is NavigationRail,
          ),
          matching: find.text('国策树'),
        ),
      );
      await pumpUi();
      await shot('01-tree');

      // 卡片库两个页签：外侧卡片（强化/内化/判例/进度/放入）与已删除恢复卡。
      await tapText('卡片库');
      await shot('01b-library-active');
      await tapText('已删除');
      await shot('01c-library-deleted');
      await back();

      await openNode(morning);
      await shot('02-node-sheet');
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('确认')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('熄灭')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      now = now.add(const Duration(days: 1));
      await tree.settleDueCheckpoints();
      await pumpUi();
      expect(
        (await tree.getCard(morning.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      await openNode(morning);
      final confirm = find.descendant(of: sheet, matching: find.text('确认'));
      final extinguish = find.descendant(of: sheet, matching: find.text('熄灭'));
      expect(
        tester.getCenter(confirm).dy,
        closeTo(tester.getCenter(extinguish).dy, 1),
      );
      await shot('02b-pending-actions-row');
      if (Platform.isWindows && _mouseReview) {
        final mouse = TestGesture(
          dispatcher: tester.sendEventToBinding,
          kind: ui.PointerDeviceKind.mouse,
          device: 9901,
          pointer: 9901,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(confirm));
        await tester.pumpAndSettle();
        await shot('02d-windows-confirm-hover');
        await mouse.removePointer();
        await tester.pumpAndSettle();
      }
      await tapText('查看详情');
      await shot('03-detail-collapsed');
      await tapText('例外与判例');
      await shot('04-detail-exceptions');
      await tapKey('national-focus-detail-edit');
      await shot('05-card-editor');
      await tapText('例外与判例');
      final notesField = find.byKey(
        const ValueKey('national-focus-exception-notes'),
      );
      await tester.ensureVisible(notesField);
      await tester.pumpAndSettle();
      await shot('05b-card-editor-exceptions-expanded');
      await tester.tap(notesField);
      await tester.pumpAndSettle();
      await settleNativeKeyboard(visible: true);
      final notesFocus = tester
          .widget<EditableText>(
            find.descendant(
              of: notesField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(notesFocus.hasFocus, isTrue);
      await shot('05c-card-editor-exceptions-focused');
      await tapText('例外与判例');
      expect(notesFocus.hasFocus, isFalse);
      await settleNativeKeyboard(visible: false);
      await shot('05c2-card-editor-exceptions-collapsed');
      await tapText('例外与判例');
      expect(
        tester.widget<TextFormField>(notesField).controller!.text,
        morning.exceptionNotes,
      );
      await shot('05d-card-editor-exceptions-reopened');
      await back();
      await back();
      expect(
        find.byKey(ValueKey('national-focus-node-${morning.id}')),
        findsOneWidget,
        reason: '从编辑页返回后应回到国策树',
      );

      await tree.extinguishCard(
        cardId: morning.id,
        failureReason: '界面验收样例：今天未执行。',
      );
      await pumpUi();
      await openNode(morning);
      expect(
        find.descendant(of: sheet, matching: find.text('点亮')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('确认')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('熄灭')),
        findsNothing,
      );
      await shot('02c-extinguished-single-action');
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await openNode(strengthened);
      await tapText('查看详情');
      await shot('06-detail-strengthened');
      await tapKey('national-focus-detail-edit');
      await tapText('强化要求');
      await shot('07-strengthening-manager');
      // 生效版本记录整块下线：没有历史白卡，也没有版本条目。
      expect(find.text('生效版本记录'), findsNothing);
      expect(
        find.byKey(const ValueKey('national-focus-version-history-card')),
        findsNothing,
      );
      // 当前选中行保持实底 card，并带左侧 3.5dp 主色强调条。
      final activeRow = find.byKey(
        const ValueKey('national-focus-strengthening-level-1'),
      );
      final activeBar = find.descendant(
        of: activeRow,
        matching: find.byKey(
          const ValueKey('national-focus-strengthening-active-bar'),
        ),
      );
      expect(activeBar, findsOneWidget);
      expect(
        tester.getSize(activeBar).width,
        moreOrLessEquals(3.5, epsilon: 0.01),
      );
      final activeMaterial = tester.widget<Material>(
        find.descendant(of: activeRow, matching: find.byType(Material)).first,
      );
      expect(
        activeMaterial.color,
        PactaSurfaces.of(tester.element(activeRow)).card,
      );
      await shot('07b-strengthening-solid-selected');
      final secondLevel = find.byKey(
        const ValueKey('national-focus-strengthening-level-2'),
      );
      // Editing an inactive level must not change the requirement in force.
      final editSecondLevel = find.descendant(
        of: secondLevel,
        matching: find.byTooltip('编辑强化等级 2'),
      );
      await tester.ensureVisible(editSecondLevel);
      await tester.pumpAndSettle();
      await tester.tap(editSecondLevel);
      await tester.pumpAndSettle();
      await shot('08a-strengthening-base-collapsed');
      await tapText('对照基础规则');
      await tester.ensureVisible(find.text(strengthened.action));
      await tester.pumpAndSettle();
      await shot('08-strengthening-level-editor');
      await back();
      // 当前档位只由选中段表达：回到管理页后「正在使用」仍在 1 级。
      final activeLevelBadge = find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-1')),
        matching: find.text('正在使用'),
      );
      await tester.ensureVisible(activeLevelBadge);
      await tester.pumpAndSettle();
      expect(activeLevelBadge, findsOneWidget);
      await back();
      expect(find.text('编辑国策卡'), findsOneWidget);
      await back();
      expect(find.text('国策卡详情'), findsOneWidget);
      await back();
      expect(
        find.byKey(ValueKey('national-focus-node-${strengthened.id}')),
        findsOneWidget,
        reason: '强化管理往返后应回到国策树',
      );

      await openNode(atCap);
      await tapText('查看详情');
      await tapKey('national-focus-detail-edit');
      await tapText('强化要求');
      await shot('09-strengthening-cap');
      expect(find.text('已达 5 级上限'), findsOneWidget);
      await back();
      await back();
      await back();
      expect(
        find.byKey(ValueKey('national-focus-node-${atCap.id}')),
        findsOneWidget,
        reason: '五级上限页返回后应回到国策树',
      );
      now = now.add(const Duration(days: 1));
      await tree.settleDueCheckpoints();
      expect(await tree.getFailures(), isNotEmpty);
      await pumpUi();
      await tester.ensureVisible(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tapText('失败记录');
      await shot('10-failure-history-collapsed');
      await tester.tap(find.textContaining(' 个节点').first);
      await tester.pumpAndSettle();
      await shot('10b-failure-history-expanded');

      final brightness = Theme.of(tester.element(find.byType(Scaffold).last))
          .brightness;
      final blockedCard = NationalFocusCard(
        id: 'layout-blocked-card',
        name: '待核对的晨光校准',
        action: '预定闹钟响起时打开床边灯。',
        triggerCondition: '',
        isInTree: true,
        state: NationalFocusCardState.pendingTodayConfirmation,
        createdAt: now,
        updatedAt: now,
      );
      final blockedApp = MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pactaTheme(brightness),
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: _LayoutBlockedRepository(blockedCard),
          ),
        ),
      );
      await tester.pumpWidget(
        Platform.isWindows
            ? RepaintBoundary(key: boundaryKey, child: blockedApp)
            : blockedApp,
      );
      await pumpUi();
      await shot('12-review-blocked-actions-row');
      expect(tester.takeException(), isNull);
    } finally {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await focus.dispose();
      await tasks.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}

/// Existing page-test seam for read-only presentation of a review-blocked card.
class _LayoutBlockedRepository extends UnavailableNationalFocusRepository {
  _LayoutBlockedRepository(this.card);
  final NationalFocusCard card;
  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value([card]);
  @override
  Future<List<NationalFocusCard>> getTreeCards() async => [card];
  @override
  Future<NationalFocusCard> getCard(String cardId) async => card;
}
