import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

class _FakeProfileRemote implements ProfileRemote {
  _FakeProfileRemote();

  RemoteProfile? stored;
  Object? fetchError;
  Object? saveError;
  Completer<RemoteProfile?>? fetchGate;
  Completer<void>? saveGate;
  int saveCalls = 0;
  int fetchCalls = 0;
  bool available = true;

  @override
  bool get isAvailable => available;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async {
    fetchCalls++;
    final gate = fetchGate;
    if (gate != null) return gate.future;
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
    final gate = saveGate;
    if (gate != null) await gate.future;
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

  LocalProfileRepository buildRepository({
    String userId = 'user-a',
    ProfileRemote? withRemote,
  }) => LocalProfileRepository(
    database: database,
    userId: userId,
    remote: withRemote ?? remote,
    now: () => clock,
  );

  Future<void> purgeUser(String userId) => database.purgeUserDataForReceipt(
    userId: userId,
    receipt: UserPurgeReceipt(
      userId: userId,
      status: UserPurgeStatus.completed,
      purgedAt: clock,
    ),
  );

  Future<List<LocalProfileAccount>> profileRows(String userId) =>
      (database.select(
        database.localProfileAccounts,
      )..where((row) => row.userId.equals(userId))).get();

  test('空资料返回占位昵称而不是编造账号名', () async {
    final repository = buildRepository();
    final profile = await repository.getProfile();
    expect(profile.displayName, isEmpty);
    expect(profile.avatar, isNull);
    expect(profile.effectiveDisplayName, '当前用户');
  });

  test('保存后本机缓存立即可见，离线重新打开仍可见且等待重试', () async {
    remote.available = false;
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林', avatar: _avatar());
    clock = clock.add(const Duration(minutes: 1));

    final reopened = buildRepository();
    final profile = await reopened.getProfile();
    expect(profile.displayName, '小林');
    expect(profile.avatar?.mimeType, 'image/png');
    // 远端不可用时的真实编辑保留待上传意图，云可用后再上传。
    expect(profile.hasPendingSave, isTrue);
    expect(profile.syncError, isNull);
  });

  test('离线编辑在云端可用后由同步上传，而不是丢弃', () async {
    remote.available = false;
    final offline = buildRepository();
    await offline.saveProfile(displayName: '离线昵称');

    remote.available = true;
    final online = buildRepository();
    final synced = await online.syncProfile();
    expect(synced.hasPendingSave, isFalse);
    expect(remote.stored?.displayName, '离线昵称');
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

  test('首次读取失败不写本机版本，重试后采用云端既有资料且不上传', () async {
    final repository = buildRepository();
    remote.fetchError = StateError('云端不可用');

    final failed = await repository.syncProfile();
    expect(failed.syncError, isNotNull);
    expect(failed.displayName, isEmpty);
    expect(failed.updatedAt, isNull, reason: '读取失败不能制造本机版本');
    expect(remote.saveCalls, 0);

    remote.fetchError = null;
    remote.stored = RemoteProfile(
      displayName: '云端已有',
      avatar: _avatar(),
      updatedAt: clock.subtract(const Duration(days: 1)),
    );
    final synced = await repository.syncProfile();
    expect(synced.displayName, '云端已有');
    expect(synced.avatar?.mimeType, 'image/png');
    expect(remote.saveCalls, 0, reason: '没有本地编辑意图时不得上传');
    expect(remote.stored?.displayName, '云端已有');
  });

  test('读取失败不推进已有缓存的版本时间', () async {
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林');
    final before = await repository.getProfile();
    clock = clock.add(const Duration(hours: 3));

    remote.fetchError = StateError('云端不可用');
    final after = await repository.syncProfile();
    expect(after.displayName, '小林');
    expect(after.updatedAt, before.updatedAt);
    expect(after.syncError, isNotNull);
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

  test('后台读取等待时用户保存会排队，旧云端资料不会回滚新编辑', () async {
    final repository = buildRepository();
    remote.stored = RemoteProfile(
      displayName: '云端旧名',
      avatar: null,
      updatedAt: clock.subtract(const Duration(hours: 2)),
    );
    final gate = Completer<RemoteProfile?>();
    remote.fetchGate = gate;

    final syncing = repository.syncProfile();
    await Future<void>.delayed(Duration.zero);
    final saving = repository.saveProfile(displayName: '用户新编辑');
    await Future<void>.delayed(Duration.zero);

    gate.complete(
      RemoteProfile(
        displayName: '云端旧名',
        avatar: null,
        updatedAt: clock.subtract(const Duration(hours: 2)),
      ),
    );
    await syncing;
    await saving;

    final profile = await repository.getProfile();
    expect(profile.displayName, '用户新编辑');
    expect(profile.hasPendingSave, isFalse);
    expect(remote.stored?.displayName, '用户新编辑');
  });

  test('另一入口的新编辑不被晚到的较新云端资料覆盖', () async {
    final background = buildRepository();
    final localOnly = buildRepository(
      withRemote: const UnavailableProfileRemote(),
    );
    final gate = Completer<RemoteProfile?>();
    remote.fetchGate = gate;

    final syncing = background.syncProfile();
    await Future<void>.delayed(Duration.zero);
    await localOnly.saveProfile(displayName: '本机待上传');
    final pending = await localOnly.getProfile();
    expect(pending.hasPendingSave, isTrue);

    gate.complete(
      RemoteProfile(
        displayName: '另一设备较新',
        avatar: _avatar(),
        updatedAt: clock.add(const Duration(hours: 1)),
      ),
    );
    await syncing;

    final after = await background.getProfile();
    expect(after.displayName, '本机待上传', reason: '较新的待上传编辑优先保留');
    expect(after.hasPendingSave, isTrue);
    expect(after.avatar, isNull);
  });

  test('账号清除后晚到的首次读取不得复活昵称与头像', () async {
    final repository = buildRepository();
    final gate = Completer<RemoteProfile?>();
    remote.fetchGate = gate;

    final syncing = repository.syncProfile();
    await Future<void>.delayed(Duration.zero);
    expect(remote.fetchCalls, 1);

    // 读取已在途中时账号被清除：本机资料行删除，清除代次前进。
    await purgeUser('user-a');

    gate.complete(
      RemoteProfile(
        displayName: '已清除用户',
        avatar: _avatar(),
        updatedAt: clock.add(const Duration(minutes: 1)),
      ),
    );
    await syncing;

    expect(await profileRows('user-a'), isEmpty, reason: '晚到读取不得重新插入资料行');
    final after = await repository.getProfile();
    expect(after.hasDisplayName, isFalse);
    expect(after.avatar, isNull);
  });

  test('账号清除后晚到的上传成功应答不再写回资料', () async {
    remote.available = false;
    final repository = buildRepository();
    await repository.saveProfile(displayName: '待上传昵称');
    expect((await repository.getProfile()).hasPendingSave, isTrue);

    remote.available = true;
    final gate = Completer<void>();
    remote.saveGate = gate;
    final syncing = repository.syncProfile();
    await Future<void>.delayed(Duration.zero);
    expect(remote.saveCalls, 1);

    await purgeUser('user-a');
    gate.complete();
    await syncing;

    expect(await profileRows('user-a'), isEmpty, reason: '清除后应答不得写回昵称');
  });

  test('dispose 之后晚到的读取结果不再写入', () async {
    final repository = buildRepository();
    final gate = Completer<RemoteProfile?>();
    remote.fetchGate = gate;

    final syncing = repository.syncProfile();
    await Future<void>.delayed(Duration.zero);
    await repository.dispose();

    gate.complete(
      RemoteProfile(displayName: '已失效', avatar: null, updatedAt: clock),
    );
    await syncing;

    expect(await profileRows('user-a'), isEmpty);
  });

  test('账号清除后已排队的旧保存不再写入', () async {
    final repository = buildRepository();
    final gate = Completer<RemoteProfile?>();
    remote.fetchGate = gate;

    // 读取先占住串行队列，随后的编辑只能排队等待。
    final syncing = repository.syncProfile();
    await Future<void>.delayed(Duration.zero);
    final saving = repository.saveProfile(
      displayName: '旧昵称',
      avatar: _avatar(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(remote.saveCalls, 0, reason: '排队期间不得开始上传');

    await purgeUser('user-a');
    gate.complete(null);
    await syncing;
    await saving;

    expect(await profileRows('user-a'), isEmpty, reason: '排队的旧编辑不得复活资料');
    final after = await repository.getProfile();
    expect(after.hasDisplayName, isFalse);
    expect(after.avatar, isNull);
    expect(remote.saveCalls, 0, reason: '已清除账号不再上传');
  });

  test('已清除账号的旧 UUID 不再接受资料写入（重新注册使用新 UUID）', () async {
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林');
    await purgeUser('user-a');
    expect(await profileRows('user-a'), isEmpty);

    // 依据 supabase/README.md 的 Explicit cloud purge：清除后重新注册会得到
    // 新的 auth UUID，因此旧 UUID 上的任何资料写入都只可能是失效的旧操作。
    final stale = buildRepository();
    final saved = await stale.saveProfile(displayName: '失效写入');
    expect(saved.hasDisplayName, isFalse);
    expect(await profileRows('user-a'), isEmpty);
    expect(remote.saveCalls, 1, reason: '只有清除前那次成功写入');
  });

  test('晚到的上传失败不覆盖另一入口的新编辑', () async {
    final uploading = buildRepository();
    final localOnly = buildRepository(
      withRemote: const UnavailableProfileRemote(),
    );
    final gate = Completer<void>();
    remote.saveGate = gate;

    final saving = uploading.saveProfile(displayName: '旧编辑');
    await Future<void>.delayed(Duration.zero);
    await localOnly.saveProfile(displayName: '新编辑');

    gate.completeError(StateError('网络中断'));
    await saving;

    final after = await uploading.getProfile();
    expect(after.displayName, '新编辑');
    expect(after.hasPendingSave, isTrue);
    expect(after.syncError, isNull, reason: '旧请求的失败不得写给新编辑');
  });
}
