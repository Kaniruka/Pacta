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

        // 3. 真并发首次写入：同一全新账号上同时发出两次 first save 与两次
        //    initialize，覆盖 save/save、save/initialize、initialize/initialize。
        //    四个请求真正同时在途，不靠 sleep 制造交错。
        final otherBefore = await _read(otherRemote, otherId);
        expect(otherBefore, isNull, reason: '并发迁移需要第二个全新账号');
        final otherRace = await Future.wait<RemoteProfile?>([
          otherRemote.save(
            userId: otherId,
            displayName: '并发写入甲',
            avatar: null,
            updatedAt: clock,
            displayTimeZoneId: 'Asia/Singapore',
            timeZoneRevision: 0,
          ),
          otherPeerRemote.save(
            userId: otherId,
            displayName: '并发写入乙',
            avatar: null,
            updatedAt: clock,
            displayTimeZoneId: 'America/Los_Angeles',
            timeZoneRevision: 0,
          ),
          otherRemote.initializeTimeZone(
            userId: otherId,
            displayTimeZoneId: 'Europe/London',
          ),
          otherPeerRemote.initializeTimeZone(
            userId: otherId,
            displayTimeZoneId: 'Asia/Tokyo',
          ),
        ]);
        final firstSave = otherRace[0]!;
        final secondSave = otherRace[1]!;
        final firstInit = otherRace[2]!;
        final secondInit = otherRace[3]!;
        final raceZones = {
          firstSave.displayTimeZoneId,
          secondSave.displayTimeZoneId,
          firstInit.displayTimeZoneId,
          secondInit.displayTimeZoneId,
        };
        expect(raceZones, hasLength(1), reason: '四个首写必须收敛到同一值');
        expect(
          firstSave.displayTimeZoneId,
          anyOf(
            'Asia/Singapore',
            'America/Los_Angeles',
            'Europe/London',
            'Asia/Tokyo',
          ),
          reason: '赢家必须是四个请求之一',
        );
        final raceRevisions = {
          firstSave.timeZoneRevision,
          secondSave.timeZoneRevision,
          firstInit.timeZoneRevision,
          secondInit.timeZoneRevision,
        };
        expect(raceRevisions, hasLength(1), reason: '回答里的修订号必须一致');
        expect(raceRevisions.single, 1, reason: '后到的首写不得追加修订号');
        // 冲突标记必须如实表示本次请求值是否生效：赢家 false，输家 true。
        expect(
          firstSave.timeZoneConflict,
          firstSave.displayTimeZoneId != 'Asia/Singapore',
        );
        expect(
          secondSave.timeZoneConflict,
          secondSave.displayTimeZoneId != 'America/Los_Angeles',
        );
        final otherAfter = await _read(otherRemote, otherId);
        expect(otherAfter?.displayTimeZoneId, raceZones.single);
        expect(otherAfter?.timeZoneRevision, raceRevisions.single);
        expect(
          otherAfter?.displayName,
          anyOf('并发写入甲', '并发写入乙'),
          reason: '首写竞争不得伪造昵称，最终昵称来自其中一次保存',
        );
        print(
          'PROFILE_TZ_REAL concurrent first save/initialize PASS '
          '(winner = ${raceZones.single})',
        );

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
          final skewedSave = await skewed.saveProfile(
            displayName: nickname,
            timeZoneId: 'Europe/London',
          );
          expect(skewedSave.displayTimeZoneId, 'Europe/London');
          // 正确时钟的设备在 London 之后才同步，看到当前修订号后再做新选择；
          // 不自动重放旧意图，也不把旧修订号直接改写成新值。
          final adoptedBeforeEdit = await corrected.syncProfile();
          expect(adoptedBeforeEdit.displayTimeZoneId, 'Europe/London');
          // 读取到的就是 London 写入之后的那个修订号（与写入响应相等），
          // 不是更大；随后真正的新写入才会再推进一个修订号。
          expect(
            adoptedBeforeEdit.timeZoneRevision,
            skewedSave.timeZoneRevision,
          );
          final correctedSave = await corrected.saveProfile(
            displayName: nickname,
            timeZoneId: 'Pacific/Auckland',
          );
          expect(
            correctedSave.displayTimeZoneId,
            'Pacific/Auckland',
            reason: '正确时钟的明确修改必须胜过未来时钟的旧写入',
          );
          expect(
            correctedSave.timeZoneRevision,
            greaterThan(adoptedBeforeEdit.timeZoneRevision),
            reason: '新写入必须在观察到的账号修订号之后推进一次',
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

        // 9. 服务端校验完整 IANA 标识，而不是只检查长度。公共包装器把
        //    PostgREST 错误转成 StateError，因此精确 SQLSTATE 用原始 RPC 取证。
        var invalidInitializeRejected = false;
        try {
          await client.rpc(
            'initialize_profile_time_zone',
            params: {'p_time_zone_id': 'not/a-zone'},
          );
        } on PostgrestException catch (error) {
          invalidInitializeRejected = error.code == '22023';
        }
        expect(invalidInitializeRejected, isTrue);

        var invalidSaveRejected = false;
        try {
          final nowCurrent = await _read(remote, userId);
          await client.rpc(
            'save_profile_account',
            params: {
              'p_display_name': nickname,
              'p_time_zone_id': 'Mars/Olympus',
              'p_time_zone_revision': nowCurrent!.timeZoneRevision,
            },
          );
        } on PostgrestException catch (error) {
          invalidSaveRejected = error.code == '22023';
        }
        expect(invalidSaveRejected, isTrue);

        // 公共包装器的错误契约也要成立，且失败的保存不改变账号值。
        var wrapperRejected = false;
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
        } on StateError catch (error) {
          wrapperRejected = error.message.contains('保存失败');
        }
        expect(wrapperRejected, isTrue);
        expect(
          (await _read(remote, userId))?.displayTimeZoneId,
          'Pacific/Auckland',
        );
        print('PROFILE_TZ_REAL invalid IANA identifiers rejected PASS');

        // 10. 空白昵称不得清除已有昵称（原始 RPC 取证 SQLSTATE）。
        var blankRejected = false;
        try {
          final nowCurrent = await _read(remote, userId);
          await client.rpc(
            'save_profile_account',
            params: {
              'p_display_name': '',
              'p_time_zone_id': 'Europe/London',
              'p_time_zone_revision': nowCurrent!.timeZoneRevision,
            },
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
