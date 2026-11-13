import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
  });
  setUpAll(() async {
    final path = Platform.environment['PACTA_UI_FONT'];
    if (path != null) {
      for (final name in ['Roboto', 'Segoe UI']) {
        await (FontLoader(
          name,
        )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
      }
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in [
    const Size(320, 800),
    const Size(411, 731),
    const Size(546, 682),
    const Size(1265, 682),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        '长中文设置信号 ${size.width} ${dark ? 'dark' : 'light'} 输入时两种开始动作保持可点',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final h = _Fixture();
          await h.seed();
          await h.mount(tester);
          await tester.tap(find.byTooltip('开始专注'));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            '${size.width.toInt()}-${dark ? 'dark' : 'light'}-setup',
          );
          expect(find.text('25'), findsOneWidget);
          expect(find.text('开始倒计时').hitTestable(), findsOneWidget);
          expect(find.text('开始准备（15分钟）').hitTestable(), findsOneWidget);
          if (size.width <= 411) {
            await tester.showKeyboard(find.byType(TextField));
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            await _capture(
              tester,
              '${size.width.toInt()}-${dark ? 'dark' : 'light'}-ime',
            );
            final inputBounds = tester.getRect(find.byType(TextField));
            final viewport = tester.getRect(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(SingleChildScrollView),
              ),
            );
            expect(inputBounds.top, greaterThanOrEqualTo(viewport.top));
            expect(inputBounds.bottom, lessThanOrEqualTo(viewport.bottom));
            expect(find.text('开始倒计时').hitTestable(), findsOneWidget);
            expect(find.text('开始准备（15分钟）').hitTestable(), findsOneWidget);
          }
          await tester.enterText(find.byType(TextField), '0');
          await tester.tap(find.text('开始倒计时'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await _capture(
            tester,
            '${size.width.toInt()}-${dark ? 'dark' : 'light'}-invalid',
          );
          final errorBounds = tester.getRect(find.text('请输入大于 0 的分钟数。'));
          final contentBounds = tester.getRect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SingleChildScrollView),
            ),
          );
          expect(errorBounds.top, greaterThanOrEqualTo(contentBounds.top));
          expect(errorBounds.bottom, lessThanOrEqualTo(contentBounds.bottom));
          expect(find.text('请输入大于 0 的分钟数。').hitTestable(), findsOneWidget);
          expect(await h.focus.getSessions(), isEmpty);
          expect(await h.focus.getAppointments(), isEmpty);
          await tester.tap(find.text('开始准备（15分钟）'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('请输入大于 0 的分钟数。').hitTestable(), findsOneWidget);
          expect(await h.focus.getAppointments(), isEmpty);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(await h.focus.getLastMode(), FocusChainMode.regular);
          await h.close(tester);
        },
      );
    }
  }

  for (final board in [true, false]) {
    testWidgets('${board ? '看板' : '专注链'}入口返回与恢复保留唯一会话，结算返回文案符合真实落点', (
      tester,
    ) async {
      final h = _Fixture();
      await h.seed();
      await h.mount(tester);
      if (!board) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('专注链'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择任务'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_taskTitle));
      } else {
        await tester.tap(find.byTooltip('开始专注'));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始倒计时'));
      await tester.pumpAndSettle();
      final id = (await h.focus.getActiveSession())!.id;
      await _capture(tester, '${board ? 'board' : 'focus'}-execution');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        board ? find.byType(BoardPage) : find.text('选择任务'),
        findsOneWidget,
      );
      await _capture(tester, '${board ? 'board' : 'focus'}-returned');
      await tester.tap(board ? find.byTooltip('开始专注') : find.text('选择任务'));
      await tester.pumpAndSettle();
      expect(find.text('专注进行中'), findsOneWidget);
      expect((await h.focus.getActiveSession())!.id, id);
      expect(await h.focus.getSessions(), hasLength(1));
      h.now = h.now.add(const Duration(minutes: 26));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await _capture(tester, '${board ? 'board' : 'focus'}-settled');
      expect(find.text('返回上一页'), findsOneWidget);
      await tester.tap(find.text('返回上一页'));
      await tester.pumpAndSettle();
      expect(
        board ? find.byType(BoardPage) : find.text('选择任务'),
        findsOneWidget,
      );
      await h.close(tester);
    });
  }

  testWidgets('看板开始准备后返回再进入恢复同一预约，不再打开设置', (tester) async {
    final h = _Fixture();
    await h.seed();
    await h.mount(tester);
    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始准备（15分钟）'));
    await tester.pumpAndSettle();
    expect(find.text('预约准备'), findsOneWidget);
    final appointment = (await h.focus.getActiveAppointment())!;
    expect(appointment.durationSeconds, 25 * 60);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BoardPage), findsOneWidget);
    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();
    expect(find.text('预约准备'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect((await h.focus.getActiveAppointment())?.id, appointment.id);
    expect(await h.focus.getAppointments(), hasLength(1));
    expect(await h.focus.getSessions(), isEmpty);
    await _capture(tester, 'board-restored-appointment');
    await h.close(tester);
  });
}

const _taskTitle = '整理今天需要完成的长中文任务并记录思路与下一步行动';

class _Fixture {
  var now = DateTime.utc(2026, 11, 12, 8);
  final db = PactaDatabase(NativeDatabase.memory());
  late final tasks = LocalTaskRepository(
    database: db,
    userId: 't78',
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  );
  late final focus = LocalFocusRepository(
    database: db,
    userId: 't78',
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => now,
  );
  late final tree = LocalNationalFocusRepository(
    database: db,
    userId: 't78',
    cloudSyncEnabled: false,
  );
  late final signals = ChainSignalsRepository(database: db, userId: 't78');
  Future<void> seed() async {
    final goal = await tasks.createGoal(
      const GoalDraft(title: '设置验收目标', classification: TaskClassification.both),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: _taskTitle,
        classification: TaskClassification.both,
      ),
    );
    await signals.save(
      const ChainSignalTexts(
        appointmentTriggerSignal: '把手机放到书架上然后倒一杯温水，整理桌面并确认接下来只处理当前任务',
        focusMarker: '关掉所有通知并把任务目标读一遍，确认执行期间只专心完成这项任务',
      ),
    );
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('t78-root'),
        child: PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 't78',
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => tree,
          chainSignalsRepositoryFactory: (_) => signals,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await focus.dispose();
    await tasks.dispose();
    await tree.dispose();
    await db.close();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['PACTA_UI_EVIDENCE_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    await Directory(path).create(recursive: true);
    final file = File('$path/$name.png');
    if (await file.exists()) {
      throw StateError('Refusing to overwrite ${file.path}');
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('t78-root')),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}
