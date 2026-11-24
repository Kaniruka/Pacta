import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/avatar_picker.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/sync/cloud_recovery_point.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPicker implements AvatarPicker {
  const _NoPicker();

  @override
  Future<Uint8List?> pickSingleImage() async => null;
}

/// 「重置所有记录」的入口与确认流程。
void main() {
  late PactaDatabase database;
  late CloudSnapshotRepository cloud;
  late LocalProfileRepository profile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    cloud = CloudSnapshotRepository(
      database: database,
      remote: InMemoryCloudSnapshotRemote(),
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
      now: () => DateTime.utc(2026, 11, 20, 4),
    );
    profile = LocalProfileRepository(database: database, userId: 'user-a');
    await _seed(database);
  });

  tearDown(() => database.close());

  Widget page({
    Future<void> Function()? onCancelPendingUpload,
    Future<void> Function()? onRecordsReset,
    bool injectCloud = true,
  }) => MaterialApp(
    theme: pactaTheme(Brightness.light),
    home: ProfileEditPage(
      repository: profile,
      avatarPicker: const _NoPicker(),
      cloudSnapshotRepository: injectCloud ? cloud : null,
      onCancelPendingUpload: onCancelPendingUpload,
      onRecordsReset: onRecordsReset,
    ),
  );

  testWidgets('未注入仓储时不渲染危险操作区，旧调用方不受影响', (tester) async {
    await pumpPage(tester, page(injectCloud: false));

    expect(find.text('重置所有记录'), findsNothing);
    expect(find.text('危险操作'), findsNothing);
    expect(find.byIcon(Icons.restart_alt_outlined), findsNothing);
  });

  testWidgets('编辑资料底部提供重置所有记录的分组行', (tester) async {
    await pumpPage(tester, page());

    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('重置所有记录'), findsOneWidget);
    expect(find.text('清空全部记录与进度，保留卡片、规则与任务'), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_outlined), findsOneWidget);
    // 重置行挂在《编辑资料》底部的危险操作区，与「账号安全」各自成段：
    // 未注入登录仓储时账号安全不出现，重置入口也不依赖它。
    expect(
      find.byKey(const ValueKey('profile-reset-records-entry')),
      findsOneWidget,
    );
  });

  testWidgets('确认对话框列清保留项、销毁项与本机范围', (tester) async {
    await pumpPage(tester, page());

    await tapResetEntry(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('保留'), findsOneWidget);
    expect(find.textContaining('国策卡与国策树布局'), findsOneWidget);
    expect(find.textContaining('下必为例与专注信号'), findsOneWidget);
    expect(find.textContaining('目标（含置顶与排序）与任务'), findsOneWidget);
    expect(find.text('销毁'), findsOneWidget);
    expect(find.textContaining('点亮、连击、内化与失败记录'), findsOneWidget);
    expect(find.textContaining('专注与预约记录'), findsOneWidget);
    expect(find.textContaining('任务的完成状态与专注进度'), findsOneWidget);
    expect(find.textContaining('全部日程、重复规则与导入副本'), findsOneWidget);
    expect(find.text('仅重置本机，不自动覆盖云端；重置前会自动保存本机恢复点。'), findsOneWidget);
  });

  testWidgets('取消确认后不改任何数据，也不回调宿主', (tester) async {
    var resets = 0;
    await tester.pumpWidget(page(onRecordsReset: () async => resets++));
    await tester.pumpAndSettle();

    await tapResetEntry(tester);
    await tester.tap(
      find.byKey(const ValueKey('profile-reset-records-cancel')),
    );
    await tester.pumpAndSettle();

    expect(resets, 0);
    expect(await _count(database, 'focus_sessions'), 1);
    expect(
      (await _rows(
        database,
        "SELECT state FROM local_national_focus_cards WHERE id = 'card-1'",
      )).single['state'],
      'lit',
    );
    expect(await cloud.listLocalRecoveryPoints(), isEmpty);
  });

  testWidgets('确认后先取消待传上传，再重置记录并回调宿主', (tester) async {
    final calls = <String>[];
    int? sessionsWhenNotified;
    final widget = page(
      onCancelPendingUpload: () async => calls.add('cancel'),
      onRecordsReset: () async {
        calls.add('reset');
        sessionsWhenNotified = await _count(database, 'focus_sessions');
      },
    );
    await pumpPage(tester, widget);

    await tapResetEntry(tester);
    await tester.tap(
      find.byKey(const ValueKey('profile-reset-records-confirm')),
    );
    await tester.pumpAndSettle();

    expect(calls, ['cancel', 'reset'], reason: '取消待传队列必须早于清空');
    expect(sessionsWhenNotified, 0);
    expect(find.text('已重置所有记录；卡片、规则与任务已保留。'), findsOneWidget);
    expect(await _count(database, 'focus_sessions'), 0);
    expect(await _count(database, 'local_schedules'), 0);
    expect(
      (await _rows(
        database,
        "SELECT state, successful_days FROM local_national_focus_cards "
        "WHERE id = 'card-1'",
      )).single['successful_days'],
      0,
    );
    expect(
      (await _rows(
        database,
        "SELECT is_complete FROM local_tasks WHERE id = 'task-1'",
      )).single['is_complete'],
      0,
    );
    final points = await cloud.listLocalRecoveryPoints();
    expect(points.single.reason, CloudRecoveryReason.beforeRecordReset);
  });

  testWidgets('存在未结束的专注时先提示结束，不弹确认也不改数据', (tester) async {
    await database.customStatement(
      "UPDATE focus_sessions SET status = 'active' WHERE id = 'session-1'",
    );
    await pumpPage(tester, page());

    await tapResetEntry(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('预约或专注尚未结束，请先结束当前专注或预约，再重置数据。'), findsOneWidget);
    expect(await _count(database, 'focus_sessions'), 1);
    expect(await cloud.listLocalRecoveryPoints(), isEmpty);
  });

  testWidgets('确认期间数据变化时如实提示并保留全部记录', (tester) async {
    await pumpPage(tester, page());

    await tapResetEntry(tester);
    // 对话框打开期间另一处改了本机数据：仓储必须以指纹不一致整体放弃。
    await database.customStatement(
      "UPDATE local_goals SET title = '别处改过的标题' WHERE id = 'goal-1'",
    );
    await tester.tap(
      find.byKey(const ValueKey('profile-reset-records-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('本机数据在确认期间发生变化，请重新检查后再重置。'), findsOneWidget);
    expect(await _count(database, 'focus_sessions'), 1);
    expect(await _count(database, 'local_schedules'), 1);
  });
}

/// 打开编辑页：测试画布足够高，底部危险操作区不必滚动就能断言；
/// 点击入口仍先 ensureVisible，窄高度下也稳定。
Future<void> pumpPage(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

Future<void> tapResetEntry(WidgetTester tester) async {
  final entry = find.text('重置所有记录');
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<int> _count(PactaDatabase database, String table) async {
  final rows = await database
      .customSelect(
        'SELECT COUNT(*) AS total FROM "$table" WHERE user_id = ?',
        variables: [Variable<String>('user-a')],
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
    'user_id': 'user-a',
    'id': 'goal-1',
    'title': '保留目标',
    'description': '',
    'classification': 'regular',
    'created_at': created,
    'updated_at': updated,
    'is_pinned': 1,
    'sort_order': 1,
    'deleted_at': null,
  });
  await _insert(database, 'local_tasks', {
    'user_id': 'user-a',
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
    'user_id': 'user-a',
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
    'current_consecutive_days': 4,
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
    'user_id': 'user-a',
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
  await _insert(database, 'local_schedules', {
    'user_id': 'user-a',
    'id': 'schedule-1',
    'title': '日程',
    'notes': '',
    'starts_at': started,
    'ends_at': started + 3600,
    'all_day': 0,
    'all_day_start_date': null,
    'all_day_end_date_exclusive': null,
    'is_completed': 0,
    'completed_at': null,
    'task_id': 'task-1',
    'reminder_minutes_before': null,
    'origin': 'owned',
    'source_ids': '[]',
    'source_names': '[]',
    'source_event_id': null,
    'occurrence_id': null,
    'event_identity': null,
    'recurrence_id': null,
    'recurrence_series_id': null,
    'recurrence_date': null,
    'recurrence_time_zone_id': null,
    'recurrence_start_minutes': null,
    'is_recurrence_exception': 0,
    'is_recurrence_cancelled': 0,
    'created_at': created,
    'updated_at': updated,
  });
}
