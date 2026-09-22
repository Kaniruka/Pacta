import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote taskRemote;
  late InMemoryFocusRemote focusRemote;
  late LocalTaskRepository taskRepository;
  late LocalFocusRepository focusRepository;
  var now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    taskRemote = InMemoryTaskRemote();
    focusRemote = InMemoryFocusRemote();
    taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: taskRemote,
      now: () => now,
    );
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
  });

  tearDown(() async {
    await focusRepository.dispose();
    await taskRepository.dispose();
    await database.close();
  });

  Future<Task> createTask(String title, {int? estimatedMinutes}) async {
    final goal = await taskRepository.createGoal(
      const GoalDraft(title: '本周工作', classification: TaskClassification.both),
    );
    return taskRepository.createTask(
      goal.id,
      TaskDraft(
        title: title,
        classification: TaskClassification.both,
        estimatedMinutes: estimatedMinutes,
      ),
    );
  }

  test('倒计时归零只结算一次节点、链记录和任务有效时间', () async {
    final task = await createTask('写发布说明', estimatedMinutes: 1);
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(seconds: 80),
    );

    expect(session.isActive, isTrue);
    now = now.add(const Duration(seconds: 80));

    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 80);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await focusRepository.getChainRecords())
          .singleWhere((record) => record.mode == FocusChainMode.elite)
          .currentConsecutive,
      1,
    );
    final completedTask = (await taskRepository.getGoals()).single.tasks.single;
    expect(completedTask.focusProgressSeconds, 80);
    expect(completedTask.isComplete, isFalse);

    await focusRepository.getSessions();
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      80,
    );
  });

  test('已有进行中的专注返回原会话，不静默新建', () async {
    final task = await createTask('整理资料');
    final first = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 5),
    );

    final returned = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 30),
    );

    expect(returned.id, first.id);
    expect(returned.mode, FocusChainMode.regular);
    expect(await focusRepository.getSessions(), hasLength(1));
  });

  test('正常结算可重启读取并同步到远端', () async {
    final task = await createTask('复核构建');
    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 10),
    );
    now = now.add(const Duration(seconds: 10));
    await focusRepository.sync();

    final remoteSnapshot = await focusRemote.pull(userId: 'user-a');
    expect(remoteSnapshot.sessions.single.status, FocusSessionStatus.completed);
    expect(remoteSnapshot.nodes, hasLength(1));
    expect(
      remoteSnapshot.records
          .singleWhere((record) => record.mode == FocusChainMode.regular)
          .currentConsecutive,
      1,
    );

    final restarted = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    addTearDown(restarted.dispose);
    expect(
      (await restarted.getSessions()).single.status,
      FocusSessionStatus.completed,
    );
    expect(await restarted.getNodes(), hasLength(1));
  });

  test('新设备同步已完成专注时补齐任务有效时间', () async {
    final task = await createTask('同步交付记录');
    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 10),
    );
    now = now.add(const Duration(minutes: 10));
    await focusRepository.getSessions();
    await taskRepository.sync();
    await focusRepository.sync();

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondTaskRepository = LocalTaskRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: taskRemote,
      now: () => now,
    );
    final secondFocusRepository = LocalFocusRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    addTearDown(secondFocusRepository.dispose);
    addTearDown(secondTaskRepository.dispose);
    addTearDown(secondDatabase.close);

    await secondTaskRepository.sync();
    await secondFocusRepository.sync();

    expect(
      (await secondTaskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      10 * 60,
    );
    expect(await secondFocusRepository.getNodes(), hasLength(1));
  });

  test('确认放弃记录失败、保留有效时间且只清零本次链记录', () async {
    final task = await createTask('处理反馈');
    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(seconds: 10),
    );
    now = now.add(const Duration(seconds: 10));
    await focusRepository.getSessions();

    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(seconds: 80),
    );
    now = now.add(const Duration(seconds: 25));
    final failed = await focusRepository.abandonSession(
      sessionId: (await focusRepository.getActiveSession())!.id,
      failureReason: '注意力被打断',
    );

    expect(failed.status, FocusSessionStatus.failed);
    expect(failed.effectiveSeconds, 25);
    expect(failed.failureReason, '注意力被打断');
    expect(await focusRepository.getNodes(), hasLength(1));
    final elite = (await focusRepository.getChainRecords()).singleWhere(
      (record) => record.mode == FocusChainMode.elite,
    );
    expect(elite.currentConsecutive, 0);
    expect(elite.bestConsecutive, 1);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      35,
    );
    expect(
      (await taskRepository.getGoals()).single.tasks.single.isComplete,
      isFalse,
    );

    await focusRepository.abandonSession(
      sessionId: failed.id,
      failureReason: '重复操作不应覆盖',
    );
    final afterRepeat = (await taskRepository.getGoals()).single.tasks.single;
    expect(afterRepeat.focusProgressSeconds, 35);
    expect(
      (await focusRepository.getSessions())
          .firstWhere((session) => session.id == failed.id)
          .failureReason,
      '注意力被打断',
    );
  });

  test('暂停区间不计入失败专注有效时间', () async {
    final task = await createTask('整理资料');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 100),
    );
    now = now.add(const Duration(seconds: 40));
    await focusRepository.pauseSession(session.id, ruleText: '短暂离开时允许暂停');
    now = now.add(const Duration(seconds: 30));
    await focusRepository.resumeSession(session.id);
    now = now.add(const Duration(seconds: 20));

    final failed = await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '临时离开',
    );
    expect(failed.effectiveSeconds, 60);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      60,
    );
    expect(await focusRepository.getNodes(), isEmpty);
  });

  test('暂停后正常完成仍贡献完整的有效专注时长', () async {
    final task = await createTask('完成阅读');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 100),
    );
    now = now.add(const Duration(seconds: 40));
    await focusRepository.pauseSession(session.id, ruleText: '允许暂离');
    now = now.add(const Duration(seconds: 30));
    await focusRepository.resumeSession(session.id);
    now = now.add(const Duration(seconds: 60));

    await focusRepository.getSessions();
    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 100);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      100,
    );
  });

  test('共享下必为例规则可管理，已确认暂停保留原文字版本', () async {
    final task = await createTask('准备会议材料');
    final rule = await focusRepository.createPrecedentRule(text: '需要喝水时允许短暂离开');

    expect((await focusRepository.getPrecedentRules()).single.text, rule.text);

    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 30),
    );
    now = now.add(const Duration(minutes: 10));
    await focusRepository.pauseSession(session.id, ruleText: rule.text);

    final edited = await focusRepository.updatePrecedentRule(
      ruleId: rule.id,
      text: '需要喝水时允许离开座位',
    );
    expect(edited.text, '需要喝水时允许离开座位');
    await focusRepository.deletePrecedentRule(rule.id);

    expect(await focusRepository.getPrecedentRules(), isEmpty);
    final paused = await focusRepository.getSession(session.id);
    expect(paused?.isPaused, isTrue);
    expect(paused?.pauseRuleText, '需要喝水时允许短暂离开');

    now = now.add(const Duration(minutes: 5));
    final resumed = await focusRepository.resumeSession(session.id);
    expect(resumed.isActive, isTrue);
  });

  test('共享规则同步到另一份本地存储，删除也不会重新出现', () async {
    final remote = focusRemote;
    final rule = await focusRepository.createPrecedentRule(text: '允许查看必要资料');
    await focusRepository.sync();

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondRepository = LocalFocusRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: remote,
      now: () => now,
    );
    addTearDown(secondRepository.dispose);
    addTearDown(secondDatabase.close);

    await secondRepository.sync();
    expect((await secondRepository.getPrecedentRules()).single.text, rule.text);

    await focusRepository.deletePrecedentRule(rule.id);
    await focusRepository.sync();
    await secondRepository.sync();
    expect(await secondRepository.getPrecedentRules(), isEmpty);
  });

  test('下必为例可提前完成，保留有效时间并只生成一个节点', () async {
    final task = await createTask('完成方案');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 40),
    );

    now = now.add(const Duration(minutes: 10));
    await focusRepository.pauseSession(session.id, ruleText: '允许短暂离开');
    now = now.add(const Duration(minutes: 5));
    await focusRepository.resumeSession(session.id);
    now = now.add(const Duration(minutes: 20));

    final completed = await focusRepository.completeEarlySession(
      sessionId: session.id,
      ruleText: '允许提前结束并保留已完成的工作',
    );

    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.completionType, FocusSessionCompletionType.precedentRule);
    expect(completed.completionRuleText, '允许提前结束并保留已完成的工作');
    expect(completed.effectiveSeconds, 30 * 60);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await focusRepository.getChainRecords())
          .singleWhere((record) => record.mode == FocusChainMode.elite)
          .currentConsecutive,
      1,
    );
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      30 * 60,
    );

    final repeated = await focusRepository.completeEarlySession(
      sessionId: session.id,
      ruleText: '不应覆盖原依据',
    );
    expect(repeated.completionRuleText, '允许提前结束并保留已完成的工作');
    expect(await focusRepository.getNodes(), hasLength(1));
  });

  test('预约准备到点按最新配置自动交接且重复恢复不重复记账', () async {
    final originalTask = await createTask('原预约任务');
    final updatedTask = await createTask('改后的预约任务');
    final appointment = await focusRepository.startAppointment(
      taskId: originalTask.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 30),
    );

    final preparationEndsAt = appointment.endsAt;
    now = now.add(const Duration(minutes: 5));
    final updated = await focusRepository.updateAppointment(
      appointmentId: appointment.id,
      taskId: updatedTask.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 45),
    );
    expect(updated.endsAt.isAtSameMomentAs(preparationEndsAt), isTrue);
    expect(updated.taskId, updatedTask.id);
    expect(updated.durationSeconds, 45 * 60);

    now = preparationEndsAt;
    await focusRepository.settleDueAppointments();
    final handedOff = await focusRepository.getActiveSession();
    expect(handedOff, isNotNull);
    expect(handedOff!.id, appointment.id);
    expect(handedOff.appointmentId, appointment.id);
    expect(handedOff.taskId, updatedTask.id);
    expect(handedOff.mode, FocusChainMode.elite);
    expect(handedOff.startedAt.isAtSameMomentAs(preparationEndsAt), isTrue);
    expect(
      handedOff.endsAt.isAtSameMomentAs(
        preparationEndsAt.add(const Duration(minutes: 45)),
      ),
      isTrue,
    );

    final succeeded = await focusRepository.getAppointment(appointment.id);
    expect(succeeded?.status, AppointmentPreparationStatus.succeeded);
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );

    await focusRepository.settleDueAppointments();
    expect(await focusRepository.getAppointments(), hasLength(1));
    expect(await focusRepository.getChainRecords(), hasLength(2));

    now = handedOff.endsAt;
    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 45 * 60);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );
  });

  test('提前进入只成功一次预约，后续专注失败不撤销预约记录', () async {
    final task = await createTask('提前开始工作');
    final appointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 20),
    );

    now = now.add(const Duration(minutes: 5));
    final session = await focusRepository.enterAppointmentEarly(appointment.id);
    expect(session.isActive, isTrue);
    expect(session.appointmentId, appointment.id);
    expect(
      (await focusRepository.getAppointment(appointment.id))?.status,
      AppointmentPreparationStatus.succeeded,
    );
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );

    now = now.add(const Duration(minutes: 3));
    final failed = await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '临时中断',
    );
    expect(failed.status, FocusSessionStatus.failed);
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );
    expect(
      (await focusRepository.getChainRecords())
          .singleWhere((record) => record.mode == FocusChainMode.regular)
          .currentConsecutive,
      0,
    );

    final repeated = await focusRepository.enterAppointmentEarly(
      appointment.id,
    );
    expect(repeated.id, session.id);
    expect(await focusRepository.getAppointments(), hasLength(1));
  });

  test('取消预约必须填写失败原因且只清零预约链当前记录', () async {
    final task = await createTask('取消预约');
    final first = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 20),
    );

    expect(
      () => focusRepository.cancelAppointment(
        appointmentId: first.id,
        failureReason: '  ',
      ),
      throwsArgumentError,
    );
    final cancelled = await focusRepository.cancelAppointment(
      appointmentId: first.id,
      failureReason: '临时无法开始',
    );
    expect(cancelled.status, AppointmentPreparationStatus.failed);
    expect(cancelled.failureReason, '临时无法开始');
    expect(await focusRepository.getSessions(), isEmpty);
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      0,
    );
    expect(
      (await focusRepository.getChainRecords())
          .singleWhere((record) => record.mode == FocusChainMode.elite)
          .currentConsecutive,
      0,
    );

    final second = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 20),
    );
    expect(second.id, isNot(first.id));
  });

  test('已有预约时直接启动专注会返回可处理冲突，而不是静默绕过预约', () async {
    final task = await createTask('冲突处理');
    await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 20),
    );

    expect(
      () => focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 20),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await focusRepository.getActiveAppointment(), isNotNull);
  });

  test('预约和自动交接可离线同步到另一份本地存储且不重复预约成功', () async {
    final task = await createTask('跨设备预约');
    final appointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 10),
    );
    await taskRepository.sync();
    await focusRepository.sync();

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondTaskRepository = LocalTaskRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: taskRemote,
      now: () => now,
    );
    final secondFocusRepository = LocalFocusRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    addTearDown(secondFocusRepository.dispose);
    addTearDown(secondTaskRepository.dispose);
    addTearDown(secondDatabase.close);

    await secondTaskRepository.sync();
    await secondFocusRepository.sync();
    expect(await secondFocusRepository.getActiveAppointment(), isNotNull);

    now = appointment.endsAt.toUtc();
    await focusRepository.sync();
    await secondFocusRepository.sync();
    final syncedSession = await secondFocusRepository.getActiveSession();
    expect(syncedSession?.id, appointment.id);
    expect(
      (await secondFocusRepository.getAppointmentChainRecord())
          .currentConsecutive,
      1,
    );

    await secondFocusRepository.sync();
    expect(
      (await secondFocusRepository.getAppointmentChainRecord())
          .currentConsecutive,
      1,
    );

    now = now.add(const Duration(minutes: 10));
    await secondFocusRepository.getSessions();
    expect((await secondFocusRepository.getNodes()), hasLength(1));
  });

  test('进程重启后预约按原时间线交接并完成，重复恢复不重复记账', () async {
    final task = await createTask('重启后恢复预约');
    final appointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 30),
    );

    await focusRepository.dispose();
    now = appointment.endsAt.add(const Duration(minutes: 45));
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );

    await focusRepository.settleDueSessions();
    await focusRepository.settleDueSessions();

    final session = (await focusRepository.getSessions()).single;
    expect(session.status, FocusSessionStatus.completed);
    expect(session.startedAt.isAtSameMomentAs(appointment.endsAt), isTrue);
    expect(
      session.endsAt.isAtSameMomentAs(
        appointment.endsAt.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
    expect(
      session.completedAt?.isAtSameMomentAs(
        appointment.endsAt.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
    expect(session.effectiveSeconds, 30 * 60);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      30 * 60,
    );

    await focusRepository.sync();
    await focusRepository.settleDueSessions();
    await focusRepository.sync();
    final remoteSnapshot = await focusRemote.pull(userId: 'user-a');
    expect(remoteSnapshot.sessions, hasLength(1));
    expect(
      remoteSnapshot.sessions.single.completedAt?.isAtSameMomentAs(
        appointment.endsAt.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
    expect(remoteSnapshot.nodes, hasLength(1));
    expect(
      remoteSnapshot.nodes.single.createdAt.isAtSameMomentAs(
        appointment.endsAt.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });

  test('进程重启后未暂停专注按原结束时间完成，不计入重开后的空档', () async {
    final task = await createTask('按原时间线完成');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 30),
    );

    await focusRepository.dispose();
    now = started.endsAt.add(const Duration(hours: 2));
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );

    await focusRepository.settleDueSessions();
    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 30 * 60);
    expect(completed.completedAt?.isAtSameMomentAs(started.endsAt), isTrue);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      30 * 60,
    );

    await focusRepository.settleDueSessions();
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      30 * 60,
    );
  });

  test('进程重启后批准暂停保持暂停，恢复时只继续剩余时长', () async {
    final task = await createTask('隔夜保持暂停');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 30),
    );
    now = now.add(const Duration(minutes: 10));
    await focusRepository.pauseSession(started.id, ruleText: '允许隔夜暂停');
    final pausedAt = now;

    await focusRepository.dispose();
    now = now.add(const Duration(hours: 12));
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );

    await focusRepository.settleDueSessions();
    final restored = await focusRepository.getActiveSession();
    expect(restored?.status, FocusSessionStatus.paused);
    expect(restored?.pausedSeconds, 0);
    expect(restored?.pauseRuleText, '允许隔夜暂停');
    expect(restored?.pausedAt?.isAtSameMomentAs(pausedAt), isTrue);
    expect(await focusRepository.getNodes(), isEmpty);

    final resumed = await focusRepository.resumeSession(started.id);
    expect(resumed.status, FocusSessionStatus.active);
    expect(resumed.endsAt.difference(now), const Duration(minutes: 20));

    now = resumed.endsAt;
    await focusRepository.settleDueSessions();
    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 30 * 60);
    expect(await focusRepository.getNodes(), hasLength(1));
  });

  test('关闭并重新打开本地 SQLite 后仍能恢复预约时间线', () async {
    final directory = await Directory.systemTemp.createTemp('pacta-t07-');
    final file = File('${directory.path}${Platform.pathSeparator}pacta.sqlite');
    final persistentTaskRemote = InMemoryTaskRemote();
    final persistentFocusRemote = InMemoryFocusRemote();
    PactaDatabase? persistentDatabase;
    LocalTaskRepository? persistentTaskRepository;
    LocalFocusRepository? persistentFocusRepository;

    try {
      persistentDatabase = PactaDatabase(NativeDatabase(file));
      persistentTaskRepository = LocalTaskRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentTaskRemote,
        now: () => now,
      );
      persistentFocusRepository = LocalFocusRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentFocusRemote,
        now: () => now,
      );
      final goal = await persistentTaskRepository.createGoal(
        const GoalDraft(
          title: '本地重开验收',
          classification: TaskClassification.both,
        ),
      );
      final task = await persistentTaskRepository.createTask(
        goal.id,
        const TaskDraft(title: '恢复预约', classification: TaskClassification.both),
      );
      final appointment = await persistentFocusRepository.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 30),
      );

      await persistentFocusRepository.dispose();
      persistentFocusRepository = null;
      await persistentTaskRepository.dispose();
      persistentTaskRepository = null;
      await persistentDatabase.close();
      persistentDatabase = null;

      now = appointment.endsAt.add(const Duration(minutes: 45));
      persistentDatabase = PactaDatabase(NativeDatabase(file));
      persistentTaskRepository = LocalTaskRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentTaskRemote,
        now: () => now,
      );
      persistentFocusRepository = LocalFocusRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentFocusRemote,
        now: () => now,
      );

      await persistentFocusRepository.settleDueSessions();
      final session = (await persistentFocusRepository.getSessions()).single;
      expect(session.status, FocusSessionStatus.completed);
      expect(session.startedAt.isAtSameMomentAs(appointment.endsAt), isTrue);
      expect(
        session.completedAt?.isAtSameMomentAs(
          appointment.endsAt.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
      expect(session.effectiveSeconds, 30 * 60);
      final node = (await persistentFocusRepository.getNodes()).single;
      expect(
        node.createdAt.isAtSameMomentAs(
          appointment.endsAt.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
      expect(
        (await persistentTaskRepository.getGoals())
            .single
            .tasks
            .single
            .focusProgressSeconds,
        30 * 60,
      );

      await persistentFocusRepository.settleDueSessions();
      expect(await persistentFocusRepository.getNodes(), hasLength(1));

      final pausedSession = await persistentFocusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 30),
      );
      now = now.add(const Duration(minutes: 10));
      await persistentFocusRepository.pauseSession(
        pausedSession.id,
        ruleText: '本地重开后保持暂停',
      );
      final pausedAt = now;

      await persistentFocusRepository.dispose();
      persistentFocusRepository = null;
      await persistentTaskRepository.dispose();
      persistentTaskRepository = null;
      await persistentDatabase.close();
      persistentDatabase = null;

      now = pausedAt.add(const Duration(hours: 12));
      persistentDatabase = PactaDatabase(NativeDatabase(file));
      persistentTaskRepository = LocalTaskRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentTaskRemote,
        now: () => now,
      );
      persistentFocusRepository = LocalFocusRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentFocusRemote,
        now: () => now,
      );

      await persistentFocusRepository.settleDueSessions();
      final restoredPaused = await persistentFocusRepository.getActiveSession();
      expect(restoredPaused?.status, FocusSessionStatus.paused);
      expect(restoredPaused?.pauseRuleText, '本地重开后保持暂停');
      expect(restoredPaused?.pausedAt?.isAtSameMomentAs(pausedAt), isTrue);
      expect(await persistentFocusRepository.getNodes(), hasLength(1));

      final resumed = await persistentFocusRepository.resumeSession(
        pausedSession.id,
      );
      expect(resumed.endsAt.difference(now), const Duration(minutes: 20));
      now = resumed.endsAt;
      await persistentFocusRepository.settleDueSessions();
      await persistentFocusRepository.settleDueSessions();
      final completedPaused = (await persistentFocusRepository.getSessions())
          .singleWhere((item) => item.id == pausedSession.id);
      expect(completedPaused.status, FocusSessionStatus.completed);
      expect(completedPaused.effectiveSeconds, 30 * 60);
      expect(
        completedPaused.completedAt?.isAtSameMomentAs(resumed.endsAt),
        isTrue,
      );
      expect(await persistentFocusRepository.getNodes(), hasLength(2));
      expect(
        (await persistentTaskRepository.getGoals())
            .single
            .tasks
            .single
            .focusProgressSeconds,
        60 * 60,
      );
    } finally {
      await persistentFocusRepository?.dispose();
      await persistentTaskRepository?.dispose();
      await persistentDatabase?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('失败原因和正常节点备注可编辑并持久化', () async {
    final task = await createTask('写复盘');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 10),
    );
    now = now.add(const Duration(seconds: 10));
    await focusRepository.getSessions();
    await focusRepository.updateNodeNote(nodeId: session.id, note: '完成了关键复盘');
    expect((await focusRepository.getNodes()).single.note, '完成了关键复盘');

    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 30),
    );
    final active = await focusRepository.getActiveSession();
    final failed = await focusRepository.abandonSession(
      sessionId: active!.id,
      failureReason: '初始原因',
    );
    await focusRepository.updateFailureReason(
      sessionId: failed.id,
      failureReason: '改为更准确的反思',
    );
    expect(
      (await focusRepository.getSessions())
          .firstWhere((item) => item.id == failed.id)
          .failureReason,
      '改为更准确的反思',
    );
  });
}
