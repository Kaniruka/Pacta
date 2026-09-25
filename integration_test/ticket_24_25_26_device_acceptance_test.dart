import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/admin_user_lifecycle_card.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
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

      expect(find.text('设备验收任务'), findsOneWidget);
      expect(find.text('国策状态'), findsOneWidget);
      expect(find.text('点亮 0 · 待今日确认 1 · 熄灭 0'), findsOneWidget);
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
      await tester.ensureVisible(find.text('打开国策树'));
      await tester.tap(find.text('打开国策树'));
      await tester.pumpAndSettle();
      expect(find.text('确认节点今日继续有效，并查看连续记录与内化进度。'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    }
  });

  testWidgets('T25 安卓设备管理员密码重置表单可确认并完成', (tester) async {
    final repository = FakeAuthRepository()
      ..signedInUser = 'admin@example.invalid'
      ..administrator = true;

    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('管理员：重置用户密码'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('reset-target-email')));
    await tester.enterText(
      find.byKey(const Key('reset-target-email')),
      'ticket-25-user@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('reset-new-password')),
      'device-test-password',
    );
    await tester.enterText(
      find.byKey(const Key('reset-confirm-password')),
      'device-test-password',
    );
    await tester.ensureVisible(
      find.byKey(const Key('manual-verification-confirmation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual-verification-confirmation')));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '重置密码'));
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pumpAndSettle();

    expect(repository.passwordResetEmail, 'ticket-25-user@example.invalid');
    expect(repository.passwordResetManualVerificationConfirmed, isTrue);
    expect(find.textContaining('密码已重置'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'device-test-password',
      ),
      findsNothing,
    );
  });

  testWidgets('T26 安卓设备管理员可停用并恢复用户且保留数据说明', (tester) async {
    final repository = FakeAuthRepository()
      ..managedUsers = [
        ManagedUserLifecycle(
          userId: 'ticket-26-device-user',
          email: 'ticket-26-user@example.invalid',
          createdAt: DateTime.utc(2026, 9, 1),
          isSuspended: false,
          isEligibleForPurge: false,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminUserLifecycleCard(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('本界面不会清除数据'), findsOneWidget);
    await tester.tap(find.text('停用'));
    await tester.pumpAndSettle();
    expect(repository.suspendedUserIds, contains('ticket-26-device-user'));
    expect(find.textContaining('已停用 ·'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(repository.restoredUserIds, contains('ticket-26-device-user'));
    expect(find.textContaining('正常用户'), findsOneWidget);
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
