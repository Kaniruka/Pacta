import 'dart:io';

import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_history.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import 'predecessor_schema_fixtures.dart';

/// `CloudSnapshotRemote` is an external boundary; capturing a local snapshot
/// never calls it.
class _InertCloudRemote implements CloudSnapshotRemote {
  const _InertCloudRemote();

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async =>
      null;

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  }) => throw UnsupportedError('capture only');

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) =>
      throw UnsupportedError('capture only');

  @override
  Future<List<CloudSnapshotHistoryEntry>> history({required String userId}) =>
      throw UnsupportedError('capture only');

  @override
  Future<CloudSnapshotMetadata> downloadRevision({
    required String userId,
    required int revision,
  }) => throw UnsupportedError('capture only');
}

Future<CloudSnapshotLocalState> _capture(PactaDatabase database, String user) {
  return CloudSnapshotRepository(
    database: database,
    remote: const _InertCloudRemote(),
    userId: user,
    deviceName: 'predecessor-fixture',
  ).captureLocalState();
}

List<Map<String, dynamic>> _rows(CloudSnapshotLocalState state, String table) {
  final tables = state.payload['tables'] as Map<String, dynamic>;
  return (tables[table] as List<dynamic>).cast<Map<String, dynamic>>();
}

Future<Map<String, List<String>>> _structure(PactaDatabase database) async {
  final tables = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  final structure = <String, List<String>>{};
  for (final row in tables) {
    final name = row.read<String>('name');
    final columns = await database
        .customSelect('PRAGMA table_info("$name")')
        .get();
    structure[name] = <String>[
      for (final column in columns) column.read<String>('name'),
    ];
  }
  return structure;
}

Future<Map<String, List<String>>> _freshStructure(Directory directory) async {
  final file = File(
    '${directory.path}${Platform.pathSeparator}fresh-${DateTime.now().microsecondsSinceEpoch}.sqlite',
  );
  final database = PactaDatabase(NativeDatabase(file));
  try {
    await database.select(database.localGoals).get();
    return await _structure(database);
  } finally {
    await database.close();
  }
}

/// Opens the file without drift migrations or a schema-version stamp, so a test
/// can inspect a rolled-back database and prepare a blocker before an upgrade.
class _NoMigrationUser implements QueryExecutorUser {
  const _NoMigrationUser();

  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

const _inspectionUser = _NoMigrationUser();

void main() {
  for (final shape in predecessorShapes) {
    test('schema 39 upgrades ${shape.label} and keeps user data', () async {
      final fixture = await buildPredecessorFixture(shape);
      Map<String, List<String>> upgradedStructure;
      String firstFingerprint;
      var database = fixture.open();
      try {
        await _expectRetention(database, shape);
        final version = await database
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.single.read<int>('user_version'), 39);
        upgradedStructure = await _structure(database);
        firstFingerprint = (await _capture(database, 'user-a')).fingerprint;
      } finally {
        await database.close();
      }

      // Reopening an already upgraded file neither rewrites rows nor repeats a
      // one-time promotion or template backfill.
      database = fixture.open();
      try {
        expect(await _structure(database), upgradedStructure);
        expect(
          (await _capture(database, 'user-a')).fingerprint,
          firstFingerprint,
        );
        if (shape.hadColumn('local_goals', 'is_pinned')) {
          final reopened = <String, Goal>{
            for (final goal in await LocalTaskRepository(
              database: database,
              userId: 'user-a',
              remote: InMemoryTaskRemote(),
            ).getGoals(includeDeleted: true))
              goal.id: goal,
          };
          expect(reopened['goal-a']!.isPinned, isTrue);
          expect(reopened['goal-a']!.sortOrder, 1);
          expect(reopened['goal-deleted']!.isPinned, isTrue);
          expect(reopened['goal-deleted']!.sortOrder, 0);
        }
        if (!shape.hadTable('local_schedules')) {
          final schedules = await LocalScheduleRepository(
            database: database,
            userId: 'user-a',
          ).getSchedules();
          expect(schedules, hasLength(1));
          final markers =
              (await database.select(database.localScheduleMigrations).get())
                  .where((marker) => marker.userId == 'user-a')
                  .toList();
          expect(markers, hasLength(1));
          expect(markers.single.promotedCount, 1);
        }
      } finally {
        await database.close();
      }

      // A fresh schema 39 database has exactly the same tables and columns.
      // Column order is not part of the contract: additive migrations append a
      // column at the end, while a fresh CREATE TABLE places it inline.
      final fresh = await _freshStructure(fixture.directory);
      expect(fresh.keys.toSet(), upgradedStructure.keys.toSet());
      for (final table in fresh.keys) {
        expect(
          fresh[table]!.toSet(),
          upgradedStructure[table]!.toSet(),
          reason: table,
        );
      }
      await fixture.dispose();
    });
  }

  test('schema 39 preserves a reminder rule that already has one', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pacta-39-reminder-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(file));
    try {
      await database.select(database.localGoals).get();
      await database.customStatement(
        'INSERT INTO local_schedule_recurrences (user_id, id, frequency, weekdays, '
        'first_date, end_date, time_zone_id, all_day, start_minutes_of_day, '
        'duration_minutes, day_span, shift_days, title, notes, task_id, '
        'reminder_minutes_before, created_at, updated_at) VALUES '
        "('user-a', 'rule-39', 'daily', '[]', '2026-11-16', NULL, 'Asia/Shanghai', 0, "
        '540, 60, 1, 0, \'模板39\', \'备注39\', NULL, 45, 1763258400, 1763258400)',
      );
    } finally {
      await database.close();
    }

    database = PactaDatabase(NativeDatabase(file));
    try {
      final rows = _rows(
        await _capture(database, 'user-a'),
        'local_schedule_recurrences',
      );
      expect(rows.single['reminder_minutes_before'], 45);
      expect(rows.single['title'], '模板39');
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'a failing upgrade rolls back and a later retry keeps every row',
    () async {
      final shape = predecessorShapes.firstWhere(
        (candidate) => candidate.userVersion == 29,
      );
      final fixture = await buildPredecessorFixture(shape);
      // The blocking object makes the first migration step fail.
      final blocker = NativeDatabase(fixture.file, enableMigrations: false);
      await blocker.ensureOpen(_inspectionUser);
      await blocker.runCustom(
        'CREATE VIEW "local_schedules" AS SELECT 1 AS blocked',
      );
      // Preparing the blocker must not move the stored version.
      final prepared = await blocker.runSelect(
        'PRAGMA user_version',
        const <Object?>[],
      );
      expect(prepared.single['user_version'], 29);
      await blocker.close();

      var database = fixture.open();
      final failedOpen = database.select(database.localGoals).get();
      await expectLater(failedOpen, throwsA(anything));
      await database.close();

      // Inspect the rolled-back file without running (or stamping) migrations.
      final probe = NativeDatabase(fixture.file, enableMigrations: false);
      await probe.ensureOpen(_inspectionUser);
      try {
        final version = await probe.runSelect(
          'PRAGMA user_version',
          const <Object?>[],
        );
        expect(version.single['user_version'], 29);
        final goalColumns = await probe.runSelect(
          'PRAGMA table_info("local_goals")',
          const <Object?>[],
        );
        expect(
          goalColumns.map((column) => column['name']).toSet(),
          isNot(contains('is_pinned')),
        );
        final goals = await probe.runSelect(
          'SELECT id, title FROM local_goals ORDER BY id',
          const <Object?>[],
        );
        expect(goals.map((row) => row['id']), <String>[
          'goal-a',
          'goal-b',
          'goal-deleted',
        ]);
        expect(goals.first['title'], '目标a');
        await probe.runCustom('DROP VIEW "local_schedules"');
      } finally {
        await probe.close();
      }

      // The retry upgrades the untouched v29 data in one pass.
      database = fixture.open();
      try {
        await _expectRetention(database, shape, promoted: true);
        final version = await database
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.single.read<int>('user_version'), 39);
      } finally {
        await database.close();
        await fixture.dispose();
      }
    },
  );

  // Supplementary to the upgrade paths above: two predecessors (b9b9b38,
  // 51a5af7) already carry pins, so this only covers a database that is already
  // on 39 and a rule reminder value no predecessor could hold.
  test('schema 39 keeps non-default goal pins, order and rule reminder', () async {
    final directory = await Directory.systemTemp.createTemp('pacta-39-pins-');
    final file = File('${directory.path}${Platform.pathSeparator}pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(file));
    try {
      await database.select(database.localGoals).get();
      final repository = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: InMemoryTaskRemote(),
      );
      final first = await repository.createGoal(
        const GoalDraft(title: '一', classification: TaskClassification.regular),
      );
      final second = await repository.createGoal(
        const GoalDraft(title: '二', classification: TaskClassification.regular),
      );
      await repository.setGoalPinned(first.id, isPinned: true);
      await repository.setGoalPinned(second.id, isPinned: true);
      await repository.reorderPinnedGoals(<String>[second.id, first.id]);
      await database.customStatement(
        'INSERT INTO local_schedule_recurrences (user_id, id, frequency, weekdays, '
        'first_date, end_date, time_zone_id, all_day, start_minutes_of_day, '
        'duration_minutes, day_span, shift_days, title, notes, task_id, '
        'reminder_minutes_before, created_at, updated_at) VALUES '
        "('user-a', 'rule-39', 'daily', '[]', '2026-11-16', NULL, 'Asia/Shanghai', 0, "
        '540, 60, 1, 0, \'模板39\', \'备注39\', NULL, 45, 1763258400, 1763258400)',
      );
    } finally {
      await database.close();
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      database = PactaDatabase(NativeDatabase(file));
      try {
        final goals = await LocalTaskRepository(
          database: database,
          userId: 'user-a',
          remote: InMemoryTaskRemote(),
        ).getGoals();
        expect(goals.map((goal) => goal.title), <String>['二', '一']);
        expect(goals.every((goal) => goal.isPinned), isTrue);
        expect(goals.first.sortOrder, lessThan(goals.last.sortOrder!));
        final rows = _rows(
          await _capture(database, 'user-a'),
          'local_schedule_recurrences',
        );
        expect(rows.single['reminder_minutes_before'], 45);
        expect(rows.single['title'], '模板39');
      } finally {
        await database.close();
      }
    }
    await directory.delete(recursive: true);
  });

  test(
    'a v33 upgrade produces a usable rule template for new instances',
    () async {
      final shape = predecessorShapes.firstWhere(
        (candidate) => candidate.label == 'v33-76765c5',
      );
      final fixture = await buildPredecessorFixture(shape);
      final database = fixture.open();
      try {
        final repository = LocalScheduleRepository(
          database: database,
          userId: 'user-a',
        );
        final generated = await repository.expandRecurrences(
          from: DateTime.utc(2026, 11, 17),
          to: DateTime.utc(2026, 11, 19),
        );
        expect(generated, greaterThan(0));
        final schedules = await repository.getSchedules(
          from: DateTime.utc(2026, 11, 17),
          to: DateTime.utc(2026, 11, 19),
        );
        final inherited = schedules.where(
          (schedule) =>
              schedule.recurrenceId == 'rule-fresh-a' &&
              schedule.title == '系列日程a',
        );
        expect(inherited, isNotEmpty);
        expect(inherited.first.notes, '系列备注a');
        expect(inherited.first.taskId, 'task-a');
      } finally {
        await database.close();
        await fixture.dispose();
      }
    },
  );
}

Future<void> _expectRetention(
  PactaDatabase database,
  PredecessorShape shape, {
  bool promoted = false,
}) async {
  final goals = await LocalTaskRepository(
    database: database,
    userId: 'user-a',
    remote: InMemoryTaskRemote(),
  ).getGoals(includeDeleted: true);
  final goalsById = <String, Goal>{for (final goal in goals) goal.id: goal};
  expect(goalsById.keys.toSet(), <String>{'goal-a', 'goal-deleted'});
  final activeGoal = goalsById['goal-a']!;
  final deletedGoal = goalsById['goal-deleted']!;
  expect(activeGoal.title, '目标a');
  expect(activeGoal.description, '描述a');
  expect(activeGoal.tasks.single.id, 'task-a');
  expect(activeGoal.tasks.single.description, '任务说明a');
  expect(activeGoal.tasks.single.estimatedMinutes, 45);
  expect(activeGoal.tasks.single.deadline, isNotNull);
  expect(activeGoal.tasks.single.focusProgressSeconds, 120);
  expect(activeGoal.tasks.single.isComplete, isTrue);
  expect(deletedGoal.deletedAt, isNotNull);

  // Two real predecessors (b9b9b38 schema 35, 51a5af7 schema 37) already carry
  // the pin columns; their non-default pins and manual order must survive the
  // upgrade untouched. Shapes without the columns get the documented defaults.
  final carriedPins = shape.hadColumn('local_goals', 'is_pinned');
  if (carriedPins) {
    expect(activeGoal.isPinned, isTrue);
    expect(activeGoal.sortOrder, 1);
    expect(deletedGoal.isPinned, isTrue);
    expect(deletedGoal.sortOrder, 0);
  } else {
    expect(activeGoal.isPinned, isFalse);
    expect(activeGoal.sortOrder, isNull);
    expect(deletedGoal.isPinned, isFalse);
    expect(deletedGoal.sortOrder, isNull);
  }

  final scheduleRepository = LocalScheduleRepository(
    database: database,
    userId: 'user-a',
  );
  final schedules = await scheduleRepository.getSchedules();
  if (!shape.hadTable('local_schedules')) {
    expect(schedules, hasLength(1));
    expect(schedules.single.title, '周会a');
    expect(schedules.single.origin, ScheduleOrigin.legacyCalendarBlock);
    expect(schedules.single.sourceEventId, 'event-1');
    expect(schedules.single.eventIdentity, 'event-1:20261116');
    final status = await scheduleRepository.getLegacyMigrationStatus();
    expect(status.hasCompletedMigration, isTrue);
    expect(status.promotedCount, 1);
    expect(status.sourceBlockCount, 1);
    // Promotion copies; the read-only calendar rows stay.
    final blocks = await database.select(database.localCalendarBlocks).get();
    expect(blocks.where((block) => block.userId == 'user-a').length, 1);
    expect(await scheduleRepository.getRecurrenceRules(), isEmpty);
  } else {
    final byId = <String, dynamic>{
      for (final schedule in schedules) schedule.id: schedule,
    };
    final carriedInstances = shape.hadColumn(
      'local_schedules',
      'recurrence_id',
    );
    expect(byId.keys.toSet(), <String>{
      'schedule-owned-a',
      'schedule-imported-a',
      if (carriedInstances) ...<String>[
        'schedule-series-a',
        'schedule-exception-a',
      ],
      if (carriedInstances && shape.hadTable('local_schedule_recurrences'))
        'schedule-notes-a',
    });
    expect(byId['schedule-owned-a'].title, '自有日程a');
    expect(byId['schedule-owned-a'].notes, '备注a');
    expect(byId['schedule-owned-a'].isCompleted, isTrue);
    expect(byId['schedule-owned-a'].completedAt, isNotNull);
    expect(byId['schedule-owned-a'].taskId, 'task-a');
    expect(byId['schedule-owned-a'].reminderMinutesBefore, 15);
    expect(byId['schedule-imported-a'].origin, ScheduleOrigin.calendarImport);
    expect(byId['schedule-imported-a'].sourceIds, <String>['calendar-1']);
    expect(byId['schedule-imported-a'].sourceNames, <String>['工作']);
    expect(
      byId['schedule-imported-a'].eventIdentity,
      'event-imported:20261116',
    );
    expect(byId['schedule-imported-a'].reminderMinutesBefore, isNull);

    final capture = await _capture(database, 'user-a');
    final scheduleRows = _rows(capture, 'local_schedules');
    if (carriedInstances) {
      final cancelled = scheduleRows.singleWhere(
        (row) => row['id'] == 'schedule-cancelled-a',
      );
      expect(cancelled['is_recurrence_cancelled'], 1);
      expect(cancelled['title'], '已取消这一期a');
      final exception = scheduleRows.singleWhere(
        (row) => row['id'] == 'schedule-exception-a',
      );
      expect(exception['is_recurrence_exception'], 1);
      final series = scheduleRows.singleWhere(
        (row) => row['id'] == 'schedule-series-a',
      );
      expect(series['recurrence_id'], 'rule-fresh-a');
      expect(series['recurrence_series_id'], 'series-fresh-a');
      expect(series['recurrence_date'], '2026-11-16');
      expect(series['recurrence_time_zone_id'], 'Asia/Shanghai');
      expect(series['recurrence_start_minutes'], 540);
      expect(series['reminder_minutes_before'], 5);
    }

    if (shape.hadTable('local_schedule_recurrences')) {
      final rules = await scheduleRepository.getRecurrenceRules();
      final fresh = rules.singleWhere((rule) => rule.id == 'rule-fresh-a');
      final kept = rules.singleWhere((rule) => rule.id == 'rule-kept-a');
      // The earliest visible instance seeds the rule content; the exception and
      // the cancelled tombstone never do.
      expect(fresh.title, '系列日程a');
      expect(fresh.notes, '系列备注a');
      expect(fresh.taskId, 'task-a');
      expect(fresh.endDate, isNull);
      // Shapes without the rule-template columns never carried a template, so
      // there is nothing to preserve; rule-kept has no instances either and its
      // template stays empty rather than inventing content.
      final hadTemplate = shape.hadColumn(
        'local_schedule_recurrences',
        'title',
      );
      expect(kept.title, hadTemplate ? '已有模板a' : '');
      expect(kept.notes, hadTemplate ? '模板备注a' : '');
      expect(kept.taskId, hadTemplate ? 'task-a' : isNull);
      expect(kept.endDate, '2026-12-28');
      expect(
        kept.shiftDays,
        shape.hadColumn('local_schedule_recurrences', 'shift_days') ? 3 : 0,
      );
      // The backfill fills an empty title, but a rule's own notes/task link stay:
      // the competing instance must not overwrite them.
      final notesRule = rules.singleWhere((rule) => rule.id == 'rule-notes-a');
      final hadNotesColumn = shape.hadColumn(
        'local_schedule_recurrences',
        'notes',
      );
      final hadTaskColumn = shape.hadColumn(
        'local_schedule_recurrences',
        'task_id',
      );
      expect(notesRule.title, '实例标题a');
      expect(notesRule.notes, hadNotesColumn ? '规则自有备注a' : '实例别的备注a');
      expect(notesRule.taskId, hadTaskColumn ? 'task-a' : isNull);
      final ruleRows = _rows(capture, 'local_schedule_recurrences');
      expect(
        ruleRows.singleWhere(
          (row) => row['id'] == 'rule-fresh-a',
        )['reminder_minutes_before'],
        isNull,
        reason: '旧规则没有提醒列时补 null，绝不把实例偏移提升为规则默认值',
      );
      expect(
        ruleRows.singleWhere(
          (row) => row['id'] == 'rule-kept-a',
        )['reminder_minutes_before'],
        isNull,
      );
    } else {
      expect(await scheduleRepository.getRecurrenceRules(), isEmpty);
    }
  }

  final profile = await LocalProfileRepository(
    database: database,
    userId: 'user-a',
  ).getProfile();
  expect(profile.displayName, '用户a');
  expect(profile.editSequence, 3);
  expect(
    profile.displayTimeZoneId,
    shape.hadColumn('local_profile_accounts', 'time_zone_id')
        ? 'Asia/Shanghai'
        : isNull,
  );
  expect(
    profile.timeZoneRevision,
    shape.hadColumn('local_profile_accounts', 'time_zone_revision') ? 7 : 0,
  );
  expect(
    profile.pendingTimeZoneUpload,
    shape.hadColumn('local_profile_accounts', 'pending_time_zone_upload'),
  );

  final failures = await LocalNationalFocusRepository(
    database: database,
    userId: 'user-a',
  ).getFailures();
  expect(failures.single.id, 'failure-a');
  expect(failures.single.checkpointAt.toUtc(), DateTime.utc(2026, 11, 14));
  expect(failures.single.failureReason, '原因a');
  expect(
    failures.single.reviewedAt?.toUtc(),
    shape.hadColumn('local_national_focus_failures', 'reviewed_at')
        ? DateTime.utc(2026, 11, 14, 5)
        : isNull,
  );

  final appointments = await LocalFocusRepository(
    database: database,
    userId: 'user-a',
    remote: const UnavailableFocusRemoteDataSource(),
  ).getAppointments();
  expect(appointments.single.id, 'appointment-a');
  expect(appointments.single.taskId, 'task-a');
  expect(appointments.single.durationSeconds, 1800);
  expect(appointments.single.startedAt.toUtc(), DateTime.utc(2026, 11, 16, 1));
  expect(appointments.single.endsAt.toUtc(), DateTime.utc(2026, 11, 16, 2));
  expect(appointments.single.status, AppointmentPreparationStatus.active);
  expect(
    appointments.single.preparationSeconds,
    shape.hadColumn('focus_appointments', 'preparation_seconds') ? 420 : isNull,
  );

  // Cross-user isolation: user-b keeps its own rows and user-a's capture never
  // contains them.
  final otherGoals = await LocalTaskRepository(
    database: database,
    userId: 'user-b',
    remote: InMemoryTaskRemote(),
  ).getGoals();
  expect(otherGoals.single.id, 'goal-b');
  expect(otherGoals.single.title, '目标b');
  if (carriedPins) {
    // The other owner keeps its own pinned goal and its own order value.
    expect(otherGoals.single.isPinned, isTrue);
    expect(otherGoals.single.sortOrder, 0);
  } else {
    expect(otherGoals.single.isPinned, isFalse);
    expect(otherGoals.single.sortOrder, isNull);
  }
  final otherProfile = await LocalProfileRepository(
    database: database,
    userId: 'user-b',
  ).getProfile();
  expect(otherProfile.displayName, '用户b');
  final captureA = await _capture(database, 'user-a');
  for (final table in <String>[
    'local_goals',
    'local_tasks',
    'focus_appointments',
    'local_profile_accounts',
    'local_national_focus_failures',
    'local_schedules',
    'local_schedule_recurrences',
  ]) {
    final rows = (captureA.payload['tables'] as Map<String, dynamic>)[table];
    if (rows is! List) continue;
    for (final row in rows.cast<Map<String, dynamic>>()) {
      expect(row['user_id'], 'user-a');
    }
  }
}
