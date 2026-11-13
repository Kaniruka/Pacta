import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

class _FakeProfileRemote implements ProfileRemote {
  _FakeProfileRemote();

  RemoteProfile? stored;
  Object? fetchError;
  Object? saveError;
  int saveCalls = 0;
  bool available = true;

  @override
  bool get isAvailable => available;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async {
    if (fetchError != null) throw fetchError!;
    return stored;
  }

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  }) async {
    saveCalls++;
    if (saveError != null) throw saveError!;
    stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
    );
    return stored!;
  }
}

ProfileAvatar _avatar() => ProfileAvatar(
  bytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
  mimeType: 'image/png',
);

void main() {
  late PactaDatabase database;
  late _FakeProfileRemote remote;
  var clock = DateTime.utc(2026, 11, 13, 9);

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    remote = _FakeProfileRemote();
    clock = DateTime.utc(2026, 11, 13, 9);
  });

  tearDown(() => database.close());

  LocalProfileRepository buildRepository({String userId = 'user-a'}) =>
      LocalProfileRepository(
        database: database,
        userId: userId,
        remote: remote,
        now: () => clock,
      );

  test('空资料返回占位昵称而不是编造账号名', () async {
    final repository = buildRepository();
    final profile = await repository.getProfile();
    expect(profile.displayName, isEmpty);
    expect(profile.avatar, isNull);
    expect(profile.effectiveDisplayName, '当前用户');
  });

  test('保存后本机缓存立即可见，离线重新打开仍可见', () async {
    remote.available = false;
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林', avatar: _avatar());
    clock = clock.add(const Duration(minutes: 1));

    final reopened = buildRepository();
    final profile = await reopened.getProfile();
    expect(profile.displayName, '小林');
    expect(profile.avatar?.mimeType, 'image/png');
    expect(profile.hasPendingSave, isFalse);
    expect(profile.syncError, isNull);
  });

  test('账号资料写入失败保留本机内容并允许重试', () async {
    remote.saveError = StateError('网络不可用');
    final repository = buildRepository();
    final saved = await repository.saveProfile(displayName: '小林');
    expect(saved.displayName, '小林');
    expect(saved.hasPendingSave, isTrue);
    expect(saved.syncError, contains('保存失败'));

    remote.saveError = null;
    final retried = await repository.syncProfile();
    expect(retried.hasPendingSave, isFalse);
    expect(retried.syncError, isNull);
    expect(remote.stored?.displayName, '小林');
  });

  test('其他设备保存的更晚资料在本机同步后采用', () async {
    final repository = buildRepository();
    await repository.saveProfile(displayName: '本机旧名');
    remote.stored = RemoteProfile(
      displayName: '另一台设备',
      avatar: _avatar(),
      updatedAt: clock.add(const Duration(hours: 1)),
    );

    final synced = await repository.syncProfile();
    expect(synced.displayName, '另一台设备');
    expect(synced.avatar, isNotNull);
    expect(synced.hasPendingSave, isFalse);
  });

  test('本机更晚的修改会覆盖云端，较早的云端不回滚昵称', () async {
    remote.stored = RemoteProfile(
      displayName: '云端旧名',
      avatar: null,
      updatedAt: clock.subtract(const Duration(hours: 2)),
    );
    final repository = buildRepository();
    await repository.saveProfile(displayName: '本机新名');

    final synced = await repository.syncProfile();
    expect(synced.displayName, '本机新名');
    expect(remote.stored?.displayName, '本机新名');
  });

  test('资料按用户隔离，不读取其他用户的缓存', () async {
    final userA = buildRepository();
    await userA.saveProfile(displayName: '小林');
    final userB = buildRepository(userId: 'user-b');
    final profile = await userB.getProfile();
    expect(profile.displayName, isEmpty);
    expect(profile.userId, 'user-b');
  });

  test('云端读取失败保留缓存并给出可重试状态', () async {
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林');
    remote.fetchError = StateError('云端不可用');
    remote.stored = null;

    final profile = await repository.syncProfile();
    expect(profile.displayName, '小林');
    expect(profile.syncError, isNotNull);
  });

  test('移除头像保存后云端与缓存都不再保留二进制', () async {
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林', avatar: _avatar());
    final cleared = await repository.saveProfile(
      displayName: '小林',
      clearAvatar: true,
    );
    expect(cleared.avatar, isNull);
    expect(remote.stored?.avatar, isNull);
  });
}
