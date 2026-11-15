// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Runs only against the loopback acceptance fixture's isolated project. The
// protected .env and administrator keys are never compiled into this app:
// credentials come from the runtime control endpoint at test time.
const _control = String.fromEnvironment('ISSUE71_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'ISSUE90_RUNTIME_PORT',
  defaultValue: '30390',
);

Future<Map<String, dynamic>> _configuration(String user) async {
  final response = await http.get(
    Uri.parse('http://127.0.0.1:$_port/session?user=$user'),
    headers: {'X-Pacta-Acceptance': _control},
  );
  if (response.statusCode != 200) {
    throw StateError('Isolated acceptance session unavailable.');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<SupabaseClient> _client(Map<String, dynamic> config) async {
  final client = SupabaseClient(
    config['url'] as String,
    config['publishableKey'] as String,
  );
  await client.auth.setSession(config['refreshToken'] as String);
  expect(client.auth.currentUser?.id, config['userId']);
  return client;
}

/// 只在指定的离线步骤前挂上一次网络失败，用来验证待上传意图在恢复后只补传
/// 一次。构造时不预置失败，否则前面正常的保存会先把它消耗掉。
class _FlakyProfileRemote implements ProfileRemote {
  _FlakyProfileRemote(this.inner);

  final SupabaseProfileRemote inner;
  bool failNextSave = false;

  @override
  bool get isAvailable => inner.isAvailable;

  @override
  Future<RemoteProfile?> fetch({required String userId}) =>
      inner.fetch(userId: userId);

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) => inner.initializeTimeZone(
    userId: userId,
    displayTimeZoneId: displayTimeZoneId,
  );

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
    int? timeZoneRevision,
  }) {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('模拟网络中断');
    }
    return inner.save(
      userId: userId,
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
      displayTimeZoneId: displayTimeZoneId,
      timeZoneRevision: timeZoneRevision,
    );
  }
}

Future<RemoteProfile?> _read(ProfileRemote remote, String userId) =>
    remote.fetch(userId: userId);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real account time zone: atomic init, revision ordering, two '
      'clients, isolation and offline recovery', (tester) async {
    expect(_control, isNotEmpty, reason: '需要 runtime control');
    await tester.runAsync(() async {
      final config = await _configuration('device');
      final otherConfig = await _configuration('other');
      final client = await _client(config);
      final peer = await _client(config); // 同一账号的第二客户端
      final other = await _client(otherConfig); // 另一账号
      final otherPeer = await _client(otherConfig); // 另一账号的第二客户端
      final userId = config['userId'] as String;
      final otherId = otherConfig['userId'] as String;
      final remote = SupabaseProfileRemote(client);
      final peerRemote = SupabaseProfileRemote(peer);
      final otherRemote = SupabaseProfileRemote(other);
      final otherPeerRemote = SupabaseProfileRemote(otherPeer);
      final database = PactaDatabase(NativeDatabase.memory());
      final otherDatabase = PactaDatabase(NativeDatabase.memory());
      // 一个受控的固定时钟用于本机写入，避免固定时间与实时时钟混用。
      final clock = DateTime.utc(2026, 11, 15, 10);
      final flakyRemote = _FlakyProfileRemote(remote);
      final profile = LocalProfileRepository(
        database: database,
        userId: userId,
        remote: flakyRemote,
        now: () => clock,
      );
      final otherProfile = LocalProfileRepository(
        database: otherDatabase,
        userId: otherId,
        remote: otherRemote,
        now: () => clock,
      );

      try {
        // 全新账号：root 必须提供两个从未使用过的隔离用户。
        final before = await _read(remote, userId);
        expect(before, isNull, reason: '需要全新账号；请由 root 提供未使用的隔离用户');

        // 1. 原子初始化：只补空值，不编造昵称，首次接受只推进一个修订号。
        final first = await remote.initializeTimeZone(
          userId: userId,
          displayTimeZoneId: 'Asia/Tokyo',
        );
        expect(first, isNotNull);
        final winnerZone = first!.displayTimeZoneId;
        expect(winnerZone, 'Asia/Tokyo', reason: '首次值就是本次请求的值');
        expect(first.displayName, isEmpty, reason: '没有资料时写空昵称，不伪造名字');
        expect(first.timeZoneRevision, 1, reason: '首次接受只前进一个修订号');
        print(
          'PROFILE_TZ_REAL initial winner = $winnerZone '
          'revision = ${first.timeZoneRevision}',
        );

        // 2. 第二台设备初始化同一账号：只能采用赢家，不能各写各的。
        final peerAttempt = await peerRemote.initializeTimeZone(
          userId: userId,
          displayTimeZoneId: 'Europe/London',
        );
        expect(peerAttempt?.displayTimeZoneId, winnerZone);
        expect(peerAttempt?.timeZoneRevision, first.timeZoneRevision);

        // 3. 真正的并发首次迁移：两个独立客户端同时初始化另一全新账号。
        final otherBefore = await _read(otherRemote, otherId);
        expect(otherBefore, isNull, reason: '并发迁移需要第二个全新账号');
        final concurrent = await Future.wait([
          otherRemote.initializeTimeZone(
            userId: otherId,
            displayTimeZoneId: 'Asia/Singapore',
          ),
          otherPeerRemote.initializeTimeZone(
            userId: otherId,
            displayTimeZoneId: 'America/Los_Angeles',
          ),
        ]);
        final raceZones = concurrent
            .map((profile) => profile?.displayTimeZoneId)
            .toSet();
        expect(raceZones, hasLength(1), reason: '两个客户端必须收敛到同一值');
        expect(raceZones.single, isNotNull);
        final raceRevision = concurrent.first?.timeZoneRevision;
        expect(raceRevision, concurrent.last?.timeZoneRevision);
        final otherAfter = await _read(otherRemote, otherId);
        expect(otherAfter?.displayTimeZoneId, raceZones.single);
        expect(otherAfter?.timeZoneRevision, raceRevision);
        expect(
          raceZones.single,
          anyOf('Asia/Singapore', 'America/Los_Angeles'),
          reason: '首次并发初始化只能产生一个请求值作为赢家',
        );
        expect(raceRevision, 1);
        expect(otherAfter?.displayName, isEmpty, reason: '并发初始化不伪造昵称');
        print('PROFILE_TZ_REAL concurrent initialization PASS');

        // 4. 空昵称账号可以只改时区；已有昵称则保持原样，不伪造名字。
        final syncedBeforeZoneEdit = await profile.syncProfile();
        final revisionBeforeZoneEdit = syncedBeforeZoneEdit.timeZoneRevision;
        final zoneOnly = await profile.saveProfile(
          displayName: '',
          timeZoneId: 'Asia/Singapore',
        );
        expect(
          zoneOnly.syncError,
          isNull,
          reason: '正常网络下只改时区的保存必须成功；失败留给专门的离线步骤',
        );
        expect(zoneOnly.hasPendingSave, isFalse);
        expect(zoneOnly.displayTimeZoneId, 'Asia/Singapore');
        expect(zoneOnly.displayName, isEmpty, reason: '只改时区不得写入或清除昵称');
        expect(zoneOnly.timeZoneRevision, greaterThan(revisionBeforeZoneEdit));
        final cloudAfterZoneOnly = await _read(remote, userId);
        expect(cloudAfterZoneOnly?.displayTimeZoneId, 'Asia/Singapore');
        expect(cloudAfterZoneOnly?.displayName, isEmpty);
        print('PROFILE_TZ_REAL time-zone-only save keeps the nickname PASS');

        // 5. 明确的更新请求（带当前修订号）获胜。
        final nickname = '时区验收 ${Platform.operatingSystem}';
        final current = await _read(remote, userId);
        expect(current, isNotNull);
        final updated = await remote.save(
          userId: userId,
          displayName: nickname,
          avatar: null,
          updatedAt: clock,
          displayTimeZoneId: 'America/New_York',
          timeZoneRevision: current!.timeZoneRevision,
        );
        expect(updated.displayTimeZoneId, 'America/New_York');
        expect(updated.timeZoneConflict, isFalse);
        expect(updated.timeZoneRevision, greaterThan(current.timeZoneRevision));

        // 6. 基于旧修订号的晚到请求不得覆盖已接受的新值。
        final stale = await remote.save(
          userId: userId,
          displayName: nickname,
          avatar: null,
          updatedAt: clock,
          displayTimeZoneId: 'Asia/Tokyo',
          timeZoneRevision: current.timeZoneRevision,
        );
        expect(stale.displayTimeZoneId, 'America/New_York');
        expect(stale.timeZoneConflict, isTrue, reason: '旧修订号必须被报告为冲突');
        expect(stale.timeZoneRevision, updated.timeZoneRevision);
        expect(stale.displayName, nickname, reason: '冲突只影响时区，不影响昵称');
        print('PROFILE_TZ_REAL revision CAS rejects the stale request PASS');

        // 7. 未来时钟设备的写入不会阻塞正确时钟设备随后的明确修改。
        final skewedDatabase = PactaDatabase(NativeDatabase.memory());
        final correctedDatabase = PactaDatabase(NativeDatabase.memory());
        try {
          final skewed = LocalProfileRepository(
            database: skewedDatabase,
            userId: userId,
            remote: remote,
            now: () => clock.add(const Duration(days: 1)),
          );
          final corrected = LocalProfileRepository(
            database: correctedDatabase,
            userId: userId,
            remote: remote,
            now: () => clock,
          );
          await skewed.syncProfile();
          await corrected.syncProfile();
          final skewedSave = await skewed.saveProfile(
            displayName: nickname,
            timeZoneId: 'Europe/London',
          );
          expect(skewedSave.displayTimeZoneId, 'Europe/London');
          final correctedSave = await corrected.saveProfile(
            displayName: nickname,
            timeZoneId: 'Pacific/Auckland',
          );
          expect(
            correctedSave.displayTimeZoneId,
            'Pacific/Auckland',
            reason: '正确时钟的明确修改必须胜过未来时钟的旧写入',
          );
          final cloudAfterSkew = await _read(remote, userId);
          expect(cloudAfterSkew?.displayTimeZoneId, 'Pacific/Auckland');
        } finally {
          await skewedDatabase.close();
          await correctedDatabase.close();
        }
        print('PROFILE_TZ_REAL future clock does not block a later edit PASS');

        // 8. 未同步到当前修订号的旧客户端只能采用账号值，不能覆盖。
        final neverSyncedDatabase = PactaDatabase(NativeDatabase.memory());
        try {
          final staleClient = LocalProfileRepository(
            database: neverSyncedDatabase,
            userId: userId,
            remote: remote,
            now: () => clock,
          );
          final staleSave = await staleClient.saveProfile(
            displayName: nickname,
            timeZoneId: 'Asia/Tokyo',
          );
          expect(staleSave.displayTimeZoneId, 'Pacific/Auckland');
          expect(
            staleSave.timeZoneRevision,
            (await _read(remote, userId))?.timeZoneRevision,
          );
          final cloudAfterStale = await _read(remote, userId);
          expect(cloudAfterStale?.displayTimeZoneId, 'Pacific/Auckland');
        } finally {
          await neverSyncedDatabase.close();
        }
        print('PROFILE_TZ_REAL unsynced client adopts the winner PASS');

        // 9. 服务端校验完整 IANA 标识，而不是只检查长度。
        var invalidInitializeRejected = false;
        try {
          await remote.initializeTimeZone(
            userId: userId,
            displayTimeZoneId: 'not/a-zone',
          );
        } on PostgrestException catch (error) {
          invalidInitializeRejected = error.code == '22023';
        }
        expect(invalidInitializeRejected, isTrue);
        var invalidSaveRejected = false;
        try {
          final nowCurrent = await _read(remote, userId);
          await remote.save(
            userId: userId,
            displayName: nickname,
            avatar: null,
            updatedAt: clock,
            displayTimeZoneId: 'Mars/Olympus',
            timeZoneRevision: nowCurrent!.timeZoneRevision,
          );
        } on PostgrestException catch (error) {
          invalidSaveRejected = error.code == '22023';
        }
        expect(invalidSaveRejected, isTrue);
        expect(
          (await _read(remote, userId))?.displayTimeZoneId,
          'Pacific/Auckland',
        );
        print('PROFILE_TZ_REAL invalid IANA identifiers rejected PASS');

        // 10. 空白昵称不得清除已有昵称。
        var blankRejected = false;
        try {
          final nowCurrent = await _read(remote, userId);
          await remote.save(
            userId: userId,
            displayName: '',
            avatar: null,
            updatedAt: clock,
            displayTimeZoneId: 'Europe/London',
            timeZoneRevision: nowCurrent!.timeZoneRevision,
          );
        } on PostgrestException catch (error) {
          blankRejected = error.code == '22023';
        }
        expect(blankRejected, isTrue, reason: '已有昵称不能被空输入静默清除');

        // 11. 旧的三参数保存（昵称/头像）不得改写账号时区。
        final legacySaved = await client.rpc(
          'save_profile_account',
          params: {'p_display_name': '$nickname 旧调用'},
        );
        expect(
          legacySaved is Map ? legacySaved['timeZoneId'] : null,
          'Pacific/Auckland',
          reason: '没有明确时区的旧调用不得覆盖账号时区',
        );
        print('PROFILE_TZ_REAL legacy save keeps the account zone PASS');

        // 12. 跨用户隔离：另一账号读不到本账号资料，也不能直读表。
        final otherRead = await other.rpc('read_profile_account');
        final otherZone = otherRead is Map ? otherRead['timeZoneId'] : null;
        expect(otherZone, isNot('Pacific/Auckland'));
        var directReadRejected = false;
        try {
          await other.from('profile_accounts').select('user_id').limit(1);
        } on PostgrestException {
          directReadRejected = true;
        }
        expect(directReadRejected, isTrue);
        print('PROFILE_TZ_REAL cross-user isolation PASS');

        // 13. 本机离线：失败保存保留待上传意图，恢复后补传一次并采用修订号。
        final beforeOffline = await profile.syncProfile();
        // 只有这里显式挂上网络失败，前面的正常保存不会消耗它。
        flakyRemote.failNextSave = true;
        final offlinePending = await profile.saveProfile(
          displayName: '$nickname 离线',
          timeZoneId: 'Asia/Tokyo',
        );
        expect(offlinePending.hasPendingSave, isTrue);
        expect(offlinePending.syncError, isNotNull);
        final recovered = await profile.syncProfile();
        expect(recovered.hasPendingSave, isFalse);
        expect(recovered.displayTimeZoneId, 'Asia/Tokyo');
        expect(
          recovered.timeZoneRevision,
          greaterThan(beforeOffline.timeZoneRevision),
        );
        final cloudAfterRecovery = await _read(remote, userId);
        expect(cloudAfterRecovery?.displayTimeZoneId, 'Asia/Tokyo');
        expect(cloudAfterRecovery?.displayName, '$nickname 离线');
        print('PROFILE_TZ_REAL offline recovery uploads once PASS');

        // 14. 恢复后普通昵称保存不再重推旧时区，修订号保持不变。
        final renamed = await profile.saveProfile(displayName: '$nickname 改名');
        expect(renamed.displayTimeZoneId, 'Asia/Tokyo');
        expect(renamed.timeZoneRevision, recovered.timeZoneRevision);
        final cloudAfterRename = await _read(remote, userId);
        expect(cloudAfterRename?.displayTimeZoneId, 'Asia/Tokyo');
        print('PROFILE_TZ_REAL nickname-only save keeps the account zone PASS');

        // 15. 另一账号仍可按自己的修订号改自己的时区（隔离后仍可用）。
        final otherCurrent = await _read(otherRemote, otherId);
        expect(otherCurrent, isNotNull);
        final otherEdit = await otherRemote.save(
          userId: otherId,
          displayName: otherCurrent!.displayName,
          avatar: null,
          updatedAt: clock,
          displayTimeZoneId: 'Europe/London',
          timeZoneRevision: otherCurrent.timeZoneRevision,
        );
        expect(otherEdit.displayTimeZoneId, 'Europe/London');
        expect(otherEdit.timeZoneConflict, isFalse);
        expect((await _read(remote, userId))?.displayTimeZoneId, 'Asia/Tokyo');
      } finally {
        await profile.dispose();
        await otherProfile.dispose();
        await database.close();
        await otherDatabase.close();
        await client.dispose();
        await peer.dispose();
        await other.dispose();
        await otherPeer.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 8)));
}
