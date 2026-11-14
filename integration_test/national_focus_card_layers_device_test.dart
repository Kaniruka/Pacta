// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_reconciliation_page.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
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
        await tester.runAsync(
          () => Future<void>.delayed(Duration(milliseconds: _nativeHoldMs)),
        );
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
      await tester.tap(node);
      await tester.pumpAndSettle();
    }

    Future<void> tapText(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '操作「$label」不应抛异常');
    }

    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '返回上一页不应抛异常');
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
      await tapText('查看详情');
      await shot('03-detail-collapsed');
      await tapText('例外与判例');
      await shot('04-detail-exceptions');
      await tapText('编辑卡片');
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
      await tapText('编辑卡片');
      await tapText('管理强化要求');
      await shot('07-strengthening-manager');
      await tester.scrollUntilVisible(
        find.textContaining('生效版本记录 ·'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.textContaining('生效版本记录 ·'));
      await tester.pumpAndSettle();
      await shot('07b-strengthening-history-expanded');
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
      await tapText('对照基础规则');
      await shot('08-strengthening-level-editor');
      await back();
      await tester.scrollUntilVisible(
        find.text('当前使用 · 强化等级 1'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('当前使用 · 强化等级 1'), findsOneWidget);
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
      await tapText('编辑卡片');
      await tapText('管理强化要求');
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
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tapText('检查点与失败记录');
      await tapText('查看失败记录');
      await shot('10-failure-history-collapsed');
      await tester.tap(find.textContaining(' 个节点').first);
      await tester.pumpAndSettle();
      await shot('10b-failure-history-expanded');

      final brightness = Theme.of(tester.element(find.byType(Scaffold).last))
          .brightness;
      final reviewApp = MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pactaTheme(brightness),
        home: NationalFocusReconciliationPage(
          repository: _LayoutReviewRepository(),
        ),
      );
      await tester.pumpWidget(
        Platform.isWindows
            ? RepaintBoundary(key: boundaryKey, child: reviewApp)
            : reviewApp,
      );
      await pumpUi();
      await tester.ensureVisible(find.text('查看完整来源操作').first);
      await tester.pumpAndSettle();
      await shot('11-review-source-collapsed');
      await tester.tap(find.text('查看完整来源操作').first);
      await tester.pumpAndSettle();
      await shot('11b-review-source-expanded');
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

/// Read-only layout sample, using the existing reconciliation page test seam.
/// No branch is adopted and no real account or cloud operation is invoked.
class _LayoutReviewRepository extends UnavailableNationalFocusRepository {
  @override
  Stream<NationalFocusReviewState> watchNationalFocusReviewState() {
    final effect = NationalFocusReconciliationCardEffect(
      cardId: 'sample-card',
      triggerCondition: '晨光校准',
      previousState: 'lit',
      newState: 'extinguished',
      previousParentId: null,
      newParentId: null,
      previousIsInTree: true,
      newIsInTree: true,
      previousSuccessfulDays: 10,
      newSuccessfulDays: 10,
      previousCurrentConsecutiveDays: 10,
      newCurrentConsecutiveDays: 0,
    );
    return Stream.value(
      NationalFocusReviewState(
        reconciliationCases: [
          NationalFocusReconciliationCase(
            id: 'layout-review',
            createdAt: DateTime.utc(2026, 11, 14),
            cardIds: const ['sample-card'],
            cardNames: const {'sample-card': '晨光校准'},
            options: [
              for (final source in ['手机', '电脑'])
                NationalFocusReconciliationOption(
                  sourceId: 'layout-$source',
                  effects: [effect],
                  operations: [
                    NationalFocusReconciliationOperation(
                      sourceId: 'layout-$source',
                      deviceId: source,
                      operation: 'extinguish_card',
                      occurredAt: DateTime.utc(2026, 11, 14),
                      effects: [effect],
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
