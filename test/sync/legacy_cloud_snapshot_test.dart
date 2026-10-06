import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/legacy_cloud_snapshot.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  const userId = 'legacy-user';
  final converter = LegacyCloudSnapshotConverter();

  test('returns null when all legacy business tables are empty', () async {
    expect(
      await converter.convert(userId: userId, records: _emptyRecords()),
      isNull,
    );
  });

  test(
    'maps legacy rows into a portable snapshot without device calendar ids',
    () async {
      final records = _emptyRecords();
      records['goals'] = [
        {
          'id': 'goal-1',
          'user_id': userId,
          'title': 'Legacy goal',
          'classification': 'regular',
          'created_at': '2026-09-01T00:00:00Z',
          'updated_at': '2026-09-02T03:04:05Z',
          'deleted_at': null,
        },
      ];
      records['tasks'] = [
        {
          'id': 'task-1',
          'user_id': userId,
          'goal_id': 'goal-1',
          'title': 'Legacy task',
          'classification': 'regular',
          'estimated_minutes': 25,
          'deadline': '2026-09-03T00:00:00Z',
          'is_complete': true,
          'focus_progress_seconds': 90,
          'created_at': '2026-09-01T01:00:00Z',
          'updated_at': '2026-09-02T04:00:00Z',
          'deleted_at': null,
        },
      ];
      records['focus_sessions'] = [
        {
          'id': 'session-1',
          'user_id': userId,
          'appointment_id': null,
          'task_id': 'task-1',
          'mode': 'regular',
          'duration_seconds': 1800,
          'started_at': '2026-09-02T08:00:00Z',
          'ends_at': '2026-09-02T08:30:00Z',
          'status': 'active',
          'completed_at': null,
          'effective_seconds': 0,
          'completion_type': 'countdown',
          'completion_rule_text': null,
          'paused_at': null,
          'paused_seconds': 0,
          'pause_rule_text': null,
          'failure_reason': null,
          'effective_intervals': [
            {'started_at': '2026-09-02T08:00:00Z'},
          ],
          'review_disposition': 'accepted',
          'review_disposition_updated_at': null,
          'configuration_basis_source_id': null,
          'outcome_basis_source_id': null,
        },
      ];
      records['focus_sync_sources'] = [
        {
          'source_id': 'source-1',
          'user_id': userId,
          'device_id': 'old-device',
          'entity_type': 'focus_session',
          'entity_id': 'session-1',
          'parent_source_id': null,
          'parent_source_ids': <String>[],
          'occurred_at': '2026-09-02T05:00:00Z',
          'payload': {'status': 'completed'},
        },
      ];
      records['calendar_sources'] = [
        {
          'user_id': userId,
          'source_id': 'calendar-1',
          'display_name': 'Legacy calendar',
          'time_zone_id': 'Asia/Shanghai',
          'updated_at': '2026-09-02T06:00:00Z',
          'last_refreshed_at': '2026-09-02T07:00:00Z',
        },
      ];
      records['calendar_blocks'] = [
        {
          'user_id': userId,
          'source_id': 'calendar-1',
          'source_event_id': 'event-1',
          'occurrence_id': 'event-1:20260904',
          'event_identity': 'event-1:20260904',
          'title': 'Legacy event',
          'starts_at': '2026-09-04T00:00:00Z',
          'ends_at': '2026-09-05T00:00:00Z',
          'is_all_day': true,
          'all_day_start_date': '2026-09-04',
          'all_day_end_date_exclusive': '2026-09-05',
          'availability': 'busy',
          'time_zone_id': 'Asia/Shanghai',
          'updated_at': '2026-09-02T07:00:00Z',
        },
      ];

      final state = await converter.convert(userId: userId, records: records);

      expect(state, isNotNull);
      expect(state!.rowCount, 6);
      expect(state.payload['schemaVersion'], 1);
      expect(state.payload['userId'], userId);
      final tables = state.payload['tables'] as Map<String, dynamic>;
      final goal = (tables['local_goals'] as List).single as Map;
      final task = (tables['local_tasks'] as List).single as Map;
      final session =
          (tables['focus_sessions'] as List).single as Map<String, dynamic>;
      final source =
          (tables['focus_sync_sources'] as List).single as Map<String, dynamic>;
      final localCalendar =
          (tables['local_calendar_sources'] as List).single as Map;
      final event = (tables['local_calendar_blocks'] as List).single as Map;

      expect(
        goal['created_at'],
        DateTime.parse('2026-09-01T00:00:00Z').millisecondsSinceEpoch ~/ 1000,
      );
      expect(task['is_complete'], 1);
      expect(task['focus_progress_seconds'], 90);
      expect(session['status'], 'active');
      expect(state.hasUnfinishedFlow, isTrue);
      expect(
        session['effective_intervals'],
        '[{"started_at":"2026-09-02T08:00:00Z"}]',
      );
      expect(source['parent_source_ids'], '[]');
      expect(source['payload'], '{"status":"completed"}');
      expect(localCalendar['is_deleted'], 0);
      expect(localCalendar.containsKey('local_calendar_id'), isFalse);
      expect(localCalendar.containsKey('is_selected'), isFalse);
      expect(event['all_day'], 1);
      expect(
        event['starts_at'],
        DateTime.parse('2026-09-04T00:00:00Z').millisecondsSinceEpoch ~/ 1000,
      );
    },
  );

  test('rejects rows owned by another user', () async {
    final records = _emptyRecords();
    records['goals'] = [
      {
        'id': 'goal-other',
        'user_id': 'another-user',
        'title': 'Other user',
        'classification': 'regular',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
        'deleted_at': null,
      },
    ];

    await expectLater(
      converter.convert(userId: userId, records: records),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'converts more than one thousand rows without truncating the payload',
    () async {
      final records = _emptyRecords();
      records['goals'] = [
        for (var index = 0; index < 1001; index++)
          {
            'id': 'goal-$index',
            'user_id': userId,
            'title': 'Goal $index',
            'classification': 'regular',
            'created_at': '2026-09-01T00:00:00Z',
            'updated_at': '2026-09-01T00:00:00Z',
            'deleted_at': null,
          },
      ];

      final state = await converter.convert(userId: userId, records: records);

      expect(state, isNotNull);
      expect(state!.rowCount, 1001);
      final tables = state.payload['tables'] as Map<String, dynamic>;
      expect(tables['local_goals'], hasLength(1001));
    },
  );

  test(
    'reconstructs National Focus projections from stored source history',
    () async {
      final sourceDatabase = PactaDatabase(NativeDatabase.memory());
      final sourceRepository = LocalNationalFocusRepository(
        database: sourceDatabase,
        userId: userId,
      );
      try {
        await sourceRepository.createCard(
          const NationalFocusCardDraft(
            name: '开始阅读',
            triggerCondition: '开始阅读',
            action: '阅读五页',
          ),
        );
        final localSources = await (sourceDatabase.select(
          sourceDatabase.focusSyncSources,
        )..where((row) => row.userId.equals(userId))).get();
        final records = _emptyRecords();
        records['focus_sync_sources'] = [
          for (final source in localSources)
            {
              'source_id': source.sourceId,
              'user_id': source.userId,
              'device_id': source.deviceId,
              'entity_type': source.entityType,
              'entity_id': source.entityId,
              'parent_source_id': source.parentSourceId,
              'parent_source_ids': jsonDecode(source.parentSourceIds),
              'occurred_at': source.occurredAt.toUtc().toIso8601String(),
              'payload': jsonDecode(source.payload),
            },
        ];

        final state = await converter.convert(userId: userId, records: records);

        expect(state, isNotNull);
        final tables = state!.payload['tables'] as Map<String, dynamic>;
        final cards = tables['local_national_focus_cards'] as List;
        final versions =
            tables['local_national_focus_requirement_versions'] as List;
        final maintenance = tables['local_national_focus_maintenance'] as List;
        expect(cards, hasLength(1));
        expect((cards.single as Map)['trigger_condition'], '开始阅读');
        expect(versions, hasLength(1));
        expect(maintenance, hasLength(1));
      } finally {
        await sourceRepository.dispose();
        await sourceDatabase.close();
      }
    },
  );
}

Map<String, dynamic> _emptyRecords() => {
  'goals': <Object?>[],
  'tasks': <Object?>[],
  'focus_sessions': <Object?>[],
  'focus_appointments': <Object?>[],
  'focus_nodes': <Object?>[],
  'focus_chain_records': <Object?>[],
  'appointment_chain_records': <Object?>[],
  'focus_precedent_rules': <Object?>[],
  'focus_sync_sources': <Object?>[],
  'calendar_sources': <Object?>[],
  'calendar_blocks': <Object?>[],
};
