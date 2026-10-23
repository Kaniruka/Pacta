import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _phase = String.fromEnvironment('MANUAL_SYNC_REAL_CLOUD_PHASE');
const _control = String.fromEnvironment('MANUAL_SYNC_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'MANUAL_SYNC_RUNTIME_PORT',
  defaultValue: '30347',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  testWidgets('real service manual whole-data transfer: $_phase', (
    tester,
  ) async {
    expect(
      _phase,
      anyOf('android-upload', 'windows-roundtrip', 'android-download'),
    );
    expect(_control, isNotEmpty);
    final configuration = await tester.runAsync(() async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$_port/session?user=device'),
        headers: {'X-Pacta-Acceptance': _control},
      );
      if (response.statusCode != 200) {
        throw StateError('Runtime acceptance session unavailable.');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
    final config = configuration!;
    final client = SupabaseClient(
      config['url'] as String,
      config['publishableKey'] as String,
    );
    await tester.runAsync(
      () => client.auth.setSession(config['refreshToken'] as String),
    );
    final userId = config['userId'] as String;
    expect(client.auth.currentUser?.id, userId);
    final directory = await Directory.systemTemp.createTemp(
      'pacta-manual-real-cloud-',
    );
    final databaseFile = File('${directory.path}/business.sqlite');
    final database = PactaDatabase(NativeDatabase(databaseFile));
    final remote = _ObservedCloudRemote(client);
    final sync = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: userId,
      deviceId: Platform.isAndroid
          ? 'acceptance-android'
          : 'acceptance-windows',
      deviceName: Platform.isAndroid
          ? 'Android 15 emulator'
          : 'Windows 11 acceptance client',
    );
    var clock = DateTime.now().toUtc();
    final seedTasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: const UnavailableTaskRemoteDataSource(),
      cloudSyncEnabled: false,
      now: () => clock,
    );
    final seedFocus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: const UnavailableFocusRemoteDataSource(),
      cloudSyncEnabled: false,
      now: () => clock,
    );
    final seedNational = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      remote: const UnavailableNationalFocusRemoteDataSource(),
      cloudSyncEnabled: false,
      now: () => clock,
    );
    var databaseClosed = false;
    try {
      if (_phase == 'android-upload') {
        final goal = await seedTasks.createGoal(
          const GoalDraft(
            title: 'Android cloud goal',
            description: 'Android goal description survives cloud sync',
            classification: TaskClassification.both,
          ),
        );
        final task = await seedTasks.createTask(
          goal.id,
          const TaskDraft(
            title: 'Android cloud task',
            description: 'Android task description survives cloud sync',
            classification: TaskClassification.both,
          ),
        );
        final session = await seedFocus.startSession(
          taskId: task.id,
          mode: FocusChainMode.regular,
          duration: const Duration(seconds: 15),
        );
        clock = clock.add(const Duration(seconds: 16));
        await seedFocus.settleDueSessions();
        expect(
          (await seedFocus.getSession(session.id))!.status,
          FocusSessionStatus.completed,
        );
        final card = await seedNational.createCard(
          const NationalFocusCardDraft(
            name: 'Before real sync',
            triggerCondition: 'Before real sync',
            action: 'Keep Android national focus history',
          ),
        );
        await seedNational.placeCard(cardId: card.id, parentId: null);
        await seedNational.lightCard(card.id);
      } else {
        await seedTasks.createGoal(
          const GoalDraft(
            title: 'Device-only draft to discard',
            classification: TaskClassification.regular,
          ),
        );
      }
      await tester.pumpWidget(
        PactaApp(
          authRepository: SupabaseAuthRepository(client),
          taskRepositoryFactory: (_) => LocalTaskRepository(
            database: database,
            userId: userId,
            remote: const UnavailableTaskRemoteDataSource(),
            cloudSyncEnabled: false,
            now: () => clock,
          ),
          focusRepositoryFactory: (_) => LocalFocusRepository(
            database: database,
            userId: userId,
            remote: const UnavailableFocusRemoteDataSource(),
            cloudSyncEnabled: false,
            now: () => clock,
          ),
          nationalFocusRepositoryFactory: (_) => LocalNationalFocusRepository(
            database: database,
            userId: userId,
            remote: const UnavailableNationalFocusRemoteDataSource(),
            cloudSyncEnabled: false,
            now: () => clock,
          ),
          calendarRepositoryFactory: (_) => LocalCalendarRepository(
            database: database,
            userId: userId,
            provider: const UnsupportedCalendarProvider(),
            remote: const UnavailableCalendarRemoteDataSource(),
            cloudSyncEnabled: false,
          ),
          userLifecycleRepositoryFactory: (_) => UserLifecycleRepository(
            authRepository: SupabaseAuthRepository(client),
            localAccess: LocalUserLifecycleAccess(
              database: database,
              userId: userId,
            ),
          ),
          cloudSnapshotRepositoryFactory: (_) => sync,
        ),
      );
      await tester.pumpAndSettle();
      expect(remote.inspections, 0);
      expect(remote.uploads, 0);
      expect(remote.downloads, 0);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('查看云端并选择方向'));
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await _waitForText(tester, '选择同步方式');
      if (_phase == 'android-upload') {
        expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);
        await tester.tap(find.text('上传'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认上传'));
        await _waitForText(tester, '上传完成，已覆盖云端数据。');
        expect(remote.uploads, 1);
        expect(remote.downloads, 0);
        final cloud = await tester.runAsync(
          () => remote.inspect(userId: userId),
        );
        expect(cloud!.deviceName, 'Android 15 emulator');
        expect(cloud.revision, 1);
      } else {
        expect(
          find.text(
            _phase == 'windows-roundtrip'
                ? '云端来源：Android 15 emulator'
                : '云端来源：Windows 11 acceptance client',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          (await seedTasks.getGoals()).single.title,
          'Device-only draft to discard',
        );
        expect(remote.downloads, 0);
        await tester.tap(find.byTooltip('查看云端并选择方向'));
        await _waitForText(tester, '选择同步方式');
        await tester.tap(find.text('下载'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认下载'));
        await _waitForText(tester, '下载完成，已覆盖本机数据。');
        expect(remote.downloads, 1);
        final goals = await seedTasks.getGoals();
        expect(
          goals.any((goal) => goal.title == 'Device-only draft to discard'),
          isFalse,
        );
        expect(goals.any((goal) => goal.title == 'Android cloud goal'), isTrue);
        final androidGoal = goals.singleWhere(
          (goal) => goal.title == 'Android cloud goal',
        );
        expect(
          androidGoal.description,
          'Android goal description survives cloud sync',
        );
        expect(
          androidGoal.tasks.single.description,
          'Android task description survives cloud sync',
        );
        expect(await seedFocus.getSessions(), hasLength(1));
        expect(
          (await seedFocus.getSessions()).single.status,
          FocusSessionStatus.completed,
        );
        expect(await seedNational.getTreeCards(), hasLength(1));
        if (_phase == 'windows-roundtrip') {
          await seedTasks.createGoal(
            const GoalDraft(
              title: 'Windows cloud addition',
              description: 'Windows goal description survives cloud sync',
              classification: TaskClassification.regular,
            ),
          );
          await tester.tap(find.byTooltip('查看云端并选择方向'));
          await _waitForText(tester, '选择同步方式');
          await tester.tap(find.text('上传'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('确认上传'));
          await _waitForText(tester, '上传完成，已覆盖云端数据。');
          expect(remote.uploads, 1);
          final cloud = await tester.runAsync(
            () => remote.inspect(userId: userId),
          );
          expect(cloud!.deviceName, 'Windows 11 acceptance client');
          expect(cloud.revision, 2);
          final uploaded = await tester.runAsync(
            () => remote.download(userId: userId),
          );
          final uploadedGoalRows =
              (uploaded!.payload!['tables']
                      as Map<String, dynamic>)['local_goals']
                  as List;
          expect(
            uploadedGoalRows.singleWhere(
              (row) => row['title'] == 'Windows cloud addition',
            )['description'],
            'Windows goal description survives cloud sync',
          );
        } else {
          expect(
            goals.any((goal) => goal.title == 'Windows cloud addition'),
            isTrue,
          );
          final androidGoal = goals.singleWhere(
            (goal) => goal.title == 'Android cloud goal',
          );
          final windowsGoal = goals.singleWhere(
            (goal) => goal.title == 'Windows cloud addition',
          );
          expect(
            androidGoal.description,
            'Android goal description survives cloud sync',
          );
          expect(
            androidGoal.tasks.single.description,
            'Android task description survives cloud sync',
          );
          expect(
            windowsGoal.description,
            'Windows goal description survives cloud sync',
          );
          final preview = await sync.captureLocalState();
          final cloud = await tester.runAsync(
            () => remote.inspect(userId: userId),
          );
          await tester.runAsync(
            () => sync.downloadCloud(
              expectedRevision: cloud!.revision,
              expectedFingerprint: preview.fingerprint,
            ),
          );
          expect(await seedFocus.getSessions(), hasLength(1));
          expect(await seedFocus.getNodes(), hasLength(1));
        }
      }
      final result = await sync.loadSyncResult();
      expect(result, isNotNull);
      final finalLocal = await sync.captureLocalState();
      expect(result!.localFingerprint, finalLocal.fingerprint);
      final inspected = await tester.runAsync(sync.inspectCloud);
      expect(result.cloudRevision, inspected!.revision);
      expect((await sync.loadSyncResult())!.succeededAt, result.succeededAt);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final expectedTitles = (await seedTasks.getGoals())
          .map((goal) => goal.title)
          .toSet();
      await seedTasks.dispose();
      await seedFocus.dispose();
      await seedNational.dispose();
      await database.close();
      databaseClosed = true;
      final reopened = PactaDatabase(NativeDatabase(databaseFile));
      final persistedGoals = await reopened.select(reopened.localGoals).get();
      expect(persistedGoals.map((row) => row.title).toSet(), expectedTitles);
      await reopened.close();
      debugPrint('REAL_MANUAL_CLOUD_PHASE_PASSED $_phase');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      if (!databaseClosed) {
        await seedTasks.dispose();
        await seedFocus.dispose();
        await seedNational.dispose();
        await database.close();
      }
      await client.dispose();
      await directory.delete(recursive: true);
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('pacta.device.cloud_sync.result.$userId');
    }
  }, skip: _phase == 'windows-conflict');

  testWidgets(
    'real service rejects stale previews and malformed downloads without local loss',
    (tester) async {
      final config = await tester.runAsync(() async {
        final response = await http.get(
          Uri.parse('http://127.0.0.1:$_port/session?user=concurrency'),
          headers: {'X-Pacta-Acceptance': _control},
        );
        if (response.statusCode != 200) {
          throw StateError('Runtime acceptance session unavailable.');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      });
      final transport = _OfflineProbeHttpClient(http.Client());
      final client = SupabaseClient(
        config!['url'] as String,
        config['publishableKey'] as String,
        httpClient: transport,
      );
      final database = PactaDatabase(NativeDatabase.memory());
      try {
        await tester.runAsync(
          () => client.auth.setSession(config['refreshToken'] as String),
        );
        final userId = config['userId'] as String;
        final remote = SupabaseCloudSnapshotRemote(client);
        var syncClock = DateTime.utc(2026, 10, 23, 12);
        final sync = CloudSnapshotRepository(
          database: database,
          remote: remote,
          userId: userId,
          deviceId: 'windows-conflict-probe',
          deviceName: 'Windows SDK conflict probe',
          now: () => syncClock,
        );
        final tasks = LocalTaskRepository(
          database: database,
          userId: userId,
          remote: const UnavailableTaskRemoteDataSource(),
          cloudSyncEnabled: false,
        );
        final goal = await tasks.createGoal(
          const GoalDraft(
            title: 'Retain through offline transport',
            description:
                'Goal text that an old version 1 snapshot cannot carry',
            classification: TaskClassification.regular,
          ),
        );
        await tasks.createTask(
          goal.id,
          const TaskDraft(
            title: 'Keep linked task data',
            description:
                'Task text that an old version 1 snapshot cannot carry',
            classification: TaskClassification.regular,
          ),
        );
        final preview = await tester.runAsync(sync.inspectCloud);
        final local = await sync.captureLocalState();
        final initialRevision = preview?.revision ?? 0;
        final first = await tester.runAsync(
          () => sync.uploadLocal(
            expectedRevision: initialRevision,
            expectedFingerprint: local.fingerprint,
          ),
        );
        final firstResult = (await sync.loadSyncResult())!;
        expect(firstResult.succeededAt, syncClock);
        expect(firstResult.localFingerprint, local.fingerprint);
        expect(firstResult.cloudRevision, first!.revision);
        syncClock = syncClock.add(const Duration(minutes: 1));
        await tester.runAsync(sync.inspectCloud);
        expect(
          (await sync.loadSyncResult())!.succeededAt,
          firstResult.succeededAt,
        );
        final stopwatch = Stopwatch()..start();
        final conflict = await tester.runAsync(() async {
          try {
            await sync.uploadLocal(
              expectedRevision: initialRevision,
              expectedFingerprint: local.fingerprint,
            );
            return false;
          } on StateError catch (error) {
            return error.message.toString().contains('确认期间');
          }
        });
        expect(conflict, isTrue);
        expect(
          (await sync.loadSyncResult())!.succeededAt,
          firstResult.succeededAt,
        );
        expect((await sync.captureLocalState()).fingerprint, local.fingerprint);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 15)));
        expect(
          (await tester.runAsync(sync.inspectCloud))!.revision,
          first.revision,
        );
        transport.online = false;
        final failedOffline = await tester.runAsync(() async {
          try {
            await sync.uploadLocal(
              expectedRevision: first.revision,
              expectedFingerprint: local.fingerprint,
            );
            return false;
          } on SocketException {
            return true;
          }
        });
        expect(failedOffline, isTrue);
        expect(
          (await sync.loadSyncResult())!.succeededAt,
          firstResult.succeededAt,
        );
        expect((await sync.captureLocalState()).fingerprint, local.fingerprint);
        expect(
          (await tasks.getGoals()).single.title,
          'Retain through offline transport',
        );
        transport.online = true;
        final restoredCloud = await tester.runAsync(sync.inspectCloud);
        expect(restoredCloud!.revision, first.revision);
        await tester.runAsync(
          () => sync.uploadLocal(
            expectedRevision: restoredCloud.revision,
            expectedFingerprint: local.fingerprint,
          ),
        );
        expect(
          (await tasks.getGoals()).single.title,
          'Retain through offline transport',
        );
        final currentCloud = await tester.runAsync(sync.inspectCloud);
        final oldTables = Map<String, dynamic>.from(
          local.payload['tables'] as Map,
        );
        for (final table in const ['local_goals', 'local_tasks']) {
          oldTables[table] = [
            for (final rawRow in oldTables[table] as List)
              Map<String, dynamic>.from(rawRow as Map)..remove('description'),
          ];
        }
        final oldCloud = await tester.runAsync(
          () => remote.upload(
            userId: userId,
            expectedRevision: currentCloud!.revision,
            payload: <String, dynamic>{...local.payload, 'tables': oldTables},
            deviceId: 'old-version-1-probe',
            deviceName: 'Old version 1 probe',
            dataUpdatedAt: local.dataUpdatedAt,
            rowCount: local.rowCount,
          ),
        );
        final beforeLegacyDownload = await sync.captureLocalState();
        await tester.runAsync(
          () => sync.downloadCloud(
            expectedRevision: oldCloud!.revision,
            expectedFingerprint: beforeLegacyDownload.fingerprint,
          ),
        );
        final legacyRestored = (await tasks.getGoals()).single;
        expect(legacyRestored.title, 'Retain through offline transport');
        expect(legacyRestored.description, isEmpty);
        expect(legacyRestored.tasks.single.title, 'Keep linked task data');
        expect(legacyRestored.tasks.single.description, isEmpty);

        final malformedCloud = await tester.runAsync(
          () => remote.upload(
            userId: userId,
            expectedRevision: oldCloud!.revision,
            payload: {
              'schemaVersion': 1,
              'userId': userId,
              'tables': <String, dynamic>{},
            },
            deviceId: 'malformed-download-probe',
            deviceName: 'Malformed download probe',
            dataUpdatedAt: local.dataUpdatedAt,
            rowCount: 0,
          ),
        );
        final beforeMalformedDownload = await sync.captureLocalState();
        final beforeMalformedResult = (await sync.loadSyncResult())!;
        syncClock = syncClock.add(const Duration(minutes: 1));
        final rejectedMalformedDownload = await tester.runAsync(() async {
          try {
            await sync.downloadCloud(
              expectedRevision: malformedCloud!.revision,
              expectedFingerprint: beforeMalformedDownload.fingerprint,
            );
            return false;
          } on StateError {
            return true;
          }
        });
        expect(rejectedMalformedDownload, isTrue);
        expect(
          (await sync.captureLocalState()).fingerprint,
          beforeMalformedDownload.fingerprint,
        );
        expect(
          (await sync.loadSyncResult())!.succeededAt,
          beforeMalformedResult.succeededAt,
        );
        expect(
          (await tasks.getGoals()).single.title,
          'Retain through offline transport',
        );
        await tasks.dispose();
        debugPrint('REAL_HTTP409_AND_OFFLINE_RECOVERY_PASSED');
      } finally {
        await client.dispose();
        transport.close();
        await database.close();
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(
          'pacta.device.cloud_sync.result.${config['userId']}',
        );
      }
    },
    skip: _phase != 'windows-conflict',
  );
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(text).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Expected cloud UI state did not arrive: $text');
}

class _ObservedCloudRemote extends SupabaseCloudSnapshotRemote {
  _ObservedCloudRemote(super.client);
  int inspections = 0;
  int uploads = 0;
  int downloads = 0;
  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) {
    inspections++;
    return super.inspect(userId: userId);
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    downloads++;
    return super.download(userId: userId);
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  }) {
    uploads++;
    return super.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt,
      rowCount: rowCount,
    );
  }
}

class _OfflineProbeHttpClient extends http.BaseClient {
  _OfflineProbeHttpClient(this.delegate);
  final http.Client delegate;
  bool online = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!online) {
      throw const SocketException('Isolated acceptance transport is offline.');
    }
    return delegate.send(request);
  }

  @override
  void close() => delegate.close();
}
