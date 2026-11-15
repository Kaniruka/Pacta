import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 账号显示时区只影响"日分摊"的显示，不得移动国策检查点：
/// 检查点固定在北京时间 04:00（20:00Z），与账号偏好无关。
void main() {
  var now = DateTime.utc(2026, 9, 25, 19, 59);

  test('切换账号显示时区不移动国策检查点结算时刻', () async {
    for (final displayTimeZoneId in <String>[
      'Asia/Tokyo',
      'America/Los_Angeles',
    ]) {
      now = DateTime.utc(2026, 9, 25, 19, 59);
      final database = PactaDatabase(NativeDatabase.memory());
      final remote = _MemoryProfileRemote();
      final profile = LocalProfileRepository(
        database: database,
        userId: 'user-a',
        remote: remote,
        now: () => now,
      );
      final tree = LocalNationalFocusRepository(
        database: database,
        userId: 'user-a',
        cloudSyncEnabled: false,
        now: () => now,
      );
      try {
        await profile.saveProfile(
          displayName: '小林',
          timeZoneId: displayTimeZoneId,
        );
        expect(
          (await profile.getProfile()).displayTimeZoneId,
          displayTimeZoneId,
        );

        final card = await tree.createCard(
          NationalFocusCardDraft(
            name: '开始工作前',
            triggerCondition: '开始工作前',
            action: '打开计划',
          ),
        );
        await tree.placeCard(cardId: card.id, parentId: null);
        await tree.lightCard(card.id);

        // 北京时间 04:00 之前不算漏确认；到点后只进入待确认。
        now = DateTime.utc(2026, 9, 25, 19, 59, 59);
        await tree.settleDueCheckpoints();
        expect(
          await tree.getFailures(),
          isEmpty,
          reason: '显示时区 $displayTimeZoneId 不得提前结算',
        );

        now = DateTime.utc(2026, 9, 25, 20);
        await tree.settleDueCheckpoints();
        expect(await tree.getFailures(), isEmpty);
        expect(
          (await tree.getCard(card.id)).state,
          NationalFocusCardState.pendingTodayConfirmation,
        );

        // 下一个固定检查点仍未确认才记为漏确认；时刻仍是 20:00Z。
        now = DateTime.utc(2026, 9, 26, 20);
        await tree.settleDueCheckpoints();
        final failures = await tree.getFailures();
        expect(failures, hasLength(1), reason: displayTimeZoneId);
        expect(
          failures.single.checkpointAt.toUtc(),
          DateTime.utc(2026, 9, 26, 20),
          reason: '检查点固定 20:00Z，不随账号显示时区移动',
        );
        expect(
          (await tree.getCard(card.id)).state,
          NationalFocusCardState.extinguished,
        );
      } finally {
        await tree.dispose();
        await profile.dispose();
        await database.close();
      }
    }
  });
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
