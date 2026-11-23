import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_checkpoints.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 账号时区决定国策换天：账号时区当地 04:00 结算，设备时区只影响显示；
/// 切换账号时区时有 12 小时防回拨保护，既不会重复计日也不会回退已结算进度。
void main() {
  test('未设时区沿用旧行为：北京时间 04:00（20:00Z）', () {
    expect(
      nationalFocusCheckpointAtOrBefore(DateTime.utc(2026, 9, 25, 19, 59)),
      DateTime.utc(2026, 9, 24, 20),
    );
    expect(
      nextNationalFocusCheckpoint(DateTime.utc(2026, 9, 25, 19, 59)),
      DateTime.utc(2026, 9, 25, 20),
    );
    expect(
      nationalFocusCheckpointAtOrBefore(
        DateTime.utc(2026, 9, 25, 20),
        timeZoneId: 'Nope/Unknown',
      ),
      DateTime.utc(2026, 9, 25, 20),
    );
  });

  test('夏令时切换日按日历日回到当地 04:00，而不是减 24 小时', () {
    // 纽约 2026-03-08 02:00 EST 跳到 03:00 EDT，因此 04:00 是 08:00Z，
    // 而 3/7 的 04:00 是 09:00Z：两次检查点只差 23 小时。
    expect(
      nationalFocusCheckpointAtOrBefore(
        DateTime.utc(2026, 3, 8, 7, 59),
        timeZoneId: 'America/New_York',
      ),
      DateTime.utc(2026, 3, 7, 9),
    );
    expect(
      nationalFocusCheckpointAtOrBefore(
        DateTime.utc(2026, 3, 8, 8),
        timeZoneId: 'America/New_York',
      ),
      DateTime.utc(2026, 3, 8, 8),
    );
    expect(
      nextNationalFocusCheckpoint(
        DateTime.utc(2026, 3, 8, 8),
        timeZoneId: 'America/New_York',
      ),
      DateTime.utc(2026, 3, 9, 8),
    );
    // 11 月 1 日纽约回落到 EST 后，当地 04:00 是 09:00Z。
    expect(
      nationalFocusCheckpointAtOrBefore(
        DateTime.utc(2026, 11, 1, 12),
        timeZoneId: 'America/New_York',
      ),
      DateTime.utc(2026, 11, 1, 9),
    );
  });

  test('账号时区当地 04:00 换天，同一时刻在不同账号时区落在不同 UTC 结算点', () async {
    final cases = <(String, DateTime)>[
      ('Asia/Dhaka', DateTime.utc(2026, 9, 25, 22)),
      ('Asia/Tokyo', DateTime.utc(2026, 9, 25, 19)),
      ('Europe/London', DateTime.utc(2026, 9, 26, 3)),
      ('America/New_York', DateTime.utc(2026, 9, 26, 8)),
    ];

    for (final (zoneId, checkpoint) in cases) {
      var now = checkpoint.subtract(const Duration(hours: 3));
      final database = PactaDatabase(NativeDatabase.memory());
      final profile = LocalProfileRepository(
        database: database,
        userId: _userId,
        remote: _MemoryProfileRemote(),
        now: () => now,
      );
      final tree = LocalNationalFocusRepository(
        database: database,
        userId: _userId,
        cloudSyncEnabled: false,
        now: () => now,
      );
      try {
        await profile.saveProfile(displayName: '留学生', timeZoneId: zoneId);
        expect((await profile.getProfile()).displayTimeZoneId, zoneId);

        final card = await tree.createCard(
          const NationalFocusCardDraft(
            name: '开始工作前',
            triggerCondition: '开始工作前',
            action: '打开计划',
          ),
        );
        await tree.placeCard(cardId: card.id, parentId: null);
        await tree.lightCard(card.id);

        now = checkpoint.subtract(const Duration(minutes: 1));
        await tree.settleDueCheckpoints();
        expect(
          (await tree.getCard(card.id)).state,
          NationalFocusCardState.lit,
          reason: '$zoneId 不得提前结算',
        );

        // 账号时区当地 04:00：只进入待确认，不记失败。
        now = checkpoint;
        await tree.settleDueCheckpoints();
        expect(await tree.getFailures(), isEmpty, reason: zoneId);
        expect(
          (await tree.getCard(card.id)).state,
          NationalFocusCardState.pendingTodayConfirmation,
          reason: zoneId,
        );

        // 下一个同日检查点仍未确认才记为漏确认，时刻仍是账号时区的 04:00。
        now = checkpoint.add(const Duration(days: 1));
        await tree.settleDueCheckpoints();
        final failures = await tree.getFailures();
        expect(failures, hasLength(1), reason: zoneId);
        expect(
          failures.single.checkpointAt.toUtc(),
          checkpoint.add(const Duration(days: 1)),
          reason: '$zoneId 的结算点跟随账号时区',
        );
        expect(
          (await tree.getCard(card.id)).state,
          NationalFocusCardState.extinguished,
          reason: zoneId,
        );
      } finally {
        await tree.dispose();
        await profile.dispose();
        await database.close();
      }
    }
  });

  test('从东九区切到东八区：不足 12 小时顺延一天，不重复结算、不回拨', () async {
    var now = DateTime.utc(2026, 9, 26, 18);
    final database = PactaDatabase(NativeDatabase.memory());
    final profile = LocalProfileRepository(
      database: database,
      userId: _userId,
      remote: _MemoryProfileRemote(),
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
      now: () => now,
    );
    try {
      await profile.saveProfile(displayName: '在东京', timeZoneId: 'Asia/Tokyo');
      final card = await tree.createCard(
        const NationalFocusCardDraft(
          name: '背单词',
          triggerCondition: '早上坐下',
          action: '打开墨墨',
        ),
      );
      await tree.placeCard(cardId: card.id, parentId: null);
      await tree.lightCard(card.id);
      expect(await _lastSettled(database), DateTime.utc(2026, 9, 25, 19));

      // 东京 2026-09-27 04:00（19:00Z）：进入待确认。
      now = DateTime.utc(2026, 9, 26, 19);
      await tree.settleDueCheckpoints();
      expect(
        (await tree.getCard(card.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(await _lastSettled(database), DateTime.utc(2026, 9, 26, 19));

      // 切到北京时区：下一个当地 04:00 是 20:00Z，只差 1 小时。
      await profile.saveProfile(
        displayName: '回到北京',
        timeZoneId: 'Asia/Shanghai',
      );
      now = DateTime.utc(2026, 9, 26, 20, 30);
      await tree.settleDueCheckpoints();
      expect(
        await _lastSettled(database),
        DateTime.utc(2026, 9, 26, 19),
        reason: '已结算进度绝不回拨',
      );
      expect(await tree.getFailures(), isEmpty, reason: '12 小时内不得重复结算');
      expect(
        (await tree.getCard(card.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );

      // 顺延到北京 2026-09-28 04:00（2026-09-27 20:00Z）才结算。
      now = DateTime.utc(2026, 9, 27, 20);
      await tree.settleDueCheckpoints();
      final failures = await tree.getFailures();
      expect(failures, hasLength(1));
      expect(
        failures.single.checkpointAt.toUtc(),
        DateTime.utc(2026, 9, 27, 20),
      );
      expect(await _lastSettled(database), DateTime.utc(2026, 9, 27, 20));
    } finally {
      await tree.dispose();
      await profile.dispose();
      await database.close();
    }
  });

  test('从纽约切到东京：间隔 11 小时同样顺延，不跳日也不重复计连续天数', () async {
    var now = DateTime.utc(2026, 9, 25, 12);
    final database = PactaDatabase(NativeDatabase.memory());
    final profile = LocalProfileRepository(
      database: database,
      userId: _userId,
      remote: _MemoryProfileRemote(),
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
      now: () => now,
    );
    try {
      await profile.saveProfile(
        displayName: '在纽约',
        timeZoneId: 'America/New_York',
      );
      final card = await tree.createCard(
        const NationalFocusCardDraft(
          name: '读论文',
          triggerCondition: '午后',
          action: '读一篇',
        ),
      );
      await tree.placeCard(cardId: card.id, parentId: null);
      await tree.lightCard(card.id);
      expect(await _lastSettled(database), DateTime.utc(2026, 9, 25, 8));

      // 纽约 2026-09-26 04:00 EDT（08:00Z）：进入待确认。
      now = DateTime.utc(2026, 9, 26, 8);
      await tree.settleDueCheckpoints();
      expect(await _lastSettled(database), DateTime.utc(2026, 9, 26, 8));

      // 切到东京：下一个当地 04:00 是 19:00Z，只差 11 小时。
      await profile.saveProfile(displayName: '在东京', timeZoneId: 'Asia/Tokyo');
      now = DateTime.utc(2026, 9, 26, 18);
      await tree.settleDueCheckpoints();
      expect(await tree.getFailures(), isEmpty);
      expect(await _lastSettled(database), DateTime.utc(2026, 9, 26, 8));

      now = DateTime.utc(2026, 9, 27, 19);
      await tree.settleDueCheckpoints();
      final failures = await tree.getFailures();
      expect(failures, hasLength(1));
      expect(
        failures.single.checkpointAt.toUtc(),
        DateTime.utc(2026, 9, 27, 19),
      );
      expect(
        failures.single.cause,
        NationalFocusFailureCause.missedConfirmation,
        reason: '顺延一天只结算一次，不会补齐被跳过的中间日',
      );
    } finally {
      await tree.dispose();
      await profile.dispose();
      await database.close();
    }
  });
}

const _userId = 'user-a';

Future<DateTime?> _lastSettled(PactaDatabase database) async {
  final row = await (database.select(
    database.localNationalFocusMaintenance,
  )..where((entry) => entry.userId.equals(_userId))).getSingleOrNull();
  return row?.lastSettledCheckpointAt.toUtc();
}

class _MemoryProfileRemote implements ProfileRemote {
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
    String? displayTimeZoneId,
    int? timeZoneRevision,
  }) async {
    stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
      displayTimeZoneId: displayTimeZoneId ?? stored?.displayTimeZoneId,
    );
    return stored!;
  }

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) async {
    final previous = stored;
    if (previous == null) {
      return stored = RemoteProfile(
        displayName: '',
        avatar: null,
        updatedAt: DateTime.now().toUtc(),
        displayTimeZoneId: displayTimeZoneId,
      );
    }
    if (previous.displayTimeZoneId != null) return previous;
    return stored = RemoteProfile(
      displayName: previous.displayName,
      avatar: previous.avatar,
      updatedAt: DateTime.now().toUtc(),
      displayTimeZoneId: displayTimeZoneId,
    );
  }
}
