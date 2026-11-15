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

  testWidgets('预约准备时长可选 5/10/15 或自定义，并按本场时长进入专注', (tester) async {
    final h = _Fixture();
    await h.seed();
    await h.mount(tester);

    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();

    expect(find.text('5 分钟'), findsOneWidget);
    expect(find.text('10 分钟'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('开始准备（15分钟）'), findsOneWidget);

    expect(find.text('25'), findsOneWidget);

    await tester.tap(find.text('10 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('开始准备（10分钟）'), findsOneWidget);

    // 本场正式专注时长仍在同一处展示与修改（回归项）。
    await tester.enterText(find.byType(TextField).first, '40');
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

  testWidgets('自定义准备时长越界或非整数时就地拒绝且不创建预约', (tester) async {
    final h = _Fixture();
    await h.seed();
    await h.mount(tester);

    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1–60 分钟'), findsOneWidget);

    for (final invalid in ['61', '0', '7.5', '-5', '']) {
      await tester.enterText(find.byType(TextField).last, invalid);
      await tester.pump();
      await tester.tap(find.textContaining('开始准备'));
      await tester.pumpAndSettle();
      expect(
        find.text('准备时长需为 1–60 分钟的整数。'),
        findsOneWidget,
        reason: '输入 "$invalid" 必须就地拒绝',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await h.focus.getAppointments(), isEmpty);
      expect(await h.focus.getSessions(), isEmpty);
    }

    await tester.enterText(find.byType(TextField).last, '20');
    await tester.pump();
    expect(find.text('开始准备（20分钟）'), findsOneWidget);
    await tester.tap(find.text('开始准备（20分钟）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('预约准备'), findsOneWidget);
    expect((await h.focus.getActiveAppointment())!.preparationSeconds, 20 * 60);
    await h.close(tester);
  });
}

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
