import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// 账号显示时区在真实 App 里的日分摊：同一段投入在两个账号时区下落在
/// 不同日期；近期活动窗口以"今天"结束，因此未来日不会被渲染。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('看板按账号显示时区分摊任务进度与近期活动', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 9, 22, 15, 50);
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final profileRemote = _MemoryProfileRemote();
    final profileRepository = LocalProfileRepository(
      database: database,
      userId: 'user-a',
      remote: profileRemote,
      now: () => now,
    );

    try {
      await profileRepository.saveProfile(
        displayName: '设备验收',
        timeZoneId: 'Asia/Shanghai',
      );
      final goal = await taskRepository.createGoal(
        const GoalDraft(title: '设备验收', classification: TaskClassification.both),
      );
      final task = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '核对有效投入',
          classification: TaskClassification.both,
          estimatedMinutes: 10,
        ),
      );
      final session = await focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(hours: 1),
      );
      now = now.add(const Duration(minutes: 30));
      await focusRepository.abandonSession(
        sessionId: session.id,
        failureReason: '验证失败会话仍计入实际投入',
      );

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'user-a',
          taskRepositoryFactory: (_) => taskRepository,
          focusRepositoryFactory: (_) => focusRepository,
          profileRepositoryFactory: (_) => profileRepository,
        ),
      );
      await _pumpBoard(tester);

      // 「看板」同时出现在底部导航与页头：标题断言限定在页面子树内。
      expect(
        find.descendant(of: find.byType(BoardPage), matching: find.text('看板')),
        findsOneWidget,
      );
      // 原「近期专注活动」已融合为「专注与国策」：账号时区分摊体现在
      // 热力月历与日期详情里，不再有单独的近 7 天文字行。
      await _revealBoard(tester, find.text('专注与国策'));
      expect(find.text('专注与国策'), findsOneWidget);

      // 上海（UTC+8）：15:50Z–16:20Z 是 23:50–00:20，跨到 9/23。
      // 今天（9/22）只拿到 00:00 之前的 10 分钟，9/23 拿到 20 分钟。
      expect(find.text('9 月 22 日（今日）'), findsOneWidget);
      expect(find.text('10分钟'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('board-focus-day-23')));
      await _pumpBoard(tester);
      expect(find.text('9 月 23 日'), findsOneWidget);
      expect(find.text('20分钟'), findsOneWidget);

      // 同一账号改成洛杉矶（UTC−7）：08:50–09:20，整段落在 9/22。
      await profileRepository.saveProfile(
        displayName: '设备验收',
        timeZoneId: 'America/Los_Angeles',
      );
      await _pumpBoard(tester);
      await _revealBoard(tester, find.text('专注与国策'));
      expect(find.text('9 月 22 日（今日）'), findsOneWidget);
      expect(find.text('30分钟'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    }
  });
}

/// 把看板上的目标滚进可见区（融合卡片在今日安排与置顶摘要之下）。
Future<void> _revealBoard(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(BoardPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// 真实数据库与流需要真实时间推进；周期计时器让 pumpAndSettle 不可用。
Future<void> _pumpBoard(WidgetTester tester) async {
  await tester.pump();
  for (var index = 0; index < 12; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
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
