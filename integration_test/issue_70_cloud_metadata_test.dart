import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/source_device_info.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _phase = String.fromEnvironment('ISSUE70_PHASE');
const _control = String.fromEnvironment('MANUAL_SYNC_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'ISSUE70_RUNTIME_PORT',
  defaultValue: '30347',
);
const _surfaceKey = ValueKey<String>('issue70-capture-surface');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('real Android and Windows source metadata round-trip: $_phase', (
    tester,
  ) async {
    expect(
      _phase,
      anyOf('android-upload', 'windows-roundtrip', 'android-download'),
    );
    final fixture = await _startFixture(tester, 'device');
    try {
      final sourceInfo = fixture.sourceInfo;
      expect(sourceInfo.deviceName.trim(), isNotEmpty);
      expect(Platform.isAndroid || Platform.isWindows, isTrue);
      expect(
        sourceInfo.deviceName,
        endsWith(Platform.isAndroid ? ' (Android)' : ' (Windows)'),
      );
      // Report only the requested device name, manufacturer, and model.
      // ignore: avoid_print
      print(
        'ISSUE70_DEVICE_INFO platform=${Platform.operatingSystem} '
        'name=${sourceInfo.deviceName} '
        'manufacturer=${sourceInfo.manufacturer ?? 'unknown'} '
        'model=${sourceInfo.model ?? 'unknown'}',
      );

      if (_phase == 'android-upload') {
        expect(Platform.isAndroid, isTrue);
        await fixture.tasks.createGoal(
          const GoalDraft(
            title: 'Issue 70 Android cloud goal',
            description: 'Android metadata round-trip fixture',
            classification: TaskClassification.regular,
          ),
        );
      } else {
        await fixture.tasks.createGoal(
          const GoalDraft(
            title: 'Issue 70 device-only draft',
            description:
                'This row should be replaced by the confirmed download.',
            classification: TaskClassification.regular,
          ),
        );
      }

      await fixture.mount(tester);
      await _openSync(tester);

      if (_phase == 'android-upload') {
        expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);
        await _selectAndConfirm(tester, upload: true);
        final saved = await tester.runAsync(fixture.sync.inspectCloud);
        expect(saved, isNotNull);
        _expectRemoteMetadata(saved!, sourceInfo);
        expect(saved.revision, 1);
        await _openSync(tester);
        _expectVisibleMetadata(tester, saved);
        await fixture.capture(tester, 'issue70-android-upload-preview');
      } else if (_phase == 'windows-roundtrip') {
        final androidPreview = await tester.runAsync(fixture.sync.inspectCloud);
        expect(androidPreview, isNotNull);
        expect(androidPreview!.deviceName, endsWith(' (Android)'));
        _expectVisibleMetadata(tester, androidPreview);
        await fixture.capture(tester, 'issue70-windows-android-preview');

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          (await fixture.tasks.getGoals()).single.title,
          'Issue 70 device-only draft',
        );
        await _openSync(tester);
        await _selectAndConfirm(tester, upload: false);
        final downloadedGoals = await fixture.tasks.getGoals();
        expect(
          downloadedGoals.any(
            (goal) => goal.title == 'Issue 70 device-only draft',
          ),
          isFalse,
        );
        final androidGoal = downloadedGoals.singleWhere(
          (goal) => goal.title == 'Issue 70 Android cloud goal',
        );
        expect(androidGoal.description, 'Android metadata round-trip fixture');

        await fixture.tasks.createGoal(
          const GoalDraft(
            title: 'Issue 70 Windows cloud goal',
            description: 'Windows metadata round-trip fixture',
            classification: TaskClassification.regular,
          ),
        );
        await _openSync(tester);
        final local = await tester.runAsync(fixture.sync.captureLocalState);
        await _selectAndConfirm(tester, upload: true);
        final saved = await tester.runAsync(fixture.sync.inspectCloud);
        expect(saved, isNotNull);
        _expectRemoteMetadata(saved!, sourceInfo);
        expect(saved.revision, 2);
        expect(saved.rowCount, local!.rowCount);
        await _openSync(tester);
        _expectVisibleMetadata(tester, saved);
        await fixture.capture(tester, 'issue70-windows-upload-preview');

        await _verifyOtherUserIsolationAndStalePreview(tester, fixture);
      } else {
        expect(Platform.isAndroid, isTrue);
        final windowsPreview = await tester.runAsync(fixture.sync.inspectCloud);
        expect(windowsPreview, isNotNull);
        expect(windowsPreview!.deviceName, endsWith(' (Windows)'));
        _expectVisibleMetadata(tester, windowsPreview);
        await fixture.capture(tester, 'issue70-android-windows-preview');

        await _selectAndConfirm(tester, upload: false);
        final goals = await fixture.tasks.getGoals();
        expect(
          goals.any((goal) => goal.title == 'Issue 70 device-only draft'),
          isFalse,
        );
        expect(
          goals
              .singleWhere(
                (goal) => goal.title == 'Issue 70 Android cloud goal',
              )
              .description,
          'Android metadata round-trip fixture',
        );
        expect(
          goals
              .singleWhere(
                (goal) => goal.title == 'Issue 70 Windows cloud goal',
              )
              .description,
          'Windows metadata round-trip fixture',
        );
        final local = await fixture.sync.captureLocalState();
        final result = await fixture.sync.loadSyncResult();
        expect(result, isNotNull);
        expect(result!.localFingerprint, local.fingerprint);
        expect(result.cloudRevision, windowsPreview.revision);
      }
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print('ISSUE70_CLOUD_PHASE_PASSED $_phase');
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'legacy old-table preview remains selectable with unknown device metadata',
    (tester) async {
      expect(Platform.isWindows, isTrue);
      final fixture = await _startFixture(tester, 'legacy');
      try {
        await fixture.tasks.createGoal(
          const GoalDraft(
            title: 'Issue 70 local legacy draft',
            classification: TaskClassification.regular,
          ),
        );
        await fixture.mount(tester);
        await _openSync(tester);
        expect(find.text('云端来源：旧版云数据（来源设备未记录）'), findsOneWidget);
        expect(find.text('型号未知'), findsOneWidget);
        expect(find.text('发现旧版云端记录，将转换为整份数据；原设备和上传时间未记录。'), findsOneWidget);
        expect(find.text('下载'), findsOneWidget);
        await fixture.capture(tester, 'issue70-windows-legacy-preview');

        await _selectAndConfirm(tester, upload: false);
        final goals = await fixture.tasks.getGoals();
        expect(
          goals.any((goal) => goal.title == 'Issue 70 local legacy draft'),
          isFalse,
        );
        expect(
          goals
              .singleWhere(
                (goal) => goal.title == 'Issue 70 legacy cloud preview fixture',
              )
              .classification,
          TaskClassification.regular,
        );
        expect(tester.takeException(), isNull);
        // ignore: avoid_print
        print('ISSUE70_LEGACY_PREVIEW_PASSED selectable=true model=unknown');
      } finally {
        await fixture.close(tester);
      }
    },
    skip: _phase != 'windows-roundtrip',
  );
}

Future<_DeviceFixture> _startFixture(
  WidgetTester tester,
  String purpose,
) async {
  final fetchedConfig = await tester.runAsync(() async {
    final response = await http.get(
      Uri.parse('http://127.0.0.1:$_port/session?user=$purpose'),
      headers: {'X-Pacta-Acceptance': _control},
    );
    if (response.statusCode != 200) {
      throw StateError('Issue 70 runtime acceptance session unavailable.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  });
  expect(fetchedConfig, isNotNull);
  final config = fetchedConfig!;
  final client = SupabaseClient(
    config['url'] as String,
    config['publishableKey'] as String,
  );
  await tester.runAsync(
    () => client.auth.setSession(config['refreshToken'] as String),
  );
  final userId = config['userId'] as String;
  expect(client.auth.currentUser?.id, userId);
  final sourceInfo = await SourceDeviceInfo.load();
  final directory = await Directory.systemTemp.createTemp(
    'pacta-issue70-cloud-',
  );
  final database = PactaDatabase(
    NativeDatabase(File('${directory.path}/business.sqlite')),
  );
  var clock = DateTime.now().toUtc();
  final sync = CloudSnapshotRepository(
    database: database,
    remote: SupabaseCloudSnapshotRemote(client),
    userId: userId,
    deviceId: Platform.isAndroid ? 'issue70-android' : 'issue70-windows',
    deviceName: sourceInfo.deviceName,
    deviceManufacturer: sourceInfo.manufacturer,
    deviceModel: sourceInfo.model,
    now: () => clock,
  );
  final tasks = LocalTaskRepository(
    database: database,
    userId: userId,
    remote: const UnavailableTaskRemoteDataSource(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  final focus = LocalFocusRepository(
    database: database,
    userId: userId,
    remote: const UnavailableFocusRemoteDataSource(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  final national = LocalNationalFocusRepository(
    database: database,
    userId: userId,
    remote: const UnavailableNationalFocusRemoteDataSource(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  final authRepository = SupabaseAuthRepository(client);
  final fixture = _DeviceFixture(
    client: client,
    userId: userId,
    sourceInfo: sourceInfo,
    directory: directory,
    database: database,
    sync: sync,
    tasks: tasks,
    focus: focus,
    national: national,
    authRepository: authRepository,
  );
  return fixture;
}

Future<void> _openSync(WidgetTester tester) async {
  if (find.byTooltip('查看云端并选择方向').evaluate().isEmpty) {
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
  }
  final entry = find.byTooltip('查看云端并选择方向');
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await _waitForText(tester, '选择同步方式');
}

Future<void> _selectAndConfirm(
  WidgetTester tester, {
  required bool upload,
}) async {
  await tester.tap(find.text(upload ? '上传' : '下载'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(upload ? '确认上传' : '确认下载'));
  await _waitForText(tester, upload ? '上传完成，已覆盖云端数据。' : '下载完成，已覆盖本机数据。');
}

void _expectRemoteMetadata(
  CloudSnapshotMetadata cloud,
  SourceDeviceInfo source,
) {
  expect(cloud.deviceName, source.deviceName);
  expect(cloud.deviceManufacturer, source.manufacturer);
  expect(cloud.deviceModel, source.model);
}

void _expectVisibleMetadata(WidgetTester tester, CloudSnapshotMetadata cloud) {
  expect(find.text('云端来源：${cloud.deviceName}'), findsOneWidget);
  expect(
    find.textContaining(_normalize(cloud.deviceModel) ?? '型号未知'),
    findsOneWidget,
  );
  final manufacturer = _normalize(cloud.deviceManufacturer);
  if (manufacturer != null) {
    expect(find.textContaining(manufacturer), findsOneWidget);
  }
}

String? _normalize(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Future<void> _verifyOtherUserIsolationAndStalePreview(
  WidgetTester tester,
  _DeviceFixture owner,
) async {
  final fetchedConfig = await tester.runAsync(() async {
    final response = await http.get(
      Uri.parse('http://127.0.0.1:$_port/session?user=concurrency'),
      headers: {'X-Pacta-Acceptance': _control},
    );
    if (response.statusCode != 200) {
      throw StateError('Issue 70 isolation session unavailable.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  });
  expect(fetchedConfig, isNotNull);
  final config = fetchedConfig!;
  final otherClient = SupabaseClient(
    config['url'] as String,
    config['publishableKey'] as String,
  );
  final otherUserId = config['userId'] as String;
  final database = PactaDatabase(NativeDatabase.memory());
  final otherRemote = SupabaseCloudSnapshotRemote(otherClient);
  try {
    await tester.runAsync(
      () => otherClient.auth.setSession(config['refreshToken'] as String),
    );
    expect(otherClient.auth.currentUser?.id, otherUserId);
    final foreignRow = await tester.runAsync(
      () => otherClient
          .from('cloud_business_snapshots')
          .select('revision,device_name')
          .eq('user_id', owner.userId)
          .maybeSingle(),
    );
    expect(foreignRow, isNull);

    final sync = CloudSnapshotRepository(
      database: database,
      remote: otherRemote,
      userId: otherUserId,
      deviceId: 'issue70-other-user',
      deviceName: 'Issue 70 isolated second user',
    );
    final local = await sync.captureLocalState();
    final first = await tester.runAsync(
      () => sync.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: local.fingerprint,
      ),
    );
    final firstResult = first!;
    expect(firstResult.revision, 1);
    final second = await tester.runAsync(
      () => otherRemote.upload(
        userId: otherUserId,
        expectedRevision: firstResult.revision,
        payload: local.payload,
        deviceId: 'issue70-preview-race',
        deviceName: 'Issue 70 preview race writer',
        dataUpdatedAt: local.dataUpdatedAt.add(const Duration(minutes: 1)),
        rowCount: local.rowCount,
      ),
    );
    final secondResult = second!;
    expect(secondResult.revision, 2);
    final staleDownload = await tester.runAsync(() async {
      try {
        await sync.downloadCloud(
          expectedRevision: firstResult.revision,
          expectedFingerprint: local.fingerprint,
        );
        return false;
      } on StateError catch (error) {
        return error.message.toString().contains('云端快照已变化');
      }
    });
    expect(staleDownload, isTrue);
    expect((await sync.captureLocalState()).fingerprint, local.fingerprint);
    expect((await tester.runAsync(sync.inspectCloud))!.revision, 2);
    final ownerCloud = await tester.runAsync(owner.sync.inspectCloud);
    expect(ownerCloud!.revision, 2);
    expect(ownerCloud.deviceName, owner.sourceInfo.deviceName);
    expect(ownerCloud.deviceManufacturer, owner.sourceInfo.manufacturer);
    expect(ownerCloud.deviceModel, owner.sourceInfo.model);
    // ignore: avoid_print
    print('ISSUE70_RLS_OTHER_USER_HIDDEN=true STALE_PREVIEW_REJECTED=true');
  } finally {
    await otherClient.dispose();
    await database.close();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('pacta.device.cloud_sync.result.$otherUserId');
  }
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(text).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Expected Issue 70 cloud UI state did not arrive: $text');
}

class _DeviceFixture {
  _DeviceFixture({
    required this.client,
    required this.userId,
    required this.sourceInfo,
    required this.directory,
    required this.database,
    required this.sync,
    required this.tasks,
    required this.focus,
    required this.national,
    required this.authRepository,
  });

  final SupabaseClient client;
  final String userId;
  final SourceDeviceInfo sourceInfo;
  final Directory directory;
  final PactaDatabase database;
  final CloudSnapshotRepository sync;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository national;
  final SupabaseAuthRepository authRepository;
  bool mounted = false;

  Future<void> mount(WidgetTester tester) async {
    if (mounted) return;
    await tester.pumpWidget(
      RepaintBoundary(
        key: _surfaceKey,
        child: PactaApp(
          authRepository: authRepository,
          taskRepositoryFactory: (_) => LocalTaskRepository(
            database: database,
            userId: userId,
            remote: const UnavailableTaskRemoteDataSource(),
            cloudSyncEnabled: false,
          ),
          focusRepositoryFactory: (_) => LocalFocusRepository(
            database: database,
            userId: userId,
            remote: const UnavailableFocusRemoteDataSource(),
            cloudSyncEnabled: false,
          ),
          nationalFocusRepositoryFactory: (_) => LocalNationalFocusRepository(
            database: database,
            userId: userId,
            remote: const UnavailableNationalFocusRemoteDataSource(),
            cloudSyncEnabled: false,
          ),
          calendarRepositoryFactory: (_) => LocalCalendarRepository(
            database: database,
            userId: userId,
            provider: const UnsupportedCalendarProvider(),
            remote: const UnavailableCalendarRemoteDataSource(),
            cloudSyncEnabled: false,
          ),
          userLifecycleRepositoryFactory: (_) => UserLifecycleRepository(
            authRepository: authRepository,
            localAccess: LocalUserLifecycleAccess(
              database: database,
              userId: userId,
            ),
          ),
          cloudSnapshotRepositoryFactory: (_) => sync,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.isAndroid) {
      await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .convertFlutterSurfaceToImage();
      await tester.pump();
    }
    mounted = true;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_surfaceKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final support = await getApplicationSupportDirectory();
    await File('${support.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tasks.dispose();
    await focus.dispose();
    await national.dispose();
    await database.close();
    await client.dispose();
    await directory.delete(recursive: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('pacta.device.cloud_sync.result.$userId');
  }
}
