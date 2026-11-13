import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

class _FakeProfileRemote implements ProfileRemote {
  RemoteProfile? stored;

  @override
  bool get isAvailable => true;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async => stored;

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  }) async {
    stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
    );
    return stored!;
  }
}

Future<void> _addGoal(
  PactaDatabase database, {
  required String userId,
  required String id,
}) => database
    .into(database.localGoals)
    .insert(
      LocalGoalsCompanion.insert(
        userId: userId,
        id: id,
        title: '目标 $id',
        classification: 'regular',
        createdAt: DateTime.utc(2026, 11, 1),
        updatedAt: DateTime.utc(2026, 11, 1),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('业务快照恢复不回滚账号资料', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'user-a';
    final profile = LocalProfileRepository(
      database: database,
      userId: userId,
      remote: _FakeProfileRemote(),
      now: () => DateTime.utc(2026, 11, 13, 9),
    );
    await profile.saveProfile(
      displayName: '小林',
      avatar: ProfileAvatar(
        bytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
        mimeType: AvatarImageFormat.png.mimeType,
      ),
    );

    final snapshot = CloudSnapshotRepository(
      database: database,
      remote: InMemoryCloudSnapshotRemote(),
      userId: userId,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      now: () => DateTime.utc(2026, 11, 13, 10),
    );
    await _addGoal(database, userId: userId, id: 'goal-a');
    final uploaded = await snapshot.captureLocalState();
    await snapshot.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: uploaded.fingerprint,
    );

    await _addGoal(database, userId: userId, id: 'goal-b');
    final beforeRestore = await snapshot.captureLocalState();
    final cloud = await snapshot.inspectCloud();
    await snapshot.downloadCloud(
      expectedRevision: cloud!.revision,
      expectedFingerprint: beforeRestore.fingerprint,
    );

    final restored = await profile.getProfile();
    expect(restored.displayName, '小林');
    expect(restored.avatar?.mimeType, AvatarImageFormat.png.mimeType);
    expect(drift.Value(restored.userId).value, userId);
    expect(
      (await snapshot.captureLocalState()).payload['tables'],
      isNot(contains('local_profile_accounts')),
    );
  });

  test('账号清除回执删除本机资料缓存与头像二进制', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'user-a';
    final profile = LocalProfileRepository(
      database: database,
      userId: userId,
      remote: _FakeProfileRemote(),
    );
    await profile.saveProfile(
      displayName: '小林',
      avatar: ProfileAvatar(
        bytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
        mimeType: AvatarImageFormat.png.mimeType,
      ),
    );
    expect(await database.localUserIdsWithData(), contains(userId));

    final cleaned = await database.purgeUserDataForReceipt(
      userId: userId,
      receipt: UserPurgeReceipt(
        userId: userId,
        status: UserPurgeStatus.completed,
        purgedAt: DateTime.utc(2026, 11, 13),
      ),
    );
    expect(cleaned, isTrue);
    expect((await profile.getProfile()).displayName, isEmpty);
    expect(await database.localUserIdsWithData(), isNot(contains(userId)));
  });
}
