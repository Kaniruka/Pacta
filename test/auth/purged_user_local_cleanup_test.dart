import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('completed receipt purges every old-identity cache and preserves new identity', () async {
    await _seedUser(database, 'old-user-id');
    await _seedUser(database, 'new-user-id');

    final cleaned = await database.purgeUserDataForReceipt(
      userId: 'old-user-id',
      receipt: UserPurgeReceipt(
        userId: 'old-user-id',
        status: UserPurgeStatus.completed,
        purgedAt: DateTime.utc(2026, 9, 26),
      ),
    );

    expect(cleaned, isTrue);
    await _expectUserRows(database, 'old-user-id', 0);
    await _expectUserRows(database, 'new-user-id', 20);
  });
}

Future<void> _seedUser(PactaDatabase db, String userId) async {
  final now = DateTime.utc(2026, 9, 26);
  await db
      .into(db.localGoals)
      .insert(
        LocalGoalsCompanion.insert(
          userId: userId,
          id: 'goal-$userId',
          title: 'Goal',
          classification: 'regular',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.localTasks)
      .insert(
        LocalTasksCompanion.insert(
          userId: userId,
          id: 'task-$userId',
          goalId: 'goal-$userId',
          title: 'Task',
          classification: 'regular',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.localNationalFocusCards)
      .insert(
        LocalNationalFocusCardsCompanion.insert(
          userId: userId,
          id: 'card-$userId',
          triggerCondition: 'start work',
          action: 'write first step',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.localNationalFocusStrengtheningLevels)
      .insert(
        LocalNationalFocusStrengtheningLevelsCompanion.insert(
          userId: userId,
          cardId: 'card-$userId',
          levelNumber: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.localNationalFocusRequirementVersions)
      .insert(
        LocalNationalFocusRequirementVersionsCompanion.insert(
          userId: userId,
          id: 'version-$userId',
          cardId: 'card-$userId',
          versionNumber: 1,
          effectiveTriggerCondition: 'start work',
          effectiveAction: 'write first step',
          effectiveFrom: now,
        ),
      );
  await db
      .into(db.localNationalFocusMaintenance)
      .insert(
        LocalNationalFocusMaintenanceCompanion.insert(
          userId: userId,
          lastSettledCheckpointAt: now,
        ),
      );
  await db
      .into(db.localNationalFocusFailures)
      .insert(
        LocalNationalFocusFailuresCompanion.insert(
          userId: userId,
          id: 'failure-$userId',
          batchId: 'batch-$userId',
          cardId: 'card-$userId',
          checkpointAt: now,
          cause: 'missed_confirmation',
          treeSnapshot: '[]',
        ),
      );
  await db
      .into(db.focusSessions)
      .insert(
        FocusSessionsCompanion.insert(
          userId: userId,
          id: 'session-$userId',
          taskId: 'task-$userId',
          mode: 'regular',
          durationSeconds: 60,
          startedAt: now,
          endsAt: now.add(const Duration(minutes: 1)),
          status: 'active',
        ),
      );
  await db
      .into(db.focusAppointments)
      .insert(
        FocusAppointmentsCompanion.insert(
          userId: userId,
          id: 'appointment-$userId',
          taskId: 'task-$userId',
          mode: 'regular',
          durationSeconds: 60,
          startedAt: now,
          endsAt: now.add(const Duration(minutes: 1)),
          status: 'active',
          updatedAt: now,
        ),
      );
  await db
      .into(db.focusSourceDevices)
      .insert(
        FocusSourceDevicesCompanion.insert(userId: userId, deviceId: 'device'),
      );
  await db
      .into(db.focusSyncSources)
      .insert(
        FocusSyncSourcesCompanion.insert(
          userId: userId,
          sourceId: 'source-$userId',
          deviceId: 'device',
          entityType: 'focus_session',
          entityId: 'session-$userId',
          occurredAt: now,
          payload: '{}',
        ),
      );
  await db
      .into(db.appointmentChainRecords)
      .insert(
        AppointmentChainRecordsCompanion.insert(userId: userId, updatedAt: now),
      );
  await db
      .into(db.focusNodes)
      .insert(
        FocusNodesCompanion.insert(
          userId: userId,
          id: 'node-$userId',
          sessionId: 'session-$userId',
          taskId: 'task-$userId',
          mode: 'regular',
          createdAt: now,
          effectiveSeconds: 60,
        ),
      );
  await db
      .into(db.focusChainRecords)
      .insert(
        FocusChainRecordsCompanion.insert(
          userId: userId,
          mode: 'regular',
          updatedAt: now,
        ),
      );
  await db
      .into(db.focusPreferences)
      .insert(
        FocusPreferencesCompanion.insert(userId: userId, lastMode: 'regular'),
      );
  await db
      .into(db.focusPrecedentRules)
      .insert(
        FocusPrecedentRulesCompanion.insert(
          userId: userId,
          id: 'rule-$userId',
          ruleText: 'pause for water',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.taskSyncEntries)
      .insert(
        TaskSyncEntriesCompanion.insert(
          userId: userId,
          entityType: 'goal',
          entityId: 'goal-$userId',
          updatedAt: now,
        ),
      );
  await db
      .into(db.localCalendarSources)
      .insert(
        LocalCalendarSourcesCompanion.insert(
          userId: userId,
          sourceId: 'calendar-$userId',
          displayName: 'Calendar',
          timeZoneId: 'UTC',
          updatedAt: now,
        ),
      );
  await db
      .into(db.localCalendarBlocks)
      .insert(
        LocalCalendarBlocksCompanion.insert(
          userId: userId,
          sourceId: 'calendar-$userId',
          sourceEventId: 'event-$userId',
          occurrenceId: 'occurrence-$userId',
          eventIdentity: 'identity-$userId',
          title: 'Busy',
          startsAt: now,
          endsAt: now.add(const Duration(hours: 1)),
          availability: 'busy',
          timeZoneId: 'UTC',
          updatedAt: now,
        ),
      );
  await db
      .into(db.localUserLifecycleStates)
      .insert(
        LocalUserLifecycleStatesCompanion.insert(
          userId: userId,
          checkedAt: now,
        ),
      );
}

Future<void> _expectUserRows(PactaDatabase db, String userId, int count) async {
  final counts = [
    await (db.select(
      db.localGoals,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localTasks,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localNationalFocusCards,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localNationalFocusStrengtheningLevels,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localNationalFocusRequirementVersions,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localNationalFocusMaintenance,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localNationalFocusFailures,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusSessions,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusAppointments,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusSyncSources,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.appointmentChainRecords,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusNodes,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusChainRecords,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusPreferences,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.focusPrecedentRules,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.taskSyncEntries,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localCalendarSources,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localCalendarBlocks,
    )..where((row) => row.userId.equals(userId))).get(),
    await (db.select(
      db.localUserLifecycleStates,
    )..where((row) => row.userId.equals(userId))).get(),
  ];

  expect(
    counts.map((rows) => rows.length).reduce((left, right) => left + right),
    count,
  );
}
