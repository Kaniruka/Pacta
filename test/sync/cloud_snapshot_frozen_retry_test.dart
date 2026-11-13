import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'frozen-retry-user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late CloudSnapshotRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedGoal(String title) async {
    final tasks = LocalTaskRepository(
      database: database,
      userId: _userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    await tasks.createGoal(
      GoalDraft(title: title, classification: TaskClassification.regular),
    );
    await tasks.dispose();
  }

  test('载荷指纹与捕获状态同口径，可用于校验持久化的请求载荷', () async {
    await seedGoal('Only goal');
    final state = await repository.captureLocalState();
    expect(repository.fingerprintOfPayload(state.payload), state.fingerprint);
    expect(
      repository.fingerprintOfPayload(const {'tables': 'not-a-map'}),
      isNot(state.fingerprint),
    );
  });

  test('重试已发出的请求重发当时捕获的载荷，同身份只落一份历史', () async {
    await seedGoal('First goal');
    final captured = await repository.captureLocalState();
    await seedGoal('Confirmed while offline');

    final saved = await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: captured.fingerprint,
      requestId: 'request-1',
      captured: captured,
    );
    expect(saved.revision, 1);
    expect(
      (await repository.loadSyncResult())!.localFingerprint,
      captured.fingerprint,
    );
    final payload = (await remote.download(userId: _userId)).payload!;
    expect(payload['tables']['local_goals'], hasLength(1));

    final retried = await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: captured.fingerprint,
      requestId: 'request-1',
      captured: captured,
    );
    expect(retried.revision, 1);
    expect((await remote.history(userId: _userId)), hasLength(1));
  });

  test('同一请求身份换了载荷会被拒绝，且不写入新版本', () async {
    await seedGoal('First goal');
    final captured = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: captured.fingerprint,
      requestId: 'request-1',
      captured: captured,
    );
    await seedGoal('Changed after the request');
    final current = await repository.captureLocalState();

    await expectLater(
      repository.uploadLocal(
        expectedRevision: 1,
        expectedFingerprint: current.fingerprint,
        requestId: 'request-1',
        captured: current,
      ),
      throwsA(isA<CloudUploadRequestConflict>()),
    );
    expect((await remote.history(userId: _userId)), hasLength(1));
    expect(
      (await repository.loadSyncResult())!.localFingerprint,
      captured.fingerprint,
    );
  });

  test('提供的快照指纹与期望不一致时仍然拒绝上传', () async {
    await seedGoal('First goal');
    final captured = await repository.captureLocalState();
    await expectLater(
      repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: 'v2:0000000000000000',
        requestId: 'request-1',
        captured: captured,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await remote.inspect(userId: _userId), isNull);
  });
}
