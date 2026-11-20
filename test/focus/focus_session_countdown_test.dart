import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/app/app_providers.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/focus/focus_session_pages.dart';
import 'package:pacta/src/focus/focus_setup_dialog.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

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

  testWidgets('专注进行中的倒计时随轮询实时刷新，且状态未变时不重复推送通知', (tester) async {
    final h = _Fixture();
    addTearDown(h.dispose);
    final task = await h.seed();
    final session = await h.focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await h.pumpPage(
      tester,
      FocusSessionPage(session: session, taskTitle: _taskTitle),
    );

    expect(find.text('专注进行中'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    final syncsAfterOpen = h.notifications.syncCalls;
    expect(syncsAfterOpen, greaterThanOrEqualTo(1));
    final progressBefore = _progress(tester);

    // 只推进 displayClock：status/endsAt/pausedAt 都没变，界面仍必须走秒。
    h.now = h.now.add(const Duration(seconds: 1));
    await _tick(tester);
    expect(find.text('24:59'), findsOneWidget);
    expect(find.text('25:00'), findsNothing);

    h.now = h.now.add(const Duration(seconds: 2));
    await _tick(tester);
    expect(find.text('24:57'), findsOneWidget);
    expect(_progress(tester), greaterThan(progressBefore));

    // 状态没有跳变：不得随每秒轮询重复同步或推送结束通知。
    expect(h.notifications.syncCalls, syncsAfterOpen);
    expect(h.notifications.sessionEndedCalls, 0);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('开始专注弹窗：三个预填 chip、始终可见的输入框与全宽纵向按钮', (tester) async {
    final h = _Fixture();
    addTearDown(h.dispose);
    final task = await h.seed();
    await h.pumpPage(
      tester,
      FocusSetupDialog(task: task, initialMode: FocusChainMode.regular),
    );

    expect(find.text('5 分钟'), findsOneWidget);
    expect(find.text('10 分钟'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
    expect(find.text('预约准备时长（分钟）'), findsOneWidget);
    expect(find.text('1–60 分钟；超出范围或非整数不会开始预约。'), findsOneWidget);
    expect(_preparationText(tester), '15');
    expect(find.text('开始准备（15分钟）'), findsOneWidget);

    // 规则说明收进浅色信息卡：默认不占正文高度，点 ⓘ 才展开原句。
    expect(
      find.byKey(const ValueKey('focus-setup-instructions')),
      findsOneWidget,
    );
    final info = find.byKey(const ValueKey('focus-setup-instructions-info'));
    expect(info, findsOneWidget);
    expect(find.text(focusSetupInstructionsMessage), findsNothing);
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.text(focusSetupInstructionsMessage), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();

    // 三个操作各占一行且等宽：右下角不再折行成阶梯。
    final start = tester.getRect(find.widgetWithText(FilledButton, '开始倒计时'));
    final prepare = tester.getRect(
      find.widgetWithText(OutlinedButton, '开始准备（15分钟）'),
    );
    final cancel = tester.getRect(find.widgetWithText(TextButton, '取消'));
    expect(start.bottom, lessThanOrEqualTo(prepare.top));
    expect(prepare.bottom, lessThanOrEqualTo(cancel.top));
    expect(start.width, prepare.width);
    expect(prepare.width, cancel.width);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('专注结算后停止轮询，页面未退栈也不再持续读库', (tester) async {
    final h = _Fixture();
    addTearDown(h.dispose);
    final task = await h.seed();
    final session = await h.focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await h.pumpPage(
      tester,
      FocusSessionPage(session: session, taskTitle: _taskTitle),
    );
    await _tick(tester);
    expect(h.focus.getSessionCalls, greaterThan(0));

    // 到点结算：显示 00:00 与返回入口，周期计时器随结算停止。
    h.now = session.endsAt;
    await _tick(tester);
    await _tick(tester);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('返回上一页'), findsOneWidget);
    final callsAfterSettle = h.focus.getSessionCalls;

    // 再推进 2 秒（8 个轮询周期）：已结算页面不得继续读库。
    h.now = h.now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(h.focus.getSessionCalls, callsAfterSettle);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('预约准备页的准备倒计时同样随轮询实时刷新', (tester) async {
    final h = _Fixture();
    addTearDown(h.dispose);
    final task = await h.seed();
    final appointment = await h.focus.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
      preparation: const Duration(minutes: 10),
    );
    await h.pumpPage(
      tester,
      AppointmentPreparationPage(
        appointment: appointment,
        taskTitle: _taskTitle,
      ),
    );

    expect(find.text('预约准备'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);

    h.now = h.now.add(const Duration(seconds: 1));
    await _tick(tester);
    expect(find.text('09:59'), findsOneWidget);
    expect(find.text('10:00'), findsNothing);

    h.now = h.now.add(const Duration(seconds: 1));
    await _tick(tester);
    expect(find.text('09:58'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });
}

/// 让 250ms 轮询跑完一次数据库读取并重建。
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

double _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value!;

Finder _preparationField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == '预约准备时长（分钟）',
);

String _preparationText(WidgetTester tester) =>
    tester.widget<TextField>(_preparationField()).controller!.text;

class _RecordingFocusNotifications extends DisabledFocusNotificationService {
  int syncCalls = 0;
  int sessionEndedCalls = 0;

  @override
  Future<void> sync({
    AppointmentPreparation? appointment,
    FocusSession? session,
    required String taskTitle,
  }) async {
    syncCalls++;
  }

  @override
  Future<void> sessionEnded({
    required String sessionId,
    String? appointmentId,
    required String taskTitle,
    required FocusSessionStatus status,
  }) async {
    sessionEndedCalls++;
  }
}

/// 记录轮询次数的仓储：结算后页面不应再读库。
class _CountingFocusRepository extends LocalFocusRepository {
  _CountingFocusRepository({
    required super.database,
    required super.userId,
    required super.remote,
    required super.cloudSyncEnabled,
    required DateTime Function() now,
  }) : super(now: now);

  int getSessionCalls = 0;

  @override
  Future<FocusSession?> getSession(String sessionId) {
    getSessionCalls++;
    return super.getSession(sessionId);
  }
}

class _Fixture {
  var now = DateTime.utc(2026, 11, 15, 8);
  final db = PactaDatabase(NativeDatabase.memory());
  final notifications = _RecordingFocusNotifications();
  late final tasks = LocalTaskRepository(
    database: db,
    userId: 't09',
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  );
  late final focus = _CountingFocusRepository(
    database: db,
    userId: 't09',
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => now,
  );
  late final signals = ChainSignalsRepository(database: db, userId: 't09');

  Future<Task> seed() async {
    final goal = await tasks.createGoal(
      const GoalDraft(title: '倒计时目标', classification: TaskClassification.both),
    );
    return tasks.createTask(
      goal.id,
      const TaskDraft(
        title: _taskTitle,
        classification: TaskClassification.both,
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusRepositoryProvider.overrideWithValue(focus),
          taskRepositoryProvider.overrideWithValue(tasks),
          chainSignalsRepositoryProvider.overrideWithValue(signals),
          displayClockProvider.overrideWithValue(() => now),
          focusNotificationServiceProvider.overrideWithValue(notifications),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    await focus.dispose();
    await tasks.dispose();
    await db.close();
  }
}
