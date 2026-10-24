import 'dart:async';

import 'package:drift/native.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });
  testWidgets(
    'cold start discovers cloud without transferring business data and foreground waits five minutes',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      var now = DateTime.utc(2026, 10, 24);
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'reader',
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
      );
      await tasks.createGoal(
        const GoalDraft(
          title: 'Untouched local business',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.dispose();
      final before = await repository.captureLocalState();
      await tester.pumpWidget(
        _app(database, auth, repository, cloudCheckClock: () => now),
      );
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('云端有待处理更新'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      now = now.add(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remote.inspections, 2);
      expect(remote.transfers, 0);
      expect(
        (await repository.captureLocalState()).fingerprint,
        before.fingerprint,
      );
      auth.lifecycleStatus = UserLifecycleStatus(
        isSuspended: true,
        checkedAt: now,
      );
      now = now.add(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('此用户已停用'), findsOneWidget);
      expect(remote.inspections, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );
  testWidgets(
    'offline discovery is silent and the card retries without transfer',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote()..fail = true;
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('云端检查失败，点击重试'), findsOneWidget);
      remote.fail = false;
      await tester.tap(find.text('云端检查失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.text('云端有待处理更新'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets('failed check retry respects newly suspended access', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()..signedInUser = 'reader';
    final remote = _Remote()..fail = true;
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'reader',
      deviceName: 'test',
    );
    await tester.pumpWidget(_app(database, auth, repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    auth.lifecycleStatus = UserLifecycleStatus(
      isSuspended: true,
      checkedAt: DateTime.utc(2026),
    );
    remote.fail = false;
    await tester.tap(find.text('云端检查失败，点击重试'));
    await tester.pumpAndSettle();
    expect(remote.inspections, 1);
    expect(find.text('云端有待处理更新'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
  });
  for (final legacy in [false, true]) {
    testWidgets(
      'handled ${legacy ? 'legacy token' : 'revision'} stays quiet until version changes',
      (tester) async {
        final database = PactaDatabase(NativeDatabase.memory());
        final auth = FakeAuthRepository()..signedInUser = 'reader';
        final remote = _Remote()..legacy = legacy;
        var now = DateTime.utc(2026, 10, 24);
        final repository = CloudSnapshotRepository(
          database: database,
          remote: remote,
          userId: 'reader',
          deviceName: 'test',
        );
        await repository.syncResultStore.save(
          'reader',
          CloudSyncResult(
            succeededAt: DateTime.utc(2026),
            localFingerprint: null,
            cloudRevision: 2,
            legacyToken: legacy ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' : null,
          ),
        );
        await tester.pumpWidget(
          _app(database, auth, repository, cloudCheckClock: () => now),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        expect(find.text('云端有待处理更新'), findsNothing);
        remote.revision = 3;
        remote.token = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        now = now.add(const Duration(minutes: 5));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('云端有待处理更新'), findsOneWidget);
        expect(remote.transfers, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await database.close();
      },
    );
  }

  testWidgets(
    'direct user switch discards a late result even with the same identifier',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = _Auth()..signedInUser = 'reader';
      final remote = _Remote()..gate = Completer<void>();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      auth.signedInUser = 'other-reader';
      remote.empty = true;
      auth.changes.add('same-email@example.test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      remote.gate!.complete();
      await tester.pumpAndSettle();
      expect(remote.users, ['reader', 'other-reader']);
      expect(find.text('云端有待处理更新'), findsNothing);
      expect(find.text('尚未同步'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await auth.changes.close();
      await database.close();
    },
  );
  testWidgets(
    'unknown lifecycle status never reads cloud and its failed card can retry',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()
        ..signedInUser = 'reader'
        ..lifecycleStatusError = StateError('offline');
      final remote = _Remote()..empty = true;
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(remote.inspections, 0);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('云端检查失败，点击重试'), findsOneWidget);
      auth.lifecycleStatusError = null;
      await tester.tap(find.text('云端检查失败，点击重试'));
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      expect(find.text('尚未同步'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets(
    'own upload handles the version while an older automatic result arrives late',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _RaceRemote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      final local = await repository.captureLocalState();
      await remote.upload(
        userId: 'reader',
        expectedRevision: 0,
        payload: local.payload,
        deviceId: 'other',
        deviceName: 'Other',
        dataUpdatedAt: DateTime.utc(2020),
        rowCount: 0,
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认上传'));
      await tester.pumpAndSettle();
      expect((await repository.loadSyncResult())!.cloudRevision, 2);
      remote.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('云端有待处理更新'), findsNothing);
      expect(find.text('正在检查云端…'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );
}

class _Remote implements CloudSnapshotRemote {
  final users = <String>[];
  Completer<void>? gate;
  bool empty = false;
  bool fail = false;
  bool legacy = false;
  int revision = 2;
  String token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  int inspections = 0;
  int transfers = 0;
  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    inspections++;
    users.add(userId);
    if (empty) return null;
    await gate?.future;
    if (fail) throw StateError('offline');
    return CloudSnapshotMetadata(
      revision: revision,
      isLegacy: legacy,
      legacyToken: legacy ? token : null,
      deviceId: 'other',
      deviceName: 'Other device',
      dataUpdatedAt: DateTime.utc(2020),
      uploadedAt: DateTime.utc(2020),
      rowCount: 0,
    );
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    transfers++;
    throw StateError('Unexpected download');
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
    String? deviceManufacturer,
    String? deviceModel,
  }) async {
    transfers++;
    throw StateError('Unexpected upload');
  }
}

PactaApp _app(
  PactaDatabase database,
  FakeAuthRepository auth,
  CloudSnapshotRepository repository, {
  DateTime Function() cloudCheckClock = DateTime.now,
}) => PactaApp(
  authRepository: auth,
  cloudCheckClock: cloudCheckClock,
  taskRepositoryFactory: (id) => LocalTaskRepository(
    database: database,
    userId: id,
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  ),
  focusRepositoryFactory: (id) => LocalFocusRepository(
    database: database,
    userId: id,
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
  ),
  nationalFocusRepositoryFactory: (id) => LocalNationalFocusRepository(
    database: database,
    userId: id,
    cloudSyncEnabled: false,
  ),
  calendarRepositoryFactory: (id) => LocalCalendarRepository(
    database: database,
    userId: id,
    provider: const UnsupportedCalendarProvider(),
    remote: InMemoryCalendarRemote(),
    cloudSyncEnabled: false,
  ),
  userLifecycleRepositoryFactory: (id) => UserLifecycleRepository(
    authRepository: auth,
    localAccess: LocalUserLifecycleAccess(database: database, userId: id),
  ),
  cloudSnapshotRepositoryFactory: (id) => id == repository.userId
      ? repository
      : CloudSnapshotRepository(
          database: database,
          remote: repository.remote,
          userId: id,
          deviceName: 'test',
        ),
);

class _Auth extends FakeAuthRepository {
  final changes = StreamController<String?>.broadcast();
  @override
  Stream<String?> get authState => changes.stream;
  @override
  String? get currentUserIdentifier => 'same-email@example.test';
}

class _RaceRemote extends InMemoryCloudSnapshotRemote {
  final gate = Completer<void>();
  bool firstInspection = true;
  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    final snapshot = await super.inspect(userId: userId);
    if (firstInspection) {
      firstInspection = false;
      await gate.future;
    }
    return snapshot;
  }
}
