import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

const _taskTitle = '整理今天需要完成的长中文任务并记录思路';

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

  testWidgets('预约准备时长可用 5/10/15 预填也可直接输入，并按本场时长进入专注', (tester) async {
    final h = _Fixture();
    await h.seed();
    await h.mount(tester);

    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();

    expect(find.text('5 分钟'), findsOneWidget);
    expect(find.text('10 分钟'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
    // 取消“自定义”开关：数字输入框始终可见，并与 chip 共用同一份状态。
    expect(find.text('自定义'), findsNothing);
    expect(find.text('预约准备时长（分钟）'), findsOneWidget);
    expect(find.text('1–60 分钟；超出范围或非整数不会开始预约。'), findsOneWidget);
    expect(find.text('开始准备（15分钟）'), findsOneWidget);
    expect(_preparationText(tester), '15');

    expect(find.text('25'), findsOneWidget);

    // 快捷 chip 直接预填输入框，并显示选中态。
    await tester.tap(find.text('10 分钟'));
    await tester.pump();
    expect(_preparationText(tester), '10');
    expect(_preparationChip(tester, '10 分钟').selected, isTrue);
    expect(_preparationChip(tester, '5 分钟').selected, isFalse);
    expect(_preparationChip(tester, '15 分钟').selected, isFalse);
    expect(find.text('开始准备（10分钟）'), findsOneWidget);

    // 手动输入非预设值时三个 chip 全部回到未选中态。
    await tester.enterText(_preparationField(), '7');
    await tester.pump();
    expect(_preparationText(tester), '7');
    for (final minutes in [5, 10, 15]) {
      expect(
        _preparationChip(tester, '$minutes 分钟').selected,
        isFalse,
        reason: '输入 7 时 $minutes 分钟不应选中',
      );
    }
    expect(find.text('开始准备（7分钟）'), findsOneWidget);

    // 输入恰好等于预设值时，对应 chip 立刻回到选中态。
    await tester.enterText(_preparationField(), '10');
    await tester.pump();
    expect(_preparationChip(tester, '10 分钟').selected, isTrue);
    expect(find.text('开始准备（10分钟）'), findsOneWidget);

    // 本场正式专注时长仍在同一处展示与修改（回归项）。
    await tester.enterText(_durationField(), '40');
    await tester.pump();
    expect(find.text('40'), findsOneWidget);

    await tester.tap(find.text('开始准备（10分钟）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('预约准备'), findsOneWidget);
    final appointment = (await h.focus.getActiveAppointment())!;
    expect(appointment.preparationSeconds, 10 * 60);
    expect(appointment.durationSeconds, 40 * 60);
    expect(
      appointment.endsAt.difference(appointment.startedAt),
      const Duration(minutes: 10),
    );
    expect(find.text('10:00'), findsOneWidget);
    expect(find.textContaining('本场准备 10 分钟'), findsOneWidget);

    // 到点自动交接：准备页替换为可见的专注执行页，只记一次预约成功。
    h.now = appointment.endsAt;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('专注进行中'), findsOneWidget);
    expect(
      (await h.focus.getAppointment(appointment.id))!.status,
      AppointmentPreparationStatus.succeeded,
    );
    expect((await h.focus.getAppointmentChainRecord()).currentConsecutive, 1);
    await h.close(tester);
  });

  testWidgets('准备时长越界或非整数时就地拒绝，7 分钟自填边界可正常落库', (tester) async {
    final h = _Fixture();
    await h.seed();
    await h.mount(tester);

    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1–60 分钟'), findsOneWidget);

    for (final invalid in ['61', '0', '7.5', '-5', '']) {
      await tester.enterText(_preparationField(), invalid);
      await tester.pump();
      // 非法值不生成按钮之外的数字：按钮只显示“开始准备”。
      await tester.tap(find.text('开始准备'));
      await tester.pumpAndSettle();
      expect(
        find.text('准备时长需为 1–60 分钟的整数。'),
        findsOneWidget,
        reason: '输入 "$invalid" 必须就地拒绝',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await h.focus.getAppointments(), isEmpty);
      expect(await h.focus.getSessions(), isEmpty);
      for (final minutes in [5, 10, 15]) {
        expect(
          _preparationChip(tester, '$minutes 分钟').selected,
          isFalse,
          reason: '输入 "$invalid" 时 $minutes 分钟不应选中',
        );
      }
    }

    // 7 分钟是自填边界：不是预设档，但仍在 1–60 内，照常落库。
    await tester.enterText(_preparationField(), '7');
    await tester.pump();
    expect(find.text('开始准备（7分钟）'), findsOneWidget);
    await tester.tap(find.text('开始准备（7分钟）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('预约准备'), findsOneWidget);
    expect((await h.focus.getActiveAppointment())!.preparationSeconds, 7 * 60);
    await h.close(tester);
  });
}

Finder _durationField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == '时长（分钟）',
);

Finder _preparationField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == '预约准备时长（分钟）',
);

String _preparationText(WidgetTester tester) =>
    tester.widget<TextField>(_preparationField()).controller!.text;

ChoiceChip _preparationChip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

class _Fixture {
  var now = DateTime.utc(2026, 11, 15, 8);
  final db = PactaDatabase(NativeDatabase.memory());
  late final tasks = LocalTaskRepository(
    database: db,
    userId: 't08',
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  );
  late final focus = LocalFocusRepository(
    database: db,
    userId: 't08',
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => now,
  );
  late final tree = LocalNationalFocusRepository(
    database: db,
    userId: 't08',
    cloudSyncEnabled: false,
  );
  late final signals = ChainSignalsRepository(database: db, userId: 't08');

  Future<void> seed() async {
    final goal = await tasks.createGoal(
      const GoalDraft(title: '准备时长目标', classification: TaskClassification.both),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: _taskTitle,
        classification: TaskClassification.both,
      ),
    );
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 't08',
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
        chainSignalsRepositoryFactory: (_) => signals,
        displayClock: () => now,
      ),
    );
    await tester.pumpAndSettle();
    // 任务入口在计划页；看板只保留摘要。
    final navigation = find.byType(NavigationBar).evaluate().isNotEmpty
        ? find.byType(NavigationBar)
        : find.byType(NavigationRail);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('计划')),
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
