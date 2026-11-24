import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_chain_history.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSyncSource;
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

  for (final appointment in [true, false]) {
    for (final hasPreference in [true, false]) {
      test(
        '${hasPreference ? '已有' : '首次'}模式偏好写入失败回滚${appointment ? '预约' : '直接专注'}且保留原模式',
        () async {
          final task = await createTask('失败不记忆');
          if (hasPreference) {
            final previous = await focusRepository.startSession(
              taskId: task.id,
              mode: FocusChainMode.regular,
              duration: const Duration(minutes: 25),
            );
            await focusRepository.abandonSession(
              sessionId: previous.id,
              failureReason: '结束原流程',
            );
          }
          await database.customStatement('''
        CREATE TRIGGER reject_mode_write BEFORE ${hasPreference ? 'UPDATE' : 'INSERT'} ON focus_preferences
        BEGIN SELECT RAISE(ABORT, 'preference write rejected'); END
      ''');
          await expectLater(
            appointment
                ? focusRepository.startAppointment(
                    taskId: task.id,
                    mode: FocusChainMode.elite,
                    duration: const Duration(minutes: 25),
                  )
                : focusRepository.startSession(
                    taskId: task.id,
                    mode: FocusChainMode.elite,
                    duration: const Duration(minutes: 25),
                  ),
            throwsA(isA<Exception>()),
          );
          expect(await focusRepository.getLastMode(), FocusChainMode.regular);
          expect(await focusRepository.getActiveSession(), isNull);
          expect(await focusRepository.getAppointments(), isEmpty);
          expect(
            await focusRepository.getSessions(),
            hasLength(hasPreference ? 1 : 0),
          );
        },
      );
    }
  }

  test('不同用户的模式分别持久化且关闭数据库重开后仍保留', () async {
    final directory = await Directory.systemTemp.createTemp('pacta-mode-');
    final file = File('${directory.path}/focus.sqlite');
    var persistent = PactaDatabase(NativeDatabase(file));
    var owner = LocalFocusRepository(
      database: persistent,
      userId: 'mode-owner',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final other = LocalFocusRepository(
      database: persistent,
      userId: 'other-user',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final tasks = LocalTaskRepository(
      database: persistent,
      userId: 'mode-owner',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    try {
      expect(await owner.getLastMode(), FocusChainMode.regular);
      final goal = await tasks.createGoal(
        const GoalDraft(title: '持久目标', classification: TaskClassification.both),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(title: '持久任务', classification: TaskClassification.both),
      );
      await owner.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 25),
      );
      expect(await other.getLastMode(), FocusChainMode.regular);
      await owner.dispose();
      await other.dispose();
      await tasks.dispose();
      await persistent.close();
      persistent = PactaDatabase(NativeDatabase(file));
      owner = LocalFocusRepository(
        database: persistent,
        userId: 'mode-owner',
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      expect(await owner.getLastMode(), FocusChainMode.elite);
    } finally {
      await owner.dispose();
      await other.dispose();
      await tasks.dispose();
      await persistent.close();
      await directory.delete(recursive: true);
    }
  });

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

  test('已完成记录事后改判失败：保留有效时长、移除节点且不重复累加进度', () async {
    now = DateTime.utc(2026, 10, 1, 9);
    final task = await createTask('事后改判');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    now = session.endsAt;
    await focusRepository.settleDueSessions();
    final completed = (await focusRepository.getSession(session.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 1500);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      1500,
    );

    final failed = await focusRepository.markSessionFailed(
      sessionId: session.id,
      failureReason: '事后回想并没有真的专注',
    );

    expect(failed.status, FocusSessionStatus.failed);
    expect(failed.failureReason, '事后回想并没有真的专注');
    expect(failed.effectiveSeconds, 1500, reason: '有效时长不因改判而改变');
    expect(failed.completedAt, completed.completedAt, reason: '完成时刻原样保留');
    expect(
      failed.effectiveIntervals.length,
      completed.effectiveIntervals.length,
      reason: '区间不重算',
    );
    expect(await focusRepository.getNodes(), isEmpty, reason: '专注节点随改判一起移除');
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      1500,
      reason: '任务进度已经加过一次，改判不得再累加',
    );
    final record = (await focusRepository.getChainRecords()).singleWhere(
      (entry) => entry.mode == FocusChainMode.regular,
    );
    expect(record.currentConsecutive, 0);
    expect(record.bestConsecutive, 0, reason: '唯一一条记录改判后已没有连胜段，最高连胜必须按历史收敛');
  });

  test('改判落在历史中段时按完整历史重算当前与最高连击', () async {
    now = DateTime.utc(2026, 10, 2, 9);
    final task = await createTask('历史中段改判');
    final sessionIds = <String>[];
    for (var index = 0; index < 3; index++) {
      final session = await focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 10),
      );
      sessionIds.add(session.id);
      now = now.add(const Duration(minutes: 10));
      await focusRepository.settleDueSessions();
    }
    var record = (await focusRepository.getChainRecords()).singleWhere(
      (entry) => entry.mode == FocusChainMode.elite,
    );
    expect(record.currentConsecutive, 3);
    expect(record.bestConsecutive, 3);

    // 中间那条改判失败：最早的 #1 成为一段，最新的一条重新从 #1 起算。
    await focusRepository.markSessionFailed(
      sessionId: sessionIds[1],
      failureReason: '中间那次其实走神了',
    );

    record = (await focusRepository.getChainRecords()).singleWhere(
      (entry) => entry.mode == FocusChainMode.elite,
    );
    final timeline = buildFocusChainHistory(
      sessions: await focusRepository.getSessions(),
    ).timelineFor(FocusChainType.elite);
    expect(record.currentConsecutive, 1, reason: '断链后当前段只剩最新的 1 条');
    expect(record.bestConsecutive, 1, reason: '最高连胜按回放结果收敛到 1');
    expect(record.currentConsecutive, timeline.currentStreak);
    expect(record.bestConsecutive, timeline.bestStreak, reason: '链记录与时间轴同源');
    expect(await focusRepository.getNodes(), hasLength(2));
  });

  test('已失败的会话再次改判保持原失败原因且不重复扣减', () async {
    now = DateTime.utc(2026, 10, 3, 9);
    final task = await createTask('重复改判');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    now = session.endsAt;
    await focusRepository.settleDueSessions();
    await focusRepository.markSessionFailed(
      sessionId: session.id,
      failureReason: '第一次改判',
    );

    final repeated = await focusRepository.markSessionFailed(
      sessionId: session.id,
      failureReason: '第二次不应覆盖',
    );

    expect(repeated.failureReason, '第一次改判');
    expect(repeated.effectiveSeconds, 1500);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      1500,
    );
    expect(await focusRepository.getNodes(), isEmpty);
  });

  test('倒计时归零后填写放弃原因不再报错，改为事后判定失败', () async {
    now = DateTime.utc(2026, 10, 4, 9);
    final task = await createTask('到点竞态');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 25),
    );
    // 用户填原因的这一拍正好跨过 00:00：结算先跑，会话已经是 completed。
    now = session.endsAt.add(const Duration(milliseconds: 200));

    final failed = await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '最后一秒已经走神',
    );

    expect(failed.status, FocusSessionStatus.failed);
    expect(failed.failureReason, '最后一秒已经走神');
    expect(failed.effectiveSeconds, 1500);
    expect(await focusRepository.getNodes(), isEmpty);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      1500,
      reason: '自然结算已经记过一次有效时间',
    );
  });

  test('提前完成的记录也可事后改判失败，并清掉下必为例依据', () async {
    now = DateTime.utc(2026, 10, 5, 9);
    final task = await createTask('提前完成改判');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    now = now.add(const Duration(minutes: 10));
    await focusRepository.completeEarlySession(
      sessionId: session.id,
      ruleText: '允许提前收尾',
    );

    final failed = await focusRepository.markSessionFailed(
      sessionId: session.id,
      failureReason: '其实没有达成目标',
    );

    expect(failed.isFailed, isTrue);
    expect(failed.completionRuleText, isNull, reason: '改判后不再引用下必为例');
    expect(failed.isEarlyCompleted, isFalse);
    expect(failed.effectiveSeconds, 600);
  });

  test('事后改判必须有失败原因，进行中的会话同样可以判失败', () async {
    now = DateTime.utc(2026, 10, 6, 9);
    final task = await createTask('改判校验');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );

    await expectLater(
      focusRepository.markSessionFailed(
        sessionId: session.id,
        failureReason: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );

    now = now.add(const Duration(minutes: 5));
    final failed = await focusRepository.markSessionFailed(
      sessionId: session.id,
      failureReason: '临时被打断',
    );
    expect(failed.status, FocusSessionStatus.failed);
    expect(failed.effectiveSeconds, 300);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      300,
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

  for (final preparationMinutes in [5, 10, 15, 37]) {
    test('预约准备时长为 $preparationMinutes 分钟时按本场时长自动交接且只结算一次', () async {
      final task = await createTask('本场准备 $preparationMinutes 分钟');
      final preparation = Duration(minutes: preparationMinutes);
      final appointment = await focusRepository.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 30),
        preparation: preparation,
      );

      expect(appointment.preparationSeconds, preparation.inSeconds);
      expect(appointment.endsAt.difference(appointment.startedAt), preparation);

      now = appointment.endsAt;
      await focusRepository.settleDueAppointments();
      final handedOff = await focusRepository.getActiveSession();
      expect(handedOff, isNotNull);
      expect(handedOff!.id, appointment.id);
      expect(handedOff.startedAt.isAtSameMomentAs(appointment.endsAt), isTrue);
      expect(
        handedOff.endsAt.isAtSameMomentAs(
          appointment.endsAt.add(const Duration(minutes: 30)),
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
      expect(
        (await focusRepository.getAppointment(appointment.id))?.status,
        AppointmentPreparationStatus.succeeded,
      );
      expect(
        (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
        1,
      );
      expect(await focusRepository.getSessions(), hasLength(1));
    });
  }

  test('非法准备时长在仓储边界被拒绝且从不截断', () async {
    final task = await createTask('非法准备时长');
    for (final preparation in const [
      Duration.zero,
      Duration(seconds: 59),
      Duration(seconds: 90),
      Duration(minutes: -1),
      Duration(minutes: 1, milliseconds: 500),
      Duration(minutes: 10, microseconds: 1),
      Duration(minutes: 61),
      Duration(hours: 5),
    ]) {
      await expectLater(
        focusRepository.startAppointment(
          taskId: task.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 25),
          preparation: preparation,
        ),
        throwsArgumentError,
        reason: '$preparation 必须被拒绝而不是截断',
      );
    }
    expect(await focusRepository.getAppointments(), isEmpty);
    expect(await focusRepository.getSessions(), isEmpty);

    for (final minutes in const [1, 60]) {
      final appointment = await focusRepository.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
        preparation: Duration(minutes: minutes),
      );
      expect(appointment.preparationSeconds, minutes * 60);
      expect(
        appointment.endsAt.difference(appointment.startedAt),
        Duration(minutes: minutes),
      );
      await focusRepository.cancelAppointment(
        appointmentId: appointment.id,
        failureReason: '边界校验结束',
      );
    }
  });

  test('准备期间修改任务与专注时长不重置本场准备时长和结束时刻', () async {
    final originalTask = await createTask('准备中原任务');
    final updatedTask = await createTask('准备中改任务');
    final appointment = await focusRepository.startAppointment(
      taskId: originalTask.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 30),
      preparation: const Duration(minutes: 10),
    );
    final preparationEndsAt = appointment.endsAt;

    now = now.add(const Duration(minutes: 4));
    final changed = await focusRepository.updateAppointment(
      appointmentId: appointment.id,
      taskId: updatedTask.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 45),
    );

    expect(changed.endsAt.isAtSameMomentAs(preparationEndsAt), isTrue);
    expect(changed.preparationSeconds, 10 * 60);
    expect(changed.effectivePreparationSeconds, 10 * 60);
    expect(changed.durationSeconds, 45 * 60);
    expect(changed.taskId, updatedTask.id);

    now = preparationEndsAt;
    await focusRepository.settleDueAppointments();
    final handedOff = (await focusRepository.getSessions()).single;
    expect(handedOff.startedAt.isAtSameMomentAs(preparationEndsAt), isTrue);
    expect(handedOff.durationSeconds, 45 * 60);
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );
  });

  test('自定义准备时长下提前进入只结算一次且重启后不重复结算', () async {
    final task = await createTask('提前进入自定义准备');
    final appointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
      preparation: const Duration(minutes: 37),
    );

    now = now.add(const Duration(minutes: 6));
    final session = await focusRepository.enterAppointmentEarly(appointment.id);
    expect(session.startedAt.isAtSameMomentAs(now), isTrue);
    expect(
      session.endsAt.isAtSameMomentAs(now.add(const Duration(minutes: 25))),
      isTrue,
    );
    expect(
      (await focusRepository.getAppointment(appointment.id))?.status,
      AppointmentPreparationStatus.succeeded,
    );
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );

    await focusRepository.dispose();
    now = now.add(const Duration(minutes: 25));
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    await focusRepository.settleDueAppointments();
    await focusRepository.settleDueSessions();

    expect(
      (await focusRepository.getAppointment(appointment.id))?.status,
      AppointmentPreparationStatus.succeeded,
    );
    expect(
      (await focusRepository.getAppointment(appointment.id))
          ?.preparationSeconds,
      37 * 60,
    );
    expect(
      (await focusRepository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );
    expect(await focusRepository.getSessions(), hasLength(1));
    final repeated = await focusRepository.enterAppointmentEarly(
      appointment.id,
    );
    expect(repeated.id, session.id);
    expect(await focusRepository.getSessions(), hasLength(1));
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

  test('删除目标后预约仍自动交接，但不能从已删除任务新建流程', () async {
    final task = await createTask('保留的预约任务');
    final appointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 20),
    );

    await taskRepository.deleteGoal(task.goalId);
    expect(await focusRepository.getActiveAppointment(), isNotNull);
    await expectLater(
      focusRepository.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 20),
      ),
      throwsStateError,
    );
    await expectLater(
      focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 20),
      ),
      throwsStateError,
    );

    now = appointment.endsAt;
    final session = await focusRepository.getActiveSession();
    expect(session, isNotNull);
    expect(session?.appointmentId, appointment.id);
    expect(session?.taskId, task.id);
    expect(
      (await focusRepository.getAppointment(appointment.id))?.isSucceeded,
      isTrue,
    );
  });

  test('删除目标后活动和批准暂停的专注仍按原时长结算', () async {
    final task = await createTask('保留的专注任务');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 5),
    );
    now = now.add(const Duration(seconds: 30));
    await focusRepository.pauseSession(session.id, ruleText: '允许暂停');
    await taskRepository.deleteGoal(task.goalId);

    await expectLater(
      focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 5),
      ),
      throwsStateError,
    );
    now = now.add(const Duration(hours: 8));
    final resumed = await focusRepository.resumeSession(session.id);
    expect(resumed.status, FocusSessionStatus.active);
    expect(
      resumed.endsAt.difference(now),
      const Duration(minutes: 4, seconds: 30),
    );

    now = resumed.endsAt;
    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, const Duration(minutes: 5).inSeconds);
    expect(await focusRepository.getNodes(), hasLength(1));
    final deletedTask = (await taskRepository.getGoals(includeDeleted: true))
        .single
        .tasks
        .single;
    expect(deletedTask.isDeleted, isTrue);
    expect(
      deletedTask.focusProgressSeconds,
      const Duration(minutes: 5).inSeconds,
    );
  });
}

class BlockingInMemoryFocusRemote extends InMemoryFocusRemote {
  Completer<void>? _pullStarted;
  Completer<void>? _releasePull;
  var _holdNextPull = false;
  var _activePulls = 0;
  var maxConcurrentPulls = 0;

  Future<void> get firstPullStarted => _pullStarted!.future;

  void holdNextPull() {
    _pullStarted = Completer<void>();
    _releasePull = Completer<void>();
    _holdNextPull = true;
  }

  void releaseBlockedPull() {
    final release = _releasePull;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    _activePulls++;
    if (_activePulls > maxConcurrentPulls) {
      maxConcurrentPulls = _activePulls;
    }
    final snapshot = await super.pull(userId: userId);
    if (_holdNextPull) {
      _holdNextPull = false;
      _pullStarted!.complete();
      await _releasePull!.future;
    }
    _activePulls--;
    return snapshot;
  }
}

class FailOnceInMemoryFocusRemote extends InMemoryFocusRemote {
  var _shouldFailSourceUpload = true;
  List<FocusSyncSource>? failedUploadSources;

  @override
  Future<void> upsertSources({
    required String userId,
    required List<FocusSyncSource> sources,
  }) async {
    if (_shouldFailSourceUpload) {
      _shouldFailSourceUpload = false;
      failedUploadSources = List.unmodifiable(sources);
      throw StateError('simulated offline');
    }
    await super.upsertSources(userId: userId, sources: sources);
  }
}
