import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('schema 31 升级只新增预约准备时长列，旧记录保留已存成交时刻', () async {
    final directory = await Directory.systemTemp.createTemp('pacta-prep-');
    final file = File('${directory.path}/pacta.sqlite');
    final startedAt = DateTime.utc(2026, 11, 15, 8);
    final activeEndsAt = startedAt.add(const Duration(minutes: 15));
    final settledStartedAt = DateTime.utc(2026, 11, 14, 9);
    final settledEndsAt = settledStartedAt.add(const Duration(minutes: 15));
    final settledAt = settledEndsAt;

    var database = PactaDatabase(NativeDatabase(file));
    try {
      await database
          .into(database.focusAppointments)
          .insert(
            FocusAppointmentsCompanion.insert(
              userId: 'user-a',
              id: 'appointment-active',
              taskId: 'task-a',
              mode: FocusChainMode.regular.storageValue,
              durationSeconds: 30 * 60,
              startedAt: startedAt,
              endsAt: activeEndsAt,
              status: AppointmentPreparationStatus.active.storageValue,
              updatedAt: startedAt,
            ),
          );
      await database
          .into(database.focusAppointments)
          .insert(
            FocusAppointmentsCompanion.insert(
              userId: 'user-a',
              id: 'appointment-settled',
              taskId: 'task-a',
              mode: FocusChainMode.elite.storageValue,
              durationSeconds: 25 * 60,
              startedAt: settledStartedAt,
              endsAt: settledEndsAt,
              status: AppointmentPreparationStatus.succeeded.storageValue,
              settledAt: Value(settledAt),
              sessionId: const Value('session-settled'),
              updatedAt: settledAt,
              preparationSeconds: const Value(21 * 60),
            ),
          );
      // 模拟升级前的本机库：focus_appointments 没有准备时长列，版本停在 29。
      // 绑定版本的 SQLite 不一定支持 DROP COLUMN，按旧定义重建同名表。
      await database.customStatement('''
        CREATE TABLE focus_appointments_v29 (
          user_id TEXT NOT NULL,
          id TEXT NOT NULL,
          task_id TEXT NOT NULL,
          mode TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          started_at INTEGER NOT NULL,
          ends_at INTEGER NOT NULL,
          status TEXT NOT NULL,
          settled_at INTEGER,
          session_id TEXT,
          failure_reason TEXT,
          updated_at INTEGER NOT NULL,
          review_disposition TEXT NOT NULL DEFAULT 'accepted',
          review_disposition_updated_at INTEGER,
          configuration_basis_source_id TEXT,
          PRIMARY KEY (user_id, id)
        )
      ''');
      await database.customStatement('''
        INSERT INTO focus_appointments_v29 (
          user_id, id, task_id, mode, duration_seconds, started_at, ends_at,
          status, settled_at, session_id, failure_reason, updated_at,
          review_disposition, review_disposition_updated_at,
          configuration_basis_source_id
        )
        SELECT
          user_id, id, task_id, mode, duration_seconds, started_at, ends_at,
          status, settled_at, session_id, failure_reason, updated_at,
          review_disposition, review_disposition_updated_at,
          configuration_basis_source_id
        FROM focus_appointments
      ''');
      await database.customStatement('DROP TABLE focus_appointments');
      await database.customStatement(
        'ALTER TABLE focus_appointments_v29 RENAME TO focus_appointments',
      );
      await database.customStatement('PRAGMA user_version = 29');
    } finally {
      await database.close();
    }

    var clock = startedAt.add(const Duration(minutes: 5));
    var repository = LocalFocusRepository(
      database: database = PactaDatabase(NativeDatabase(file)),
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => clock,
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });

    final columns = await database
        .customSelect('PRAGMA table_info(focus_appointments)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('preparation_seconds'),
    );

    final legacyActive = (await repository.getAppointment(
      'appointment-active',
    ))!;
    expect(legacyActive.preparationSeconds, isNull);
    expect(legacyActive.effectivePreparationSeconds, 15 * 60);
    expect(legacyActive.startedAt.isAtSameMomentAs(startedAt), isTrue);
    expect(legacyActive.endsAt.isAtSameMomentAs(activeEndsAt), isTrue);

    final legacySettled = (await repository.getAppointment(
      'appointment-settled',
    ))!;
    expect(legacySettled.status, AppointmentPreparationStatus.succeeded);
    expect(legacySettled.startedAt.isAtSameMomentAs(settledStartedAt), isTrue);
    expect(legacySettled.endsAt.isAtSameMomentAs(settledEndsAt), isTrue);
    expect(legacySettled.settledAt!.isAtSameMomentAs(settledAt), isTrue);
    expect(legacySettled.preparationSeconds, isNull);
    expect(legacySettled.effectivePreparationSeconds, 15 * 60);

    // 正在进行的旧预约仍按原时间线交接，不因迁移延后或重算。
    clock = activeEndsAt;
    await repository.settleDueAppointments();
    final handedOff = (await repository.getSessions()).single;
    expect(handedOff.startedAt.isAtSameMomentAs(activeEndsAt), isTrue);
    expect(handedOff.durationSeconds, 30 * 60);
    final handedOffAppointment = (await repository.getAppointment(
      'appointment-active',
    ))!;
    expect(handedOffAppointment.status, AppointmentPreparationStatus.succeeded);
    expect(
      handedOffAppointment.settledAt!.isAtSameMomentAs(activeEndsAt),
      isTrue,
    );
    expect(
      (await repository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );

    // 迁移只跑一次：再次打开同一库不重复加列，也不改写已存记录。
    final previousEndsAt = handedOffAppointment.endsAt;
    await repository.dispose();
    database = PactaDatabase(NativeDatabase(file));
    repository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => clock,
    );
    final reopened = (await repository.getAppointment('appointment-active'))!;
    expect(reopened.endsAt.isAtSameMomentAs(previousEndsAt), isTrue);
    expect(reopened.preparationSeconds, isNull);
    expect(reopened.effectivePreparationSeconds, 15 * 60);
    expect(
      (await repository.getAppointmentChainRecord()).currentConsecutive,
      1,
    );
  });
}
