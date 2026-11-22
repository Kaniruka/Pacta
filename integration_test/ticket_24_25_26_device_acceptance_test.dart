import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/support/fake_auth_repository.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);
const _t25TestEmail = String.fromEnvironment('T25_TEST_EMAIL');
const _t25TestPassword = String.fromEnvironment('T25_TEST_PASSWORD');
const _t25ExpectedUserId = String.fromEnvironment('T25_EXPECTED_USER_ID');
final _hasT25AuthConfiguration =
    _supabaseUrl.isNotEmpty &&
    _supabasePublishableKey.isNotEmpty &&
    _t25TestEmail.isNotEmpty &&
    _t25TestPassword.isNotEmpty &&
    _t25ExpectedUserId.isNotEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('T24 安卓设备看板汇总国策状态并保留任务专注上下文', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 9, 22, 8);
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'ticket-24-device-user',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'ticket-24-device-user',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: 'ticket-24-device-user',
      remote: InMemoryNationalFocusRemoteDataSource(),
      now: () => now,
    );

    try {
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '设备验收目标',
          classification: TaskClassification.both,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '设备验收任务',
          classification: TaskClassification.both,
          estimatedMinutes: 25,
        ),
      );
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      now = now.add(const Duration(minutes: 13));
      await focus.abandonSession(
        sessionId: session.id,
        failureReason: '设备验收用的本地演示记录',
      );
      final card = await nationalFocus.createCard(
        const NationalFocusCardDraft(
          name: '开始工作前',
          triggerCondition: '开始工作前',
          action: '写下第一步',
        ),
      );
      await nationalFocus.placeCard(cardId: card.id, parentId: null);
      await nationalFocus.lightCard(card.id);
      now = DateTime.utc(2026, 9, 22, 20, 1);
      await nationalFocus.settleDueCheckpoints();

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()
            ..signedInUser = 'ticket-24-device-user',
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => nationalFocus,
        ),
      );
      await tester.pumpAndSettle();

      // 看板只保留摘要：国策状态与专注热力融合成「专注与国策」。
      expect(find.text('专注与国策'), findsOneWidget);
      expect(find.text('今日国策状态'), findsOneWidget);
      expect(find.text('点亮 0'), findsOneWidget);
      expect(find.text('待确认 1'), findsOneWidget);
      expect(find.text('熄灭 0'), findsOneWidget);

      // 任务与「开始专注」只在计划页。
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('计划'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('设备验收任务'), findsOneWidget);
      expect(find.textContaining('已专注 13分00秒'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('开始专注'));
      await tester.tap(find.byTooltip('开始专注'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('设备验收任务'),
        ),
        findsOneWidget,
      );
      final durationField = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(durationField.controller?.text, '25');
      expect(durationField.decoration?.labelText, '时长（分钟）');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      // 回到看板：今日国策状态整卡可点，直达国策树。
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('看板'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('board-today-national-focus')),
      );
      await tester.tap(
        find.byKey(const ValueKey('board-today-national-focus')),
      );
      await tester.pumpAndSettle();
      expect(find.text('全部确认 (1)'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    }
  });

  testWidgets('T25 Android/Windows 新密码登录仍是原 Supabase 身份', (tester) async {
    final userId = await tester.runAsync(() async {
      final client = SupabaseClient(_supabaseUrl, _supabasePublishableKey);
      try {
        final auth = SupabaseAuthRepository(client);
        await auth.signIn(email: _t25TestEmail, password: _t25TestPassword);
        final userId = auth.currentUserId;
        await auth.signOut();
        return userId;
      } finally {
        await client.dispose();
      }
    });

    expect(userId, _t25ExpectedUserId);
  }, skip: !_hasT25AuthConfiguration);
}
