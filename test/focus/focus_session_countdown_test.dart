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
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/ui/pacta_date_format.dart';

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

  testWidgets('进行中操作区上下两层：暂停与提前完成等宽同行，放弃独占下一行', (tester) async {
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

    const pauseKey = ValueKey('focus-session-pause-button');
    const earlyKey = ValueKey('focus-session-early-complete-button');
    const abandonKey = ValueKey('focus-session-abandon-button');
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('提前完成'), findsOneWidget);
    expect(find.text('放弃专注'), findsOneWidget);
    expect(find.text('依据规则提前完成'), findsNothing, reason: '旧文案收短为「提前完成」');

    final pause = tester.getRect(find.byKey(pauseKey));
    final early = tester.getRect(find.byKey(earlyKey));
    final abandon = tester.getRect(find.byKey(abandonKey));
    expect(
      pause.top,
      moreOrLessEquals(early.top, epsilon: 0.5),
      reason: '两颗按钮同一排',
    );
    expect(pause.bottom, moreOrLessEquals(early.bottom, epsilon: 0.5));
    expect(
      pause.width,
      moreOrLessEquals(early.width, epsilon: 0.5),
      reason: 'Expanded 两颗等宽',
    );
    expect(
      early.left - pause.right,
      moreOrLessEquals(PactaSpacing.sm, epsilon: 0.5),
      reason: '中间只留一档 8dp',
    );
    expect(abandon.top, greaterThan(pause.bottom), reason: '放弃独占下一行');
    expect(abandon.height, greaterThanOrEqualTo(48), reason: '命中区不小于 48dp');
    expect(abandon.center.dx, moreOrLessEquals(210, epsilon: 1), reason: '居中');

    final theme = Theme.of(tester.element(find.byKey(abandonKey)));
    expect(
      tester
          .widget<TextButton>(find.byKey(abandonKey))
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{}),
      theme.colorScheme.error,
      reason: '破坏性动作走错误色文字',
    );
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('已结算页面可事后判定失败：节点移除、链重算、入口收起', (tester) async {
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
    h.now = session.endsAt;
    await _tick(tester);
    await _tick(tester);
    expect(find.text('00:00'), findsOneWidget);
    expect(await h.focus.getNodes(), hasLength(1));

    const markFailedKey = ValueKey('focus-session-mark-failed-button');
    expect(find.byKey(markFailedKey), findsOneWidget);
    await tester.tap(find.byKey(markFailedKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('填写失败原因'), findsOneWidget);
    expect(find.textContaining('将删除本次生成的专注节点'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '事后发现并没有真的专注');
    await tester.tap(find.widgetWithText(FilledButton, '确认改判'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final failed = (await h.focus.getSession(session.id))!;
    expect(failed.isFailed, isTrue);
    expect(failed.failureReason, '事后发现并没有真的专注');
    expect(failed.effectiveSeconds, 1500, reason: '有效专注时长原样保留');
    expect(await h.focus.getNodes(), isEmpty, reason: '专注节点已移除');
    final record = (await h.focus.getChainRecords()).singleWhere(
      (entry) => entry.mode == FocusChainMode.regular,
    );
    expect(record.currentConsecutive, 0);
    expect(record.bestConsecutive, 0, reason: '链连击按完整历史重算');
    expect(find.byKey(markFailedKey), findsNothing, reason: '失败态不再提供二次改判');
    expect(find.textContaining('本次专注已失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('前台主动放弃只清常驻通知，不再补发系统结束通知', (tester) async {
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
    final syncsAfterOpen = h.notifications.syncCalls;

    h.now = h.now.add(const Duration(minutes: 3));
    await tester.tap(
      find.byKey(const ValueKey('focus-session-abandon-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('放弃专注'), findsWidgets, reason: '弹窗标题与按钮同名');
    await tester.enterText(find.byType(TextField), '被临时会议打断');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect((await h.focus.getSession(session.id))?.isFailed, isTrue);
    expect(h.notifications.sessionEndedCalls, 0, reason: '前台主动结束不再补发系统通知');
    expect(
      h.notifications.syncCalls,
      greaterThan(syncsAfterOpen),
      reason: '仍要清掉进行中的常驻通知与待发闹钟',
    );
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('自然到点仍然推送一次结束通知', (tester) async {
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
    expect(h.notifications.sessionEndedCalls, 0);

    h.now = session.endsAt;
    await _tick(tester);
    await _tick(tester);

    expect(find.text('00:00'), findsOneWidget);
    expect(h.notifications.sessionEndedCalls, 1, reason: '自然结算由轮询补发且只发一次');
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

  testWidgets('倒计时卡显示预计结束时间，并去掉冗余说教文案', (tester) async {
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

    expect(
      find.byKey(const ValueKey('focus-session-countdown-card')),
      findsOneWidget,
    );
    expect(find.textContaining('预计 '), findsOneWidget);
    expect(find.text('已暂停，预计时间待继续'), findsNothing);
    // 结算规则不再在计时页复述：两句说教都必须消失。
    expect(find.textContaining('倒计时归零后自动结算'), findsNothing);
    expect(find.textContaining('任务仍需你单独确认完成'), findsNothing);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('暂停时预计结束时间改为「已暂停，预计时间待继续」', (tester) async {
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
    h.now = h.now.add(const Duration(minutes: 3));
    await h.focus.pauseSession(session.id, ruleText: '需要短暂离开');
    await _tick(tester);

    expect(find.text('已暂停，预计时间待继续'), findsOneWidget);
    expect(find.textContaining('预计 '), findsNothing);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('预约准备页去掉冗余说教，并给出预计进入专注时间', (tester) async {
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

    expect(find.textContaining('本场准备 10 分钟'), findsOneWidget);
    expect(find.textContaining('预计 '), findsOneWidget);
    expect(find.textContaining('进入专注'), findsWidgets);
    expect(find.textContaining('不需要再次点击'), findsNothing);
    expect(find.textContaining('准备阶段不能暂停'), findsNothing);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  testWidgets('800×600 矮视口下预约准备页的保存配置按钮无需滚动即可点', (tester) async {
    final h = _Fixture();
    addTearDown(h.dispose);
    final task = await h.seed();
    final appointment = await h.focus.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
      preparation: const Duration(minutes: 15),
    );
    await h.pumpPage(
      tester,
      AppointmentPreparationPage(
        appointment: appointment,
        taskTitle: _taskTitle,
      ),
    );
    // 桌面矮视口：倒计时卡 + 配置卡必须一屏装得下，否则「保存配置」会被
    // 挤到 y > 600，tap 只会在屏幕外命中。
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    final save = find.text('保存配置（不重置准备时间）');
    final rect = tester.getRect(save);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600), reason: '保存配置按钮完整落在视口内');
    // 页面只有一个纵向滚动容器；配置卡里的输入框各自带一个横向 Scrollable，
    // 这也正是 scrollUntilVisible 必须显式点名纵向列表的原因。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
      findsOneWidget,
    );
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });

  test('startSession 在全部前置检查之后才采样 startedAt', () async {
    var now = DateTime.utc(2026, 11, 15, 8);
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final tasks = LocalTaskRepository(
      database: database,
      userId: 't09',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    addTearDown(tasks.dispose);
    final goal = await tasks.createGoal(
      const GoalDraft(title: '采样目标', classification: TaskClassification.both),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(title: '采样任务', classification: TaskClassification.both),
    );
    // 前置查询（结算、冲突检查）在这套夹具里耗时 3 秒：采样必须发生在它们
    // 之后，否则 startedAt 会倒退 3 秒，页面一进来就少 3 秒。
    final focus = _SlowPrecheckFocusRepository(
      database: database,
      userId: 't09',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
      onSlowQuery: () => now = now.add(const Duration(seconds: 3)),
    );
    addTearDown(focus.dispose);

    final session = await focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );

    expect(session.startedAt, now, reason: '前置查询消耗的 3 秒不能算进已开始的专注');
    expect(session.endsAt, now.add(const Duration(minutes: 25)));
    expect(session.effectiveIntervals.single.startedAt, session.startedAt);
  });

  test('formatPactaTimeInZone 按账号时区换算，未知时区退回本地时间', () {
    final endsAt = DateTime.utc(2026, 11, 15, 8, 25);
    expect(formatPactaTimeInZone(endsAt, timeZoneId: 'Asia/Shanghai'), '16:25');
    expect(formatPactaTimeInZone(endsAt, timeZoneId: 'Etc/UTC'), '08:25');
    final local = endsAt.toLocal();
    expect(
      formatPactaTimeInZone(endsAt, timeZoneId: null),
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}',
    );
    expect(
      formatPactaTimeInZone(endsAt, timeZoneId: 'Not/AZone'),
      formatPactaTimeInZone(endsAt, timeZoneId: null),
    );
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

/// 慢前置查询的仓储：`getActiveSession` 消耗 3 秒，用来锁住采样时机。
class _SlowPrecheckFocusRepository extends LocalFocusRepository {
  _SlowPrecheckFocusRepository({
    required super.database,
    required super.userId,
    required super.remote,
    super.cloudSyncEnabled,
    super.now,
    required this.onSlowQuery,
  });

  final void Function() onSlowQuery;

  @override
  Future<FocusSession?> getActiveSession() {
    onSlowQuery();
    return super.getActiveSession();
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
