import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/app/app_providers.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/profile/my_page.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_database.dart';

const _userId = 'my-page-user';

/// 只记录「重置记录」相关调用的通知服务：提醒的取消是这次清理的可观察结果。
class _RecordingNotificationService extends DisabledFocusNotificationService {
  bool? pendingConfirmations;
  List<Schedule>? schedules;
  String? timeZoneId;

  @override
  Future<void> syncNationalFocusReminder({
    required bool hasPendingConfirmations,
  }) async {
    pendingConfirmations = hasPendingConfirmations;
  }

  @override
  Future<void> syncScheduleReminders({
    required List<Schedule> schedules,
    required String timeZoneId,
  }) async {
    this.schedules = schedules;
    this.timeZoneId = timeZoneId;
  }
}

void main() {
  late PactaDatabase database;
  late CloudSnapshotRepository cloud;
  late _RecordingNotificationService notifications;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 名片与云同步卡片都在监听 Drift 查询流：同步关闭流，测试结束后
    // 不会留下等着关流的零延迟计时器。
    database = openTestDatabase();
    cloud = CloudSnapshotRepository(
      database: database,
      remote: InMemoryCloudSnapshotRemote(),
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      now: () => DateTime.utc(2026, 11, 20, 4),
    );
    notifications = _RecordingNotificationService();
    await _seed(database);
  });

  tearDown(() => database.close());

  testWidgets('我的 → 编辑资料 → 重置：清空记录并同时清掉待发提醒', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthRepository()..signedInUser = _userId;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryFactoryProvider.overrideWithValue(
            (userId) =>
                LocalProfileRepository(database: database, userId: userId),
          ),
          cloudSnapshotRepositoryFactoryProvider.overrideWithValue(
            (_) => cloud,
          ),
          focusNotificationServiceProvider.overrideWithValue(notifications),
        ],
        child: MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: const Scaffold(body: MyPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 个人名片整行即《编辑资料》入口。
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditPage), findsOneWidget);

    final entry = find.text('重置所有记录');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('profile-reset-records-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('已重置所有记录；卡片、规则与任务已保留。'), findsOneWidget);
    expect(await _count(database, 'focus_sessions'), 0);
    expect(
      (await _rows(
        database,
        "SELECT state, successful_days FROM local_national_focus_cards "
        "WHERE id = 'card-1'",
      )).single['successful_days'],
      0,
    );
    // MyPage 在重置后清掉待发提醒：没有待确认卡片，也没有任何日程。
    expect(notifications.pendingConfirmations, isFalse);
    expect(notifications.schedules, isEmpty);
    expect(notifications.timeZoneId, isNotNull);
    expect(await cloud.listLocalRecoveryPoints(), hasLength(1));
  });
}

Future<int> _count(PactaDatabase database, String table) async {
  final rows = await database
      .customSelect(
        'SELECT COUNT(*) AS total FROM "$table" WHERE user_id = ?',
        variables: [Variable<String>(_userId)],
      )
      .get();
  return rows.single.read<int>('total');
}

Future<List<Map<String, Object?>>> _rows(
  PactaDatabase database,
  String sql,
) async {
  final result = await database.customSelect(sql).get();
  return [for (final row in result) Map<String, Object?>.from(row.data)];
}

Future<void> _insert(
  PactaDatabase database,
  String table,
  Map<String, Object?> values,
) {
  final columns = values.keys.toList();
  final names = columns.map((column) => '"$column"').join(',');
  final placeholders = List.filled(columns.length, '?').join(',');
  return database.customStatement(
    'INSERT INTO "$table" ($names) VALUES ($placeholders)',
    [for (final column in columns) values[column]],
  );
}

Future<void> _seed(PactaDatabase database) async {
  int seconds(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;
  final created = seconds(DateTime.utc(2026, 11, 1, 1));
  final updated = seconds(DateTime.utc(2026, 11, 5, 2));
  final started = seconds(DateTime.utc(2026, 11, 6, 1));

  await _insert(database, 'local_goals', {
    'user_id': _userId,
    'id': 'goal-1',
    'title': '保留目标',
    'description': '',
    'classification': 'regular',
    'created_at': created,
    'updated_at': updated,
    'is_pinned': 0,
    'sort_order': null,
    'deleted_at': null,
  });
  await _insert(database, 'local_tasks', {
    'user_id': _userId,
    'id': 'task-1',
    'goal_id': 'goal-1',
    'title': '保留任务',
    'description': '',
    'classification': 'regular',
    'estimated_minutes': 25,
    'deadline': null,
    'is_complete': 1,
    'focus_progress_seconds': 600,
    'created_at': created,
    'updated_at': updated,
    'deleted_at': null,
  });
  await _insert(database, 'local_national_focus_cards', {
    'user_id': _userId,
    'id': 'card-1',
    'name': '根国策',
    'trigger_condition': '打开待办清单',
    'action': '先写第一步',
    'scope': null,
    'exception_notes': null,
    'is_in_tree': 1,
    'parent_id': null,
    'state': 'lit',
    'successful_days': 7,
    'current_consecutive_days': 3,
    'best_consecutive_days': 5,
    'maintenance_cycle_started': 1,
    'failure_reason': null,
    'cascade_source_card_id': null,
    'cascade_prior_state': null,
    'review_disposition': 'accepted',
    'active_strengthening_level': null,
    'created_at': created,
    'updated_at': updated,
    'deleted_at': null,
  });
  await _insert(database, 'focus_sessions', {
    'user_id': _userId,
    'id': 'session-1',
    'appointment_id': null,
    'task_id': 'task-1',
    'mode': 'regular',
    'duration_seconds': 1500,
    'started_at': started,
    'ends_at': started + 1500,
    'status': 'completed',
    'completed_at': started + 1500,
    'effective_seconds': 1500,
    'completion_type': 'countdown',
    'completion_rule_text': null,
    'paused_at': null,
    'paused_seconds': 0,
    'pause_rule_text': null,
    'failure_reason': null,
    'effective_intervals': '[]',
    'review_disposition': 'accepted',
    'review_disposition_updated_at': null,
    'configuration_basis_source_id': null,
    'outcome_basis_source_id': null,
  });
}
