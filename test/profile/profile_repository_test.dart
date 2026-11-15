import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/profile/account_time_zone.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

class _FakeProfileRemote implements ProfileRemote {
  _FakeProfileRemote();

  RemoteProfile? stored;
  Object? fetchError;
  Object? saveError;
  Object? initializeError;
  Completer<RemoteProfile?>? fetchGate;
  Completer<void>? saveGate;
  Completer<RemoteProfile?>? initializeGate;
  int saveCalls = 0;
  int fetchCalls = 0;
  int initializeCalls = 0;
  bool available = true;

  /// Time zone values carried by ordinary saves, newest last. A null entry is a
  /// nickname/avatar save that keeps the stored time zone.
  final List<String?> timeZoneWrites = [];

  /// Time zone values attempted through the atomic initialize-if-null step.
  final List<String> initializeWrites = [];

  /// When the stored time zone was last accepted, mirroring the account store's
  /// per-field ordering guard.
  DateTime? storedTimeZoneRequestedAt;

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
    String? displayTimeZoneId,
  }) async {
    saveCalls++;
    timeZoneWrites.add(displayTimeZoneId);
    // 单次闸门：只让这一条请求停在途中，其它入口的保存照常完成。
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
    if (saveError != null) throw saveError!;
    // Null keeps the stored value; a delayed older preference never replaces a
    // newer accepted one, like the account-store RPC.
    final acceptedZone = storedTimeZoneRequestedAt;
    final appliesTimeZone =
        displayTimeZoneId != null &&
        (acceptedZone == null || !updatedAt.isBefore(acceptedZone));
    stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
      displayTimeZoneId: appliesTimeZone
          ? displayTimeZoneId
          : stored?.displayTimeZoneId,
    );
    if (appliesTimeZone) storedTimeZoneRequestedAt = updatedAt;
    return stored!;
  }

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
    required DateTime requestedAt,
  }) async {
    initializeCalls++;
    initializeWrites.add(displayTimeZoneId);
    final gate = initializeGate;
    if (gate != null) return gate.future;
    if (initializeError != null) throw initializeError!;
    final existing = stored;
    if (existing == null) {
      stored = RemoteProfile(
        displayName: '',
        avatar: null,
        updatedAt: requestedAt,
        displayTimeZoneId: displayTimeZoneId,
      );
      storedTimeZoneRequestedAt = requestedAt;
      return stored;
    }
    // Atomic initialize-if-null: an existing account value is never replaced.
    if (existing.displayTimeZoneId == null) {
      stored = RemoteProfile(
        displayName: existing.displayName,
        avatar: existing.avatar,
        updatedAt: requestedAt,
        displayTimeZoneId: displayTimeZoneId,
      );
      storedTimeZoneRequestedAt = requestedAt;
    }
    return stored;
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

  test('账号资料保存并读回账号级时区，另一台设备读到同一值', () async {
    final repository = buildRepository();
    final saved = await repository.saveProfile(
      displayName: '小林',
      timeZoneId: 'Asia/Tokyo',
    );
    expect(saved.displayTimeZoneId, 'Asia/Tokyo');
    expect(saved.hasPendingSave, isFalse);
    expect(remote.stored?.displayTimeZoneId, 'Asia/Tokyo');

    // 另一台设备用自己的缓存读同一账号值。
    final otherDevice = buildRepository();
    expect((await otherDevice.getProfile()).displayTimeZoneId, 'Asia/Tokyo');
  });

  test('已有账号值优先，设备时区不再覆盖它', () async {
    final repository = buildRepository();
    await repository.saveProfile(
      displayName: '小林',
      timeZoneId: 'Europe/London',
    );
    final savesAfterChoice = remote.saveCalls;
    final before = await repository.getProfile();

    final migrated = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'America/Los_Angeles',
    );
    expect(migrated.displayTimeZoneId, 'Europe/London');
    expect(remote.saveCalls, savesAfterChoice);
    expect(remote.initializeCalls, 0, reason: '已有账号值时不得再初始化');
    expect(migrated.editSequence, before.editSequence, reason: '幂等：不产生新版本');
  });

  test('云端已有账号值时本机采用它，而不是写入设备时区', () async {
    remote.stored = RemoteProfile(
      displayName: '另一台设备',
      avatar: null,
      updatedAt: clock,
      displayTimeZoneId: 'Asia/Singapore',
    );
    final repository = buildRepository();

    final migrated = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Shanghai',
    );
    expect(migrated.displayTimeZoneId, 'Asia/Singapore');
    expect(migrated.displayName, '另一台设备');
    expect(remote.initializeCalls, 0);
    expect(remote.saveCalls, 0);
  });

  test('首次迁移写入旧设备级值一次，重复调用幂等', () async {
    // 旧数据：被取代的设备级字段仍在；本机运行在另一台设备的时区。
    await database
        .into(database.focusPreferences)
        .insert(
          FocusPreferencesCompanion.insert(
            userId: 'user-a',
            lastMode: 'regular',
            displayTimeZoneId: const Value('Asia/Shanghai'),
          ),
        );
    final repository = buildRepository();

    final first = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'America/Los_Angeles',
    );
    expect(first.displayTimeZoneId, 'Asia/Shanghai');
    expect(remote.stored?.displayTimeZoneId, 'Asia/Shanghai');
    final sequence = first.editSequence;
    final initializeCalls = remote.initializeCalls;

    final second = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'America/New_York',
    );
    expect(second.displayTimeZoneId, 'Asia/Shanghai');
    expect(second.editSequence, sequence);
    expect(remote.initializeCalls, initializeCalls);
  });

  test('两台设备并发首次迁移只有一个账号值赢家', () async {
    final deviceA = buildRepository();
    final deviceB = buildRepository();
    // 两台设备都先读到"账号还没有时区"。
    final staleAnswer = Completer<RemoteProfile?>();
    remote.fetchGate = staleAnswer;
    final migratingA = deviceA.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Shanghai',
    );
    final migratingB = deviceB.ensureDisplayTimeZone(
      deviceTimeZoneId: 'America/Los_Angeles',
    );
    await Future<void>.delayed(Duration.zero);
    staleAnswer.complete(
      RemoteProfile(displayName: '', avatar: null, updatedAt: clock),
    );
    remote.fetchGate = null;
    await migratingA;
    await migratingB;

    // 账号存储原子决定唯一值，另一台设备采用它，而不是各自本地胜出。
    final accountValue = remote.stored?.displayTimeZoneId;
    expect(accountValue, isNotNull);
    expect((await deviceA.getProfile()).displayTimeZoneId, accountValue);
    expect((await deviceB.getProfile()).displayTimeZoneId, accountValue);
  });

  test('账号存储读不到时保持缓存，显示用统一 fallback 而不是设备时区', () async {
    remote.fetchError = StateError('网络不可用');
    final repository = buildRepository();

    final migrated = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'America/Los_Angeles',
    );
    expect(migrated.displayTimeZoneId, isNull);
    expect(
      AccountTimeZones.effectiveId(migrated.displayTimeZoneId),
      AccountTimeZones.fallbackId,
    );
    expect(remote.timeZoneWrites, isEmpty, reason: '读不到账号值时不写设备种子');
  });

  test('未配置账号存储时迁移值就是本机账号值，不排入上传', () async {
    remote.available = false;
    final repository = buildRepository();

    final migrated = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Shanghai',
    );
    expect(migrated.displayTimeZoneId, 'Asia/Shanghai');
    expect(migrated.hasPendingSave, isFalse, reason: '没有账号存储时不存在可上传对象');
  });

  test('未知时区不被写入，也不会成为显示值', () async {
    final repository = buildRepository();
    await expectLater(
      repository.saveProfile(displayName: '小林', timeZoneId: 'Mars/Olympus'),
      throwsArgumentError,
    );

    final migrated = await repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Mars/Olympus',
    );
    expect(migrated.displayTimeZoneId, isNull);
    expect(
      AccountTimeZones.effectiveId(migrated.displayTimeZoneId),
      AccountTimeZones.fallbackId,
    );
    expect(remote.timeZoneWrites, isEmpty);
  });

  test('只改昵称或头像时不覆盖云端已存的账号时区', () async {
    remote.stored = RemoteProfile(
      displayName: '旧名',
      avatar: null,
      updatedAt: clock.subtract(const Duration(hours: 2)),
      displayTimeZoneId: 'Asia/Tokyo',
    );
    final repository = buildRepository();

    final adopted = await repository.syncProfile();
    expect(adopted.displayTimeZoneId, 'Asia/Tokyo');
    final renamed = await repository.saveProfile(displayName: '新名');
    expect(renamed.displayTimeZoneId, 'Asia/Tokyo');
    expect(remote.stored?.displayName, '新名');
    expect(remote.stored?.displayTimeZoneId, 'Asia/Tokyo');
  });

  test('初始化失败后另一台设备写入的值，在恢复后成为唯一账号值', () async {
    // 两台设备各有独立缓存，共用一个账号存储。
    final deviceADatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(deviceADatabase.close);
    final deviceBDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(deviceBDatabase.close);
    final deviceA = LocalProfileRepository(
      database: deviceADatabase,
      userId: 'user-a',
      remote: remote,
      now: () => clock,
    );
    final deviceB = LocalProfileRepository(
      database: deviceBDatabase,
      userId: 'user-a',
      remote: remote,
      now: () => clock,
    );

    // A 的原子初始化失败：不得把设备时区留成"账号值"。
    remote.initializeError = StateError('网络中断');
    final failed = await deviceA.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Tokyo',
    );
    expect(failed.displayTimeZoneId, isNull, reason: '未被账号存储接受的设备值不是账号值');
    expect(
      AccountTimeZones.effectiveId(failed.displayTimeZoneId),
      AccountTimeZones.fallbackId,
    );

    // B 随后原子初始化成功。
    remote.initializeError = null;
    final deviceBMigrated = await deviceB.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Europe/London',
    );
    expect(deviceBMigrated.displayTimeZoneId, 'Europe/London');

    // A 恢复后再迁移：读到 B 的账号值，采用它，而不是自己的设备值。
    final recovered = await deviceA.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Tokyo',
    );
    expect(recovered.displayTimeZoneId, 'Europe/London');
    expect(remote.stored?.displayTimeZoneId, 'Europe/London');
    expect(
      remote.timeZoneWrites,
      isNot(contains('Asia/Tokyo')),
      reason: '恢复后的普通保存不得把设备时区写成账号值',
    );
  });

  test('初始化失败且本机有待上传昵称时，恢复前的上传不推送设备时区', () async {
    final deviceADatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(deviceADatabase.close);
    final deviceBDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(deviceBDatabase.close);
    final deviceA = LocalProfileRepository(
      database: deviceADatabase,
      userId: 'user-a',
      remote: remote,
      now: () => clock,
    );
    final deviceB = LocalProfileRepository(
      database: deviceBDatabase,
      userId: 'user-a',
      remote: remote,
      now: () => clock,
    );

    // A 离线改过昵称：本机有待上传编辑，但没有账号时区。
    remote.available = false;
    await deviceA.saveProfile(displayName: '小林');
    expect((await deviceA.getProfile()).hasPendingSave, isTrue);
    remote.available = true;

    // A 的原子初始化失败后，本机待上传编辑不得携带设备时区。
    remote.initializeError = StateError('网络中断');
    final failed = await deviceA.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Tokyo',
    );
    expect(failed.displayTimeZoneId, isNull);
    expect(
      AccountTimeZones.effectiveId(failed.displayTimeZoneId),
      AccountTimeZones.fallbackId,
    );
    remote.initializeError = null;
    await deviceB.ensureDisplayTimeZone(deviceTimeZoneId: 'Europe/London');
    expect(remote.stored?.displayTimeZoneId, 'Europe/London');

    // 恢复前 A 同步自己的昵称：只能保留账号值，不能写成设备时区。
    final synced = await deviceA.syncProfile();
    expect(synced.displayName, '小林');
    expect(remote.stored?.displayTimeZoneId, 'Europe/London');
    expect(synced.displayTimeZoneId, 'Europe/London');
    expect(
      remote.timeZoneWrites,
      isNot(contains('Asia/Tokyo')),
      reason: '待上传昵称的保存不得携带未被接受的设备时区',
    );
  });

  test('晚到的保存应答不覆盖另一入口更新的账号时区', () async {
    final slow = buildRepository();
    final fast = buildRepository();
    await slow.saveProfile(displayName: '小林', timeZoneId: 'Asia/Tokyo');

    clock = clock.add(const Duration(minutes: 1));
    final gate = Completer<void>();
    remote.saveGate = gate;
    final slowWrite = slow.saveProfile(
      displayName: '小林',
      timeZoneId: 'Europe/London',
    );
    await Future<void>.delayed(Duration.zero);
    expect(remote.saveCalls, 2, reason: '旧请求已发出并停在途中');

    // 另一入口随后做出更新的选择。
    clock = clock.add(const Duration(minutes: 1));
    await fast.saveProfile(displayName: '小林', timeZoneId: 'America/New_York');
    gate.complete();
    await slowWrite;

    final after = await slow.getProfile();
    expect(after.displayTimeZoneId, 'America/New_York');
    expect(remote.stored?.displayTimeZoneId, 'America/New_York');
  });

  test('账号清除后晚到的时区初始化不复活资料行', () async {
    final repository = buildRepository();
    final gate = Completer<RemoteProfile?>();
    remote.initializeGate = gate;

    final migrating = repository.ensureDisplayTimeZone(
      deviceTimeZoneId: 'Asia/Shanghai',
    );
    await Future<void>.delayed(Duration.zero);
    expect(remote.initializeCalls, 1);

    await purgeUser('user-a');
    gate.complete(
      RemoteProfile(
        displayName: '',
        avatar: null,
        updatedAt: clock,
        displayTimeZoneId: 'Asia/Shanghai',
      ),
    );
    await migrating;

    expect(await profileRows('user-a'), isEmpty);
  });

  test('没有昵称的账号只改时区时不要求先设置昵称', () async {
    final repository = buildRepository();
    // 首次原子初始化在账号存储里留下空昵称行，昵称仍未设置。
    await repository.ensureDisplayTimeZone(deviceTimeZoneId: 'Asia/Tokyo');
    expect(remote.stored?.displayName, isEmpty);

    final saved = await repository.saveProfile(
      displayName: '',
      timeZoneId: 'Asia/Singapore',
    );
    expect(saved.syncError, isNull);
    expect(saved.displayName, isEmpty);
    expect(saved.effectiveDisplayName, '当前用户');
    expect(saved.displayTimeZoneId, 'Asia/Singapore');
    expect(remote.stored?.displayName, isEmpty, reason: '时区保存不得伪造昵称');
    expect(remote.stored?.displayTimeZoneId, 'Asia/Singapore');
  });

  test('清空已有昵称被拒绝，本机与账号值都保持原昵称', () async {
    final repository = buildRepository();
    await repository.saveProfile(displayName: '小林');

    await expectLater(
      repository.saveProfile(displayName: '   ', timeZoneId: 'Asia/Tokyo'),
      throwsA(isA<AvatarValidationException>()),
    );
    expect((await repository.getProfile()).displayName, '小林');
    expect(remote.stored?.displayName, '小林');
    expect(remote.stored?.displayTimeZoneId, isNull, reason: '被拒绝的保存不得顺手写入时区');
  });

  test('只改昵称不会把本机缓存的旧时区重新推给账号存储', () async {
    remote.stored = RemoteProfile(
      displayName: '小林',
      avatar: null,
      updatedAt: clock,
      displayTimeZoneId: 'Asia/Tokyo',
    );
    remote.storedTimeZoneRequestedAt = clock;
    final deviceA = buildRepository();
    final adopted = await deviceA.syncProfile();
    expect(adopted.displayTimeZoneId, 'Asia/Tokyo');

    // 另一台设备随后选了伦敦，账号存储里的值更新到更晚的时间。
    clock = clock.add(const Duration(minutes: 5));
    remote.stored = RemoteProfile(
      displayName: '小林',
      avatar: null,
      updatedAt: clock,
      displayTimeZoneId: 'Europe/London',
    );
    remote.storedTimeZoneRequestedAt = clock;

    clock = clock.add(const Duration(minutes: 1));
    final renamed = await deviceA.saveProfile(displayName: '新名');
    expect(remote.timeZoneWrites.last, isNull, reason: '未改动时区时不上传时区');
    expect(remote.stored?.displayTimeZoneId, 'Europe/London');
    expect(renamed.displayTimeZoneId, 'Europe/London');
  });

  test('上传失败的时区在重开仓储后仍会补传一次', () async {
    remote.saveError = StateError('网络不可用');
    final offline = buildRepository();
    final failed = await offline.saveProfile(
      displayName: '小林',
      timeZoneId: 'Asia/Tokyo',
    );
    expect(failed.hasPendingSave, isTrue);
    expect(failed.pendingTimeZoneUpload, isTrue);

    remote.saveError = null;
    final reopened = buildRepository();
    final synced = await reopened.syncProfile();
    expect(synced.displayTimeZoneId, 'Asia/Tokyo');
    expect(remote.stored?.displayTimeZoneId, 'Asia/Tokyo');

    final renamed = await reopened.saveProfile(displayName: '新名');
    expect(remote.timeZoneWrites.last, isNull);
    expect(renamed.displayTimeZoneId, 'Asia/Tokyo');
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
