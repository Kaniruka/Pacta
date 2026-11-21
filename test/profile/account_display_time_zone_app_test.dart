import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

/// 账号资料存储的内存替身：按用户隔离；时区初始化与真实 RPC 一致，只更新已
/// 有资料行，不为"还没有资料"的账号伪造昵称。
class _MemoryProfileRemote implements ProfileRemote {
  final Map<String, RemoteProfile> stored = {};
  Completer<RemoteProfile?>? fetchGate;
  int initializeCalls = 0;
  int saveCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async {
    final gate = fetchGate;
    if (gate != null) return gate.future.then((_) => stored[userId]);
    return stored[userId];
  }

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
    int? timeZoneRevision,
  }) async {
    saveCalls++;
    final previous = stored[userId];
    final saved = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
      displayTimeZoneId: displayTimeZoneId ?? previous?.displayTimeZoneId,
    );
    stored[userId] = saved;
    return saved;
  }

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) async {
    initializeCalls++;
    final previous = stored[userId];
    // 与账号存储一致：没有资料行时插入空昵称行（昵称未设置，不是伪造昵称），
    // 这样时区可以先于昵称存在；已有昵称/头像不动，已有值不被覆盖。
    if (previous == null) {
      return stored[userId] = RemoteProfile(
        displayName: '',
        avatar: null,
        updatedAt: DateTime.now().toUtc(),
        displayTimeZoneId: displayTimeZoneId,
      );
    }
    if (previous.displayTimeZoneId != null) return previous;
    return stored[userId] = RemoteProfile(
      displayName: previous.displayName,
      avatar: previous.avatar,
      updatedAt: DateTime.now().toUtc(),
      displayTimeZoneId: displayTimeZoneId,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
  });

  late PactaDatabase database;
  late DateTime now;
  late _MemoryProfileRemote remote;
  late LocalTaskRepository tasks;
  late LocalFocusRepository focus;
  late LocalNationalFocusRepository tree;
  late LocalProfileRepository profile;

  // 2026-09-22 15:50Z 起的 30 分钟：UTC/伦敦(+1) 都落在 9/22，
  // 东京(+9) 整段落在 9/23。
  final start = DateTime.utc(2026, 9, 22, 15, 50);

  setUp(() async {
    database = PactaDatabase(NativeDatabase.memory());
    remote = _MemoryProfileRemote();
    now = start;
    tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    tree = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      cloudSyncEnabled: false,
      now: () => now,
    );
    profile = LocalProfileRepository(
      database: database,
      userId: 'user-a',
      remote: remote,
      now: () => now,
    );
    await _seedSession(
      tasks: tasks,
      focus: focus,
      advance: (d) => now = now.add(d),
    );
  });

  tearDown(() async {
    // 仓储由 ProviderScope 在卸载时释放；这里只关闭数据库，避免重复 close
    // 一个还有暂停监听者的广播流而卡住收尾。
    await database.close();
  });

  Widget buildApp({
    String userId = 'user-a',
    required String deviceTimeZoneId,
    LocalTaskRepository? taskRepository,
    LocalFocusRepository? focusRepository,
    LocalNationalFocusRepository? nationalFocusRepository,
    LocalProfileRepository? profileRepository,
  }) => PactaApp(
    authRepository: FakeAuthRepository()..signedInUser = userId,
    taskRepositoryFactory: (_) => taskRepository ?? tasks,
    focusRepositoryFactory: (_) => focusRepository ?? focus,
    nationalFocusRepositoryFactory: (_) => nationalFocusRepository ?? tree,
    profileRepositoryFactory: (_) => profileRepository ?? profile,
    deviceTimeZoneIdReader: () async => deviceTimeZoneId,
    // 看板"今天"与热力月历共用 displayClock：不注入就会落到系统真实月份，
    // 9 月的日期格根本不存在。
    displayClock: () => now,
  );

  testWidgets('账号还没有时区时按统一 fallback 显示，迁移只写入一次设备时区', (tester) async {
    // 账号已有资料（昵称），但还没有时区。
    remote.stored['user-a'] = RemoteProfile(
      displayName: '小林',
      avatar: null,
      updatedAt: start,
    );
    final gate = Completer<RemoteProfile?>();
    remote.fetchGate = gate;

    await tester.pumpWidget(buildApp(deviceTimeZoneId: 'Asia/Tokyo'));
    await tester.pump();

    // 迁移未完成：显示按固定 fallback（UTC）分摊，而不是设备时区；整段
    // 30 分钟落在 9/22，9/23 的有效专注仍为 0。
    await expectDayValue(tester, 22, '30分00秒');
    await expectDayValue(tester, 23, '0分00秒');

    gate.complete(null);
    remote.fetchGate = null;
    await pumpBoard(tester);

    // 首次迁移把设备时区作为一次性输入写成账号值。
    expect(remote.initializeCalls, 1);
    expect(remote.stored['user-a']?.displayTimeZoneId, 'Asia/Tokyo');
    expect(remote.stored['user-a']?.displayName, '小林');
    final migrated = await tester.runAsync(() => profile.getProfile());
    expect(migrated?.displayTimeZoneId, 'Asia/Tokyo');
    await expectDayValue(tester, 23, '30分00秒');
    await expectDayValue(tester, 22, '0分00秒');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('账号已有值时按账号值显示，设备时区不再参与', (tester) async {
    remote.stored['user-a'] = RemoteProfile(
      displayName: '小林',
      avatar: null,
      updatedAt: start,
      displayTimeZoneId: 'Asia/Tokyo',
    );

    await tester.pumpWidget(buildApp(deviceTimeZoneId: 'America/Los_Angeles'));
    await pumpBoard(tester);

    await expectDayValue(tester, 23, '30分00秒');
    await expectDayValue(tester, 22, '0分00秒');
    final cached = await tester.runAsync(() => profile.getProfile());
    expect(cached?.displayTimeZoneId, 'Asia/Tokyo');
    expect(remote.initializeCalls, 0, reason: '已有账号值时不得再写入种子');
    expect(remote.saveCalls, 0);
    expect(remote.stored['user-a']?.displayTimeZoneId, 'Asia/Tokyo');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('账号还没有资料时只写空昵称与时区，不伪造昵称', (tester) async {
    await tester.pumpWidget(buildApp(deviceTimeZoneId: 'Asia/Tokyo'));
    await pumpBoard(tester);

    expect(remote.initializeCalls, greaterThan(0));
    expect(remote.saveCalls, 0, reason: '迁移不得走普通资料保存');
    final initialized = remote.stored['user-a'];
    expect(initialized, isNotNull, reason: '时区可以先于昵称存在');
    expect(initialized!.displayName, isEmpty, reason: '不得伪造昵称');
    expect(initialized.displayTimeZoneId, 'Asia/Tokyo');
    final cached = await tester.runAsync(() => profile.getProfile());
    expect(cached?.displayName, isEmpty);
    expect(cached?.effectiveDisplayName, '当前用户');
    expect(cached?.displayTimeZoneId, 'Asia/Tokyo');

    // 有账号值后按东京分摊：整段落在 9/23。
    await expectDayValue(tester, 23, '30分00秒');
    await expectDayValue(tester, 22, '0分00秒');

    // 昵称未设置时，"我的"仍显示占位称呼而不是空白。
    await tester.tap(find.text('我的'));
    await pumpBoard(tester);
    expect(find.text('当前用户'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('没有昵称的账号可以只在修改资料里改时区', (tester) async {
    await tester.pumpWidget(buildApp(deviceTimeZoneId: 'Asia/Tokyo'));
    await pumpBoard(tester);
    // 初始化已经用空昵称建好账号行，账号值是设备时区的一次性迁移。
    expect(remote.stored['user-a']?.displayName, isEmpty);

    await tester.tap(find.text('我的'));
    await pumpBoard(tester);
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();

    // 不输入昵称，只选择另一个城市并保存。
    await tester.tap(find.text('新加坡'));
    await tester.pump();
    expect(find.textContaining('新加坡 · Asia/Singapore'), findsOneWidget);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await pumpBoard(tester);

    final stored = remote.stored['user-a'];
    expect(stored?.displayName, isEmpty, reason: '时区保存不得伪造昵称');
    expect(stored?.displayTimeZoneId, 'Asia/Singapore');
    final cached = await tester.runAsync(() => profile.getProfile());
    expect(cached?.displayName, isEmpty);
    expect(cached?.displayTimeZoneId, 'Asia/Singapore');
    expect(cached?.syncError, isNull);

    // 返回看板：按新加坡（UTC+8）分摊，9/22 有 10 分钟、9/23 有 20 分钟。
    await tester.tap(find.text('看板'));
    await pumpBoard(tester);
    await expectDayValue(tester, 23, '20分00秒');
    await expectDayValue(tester, 22, '10分00秒');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('切换账号后显示该账号的时区，不沿用上一账号的值', (tester) async {
    remote.stored['user-a'] = RemoteProfile(
      displayName: '甲',
      avatar: null,
      updatedAt: start,
      displayTimeZoneId: 'Asia/Tokyo',
    );
    remote.stored['user-b'] = RemoteProfile(
      displayName: '乙',
      avatar: null,
      updatedAt: start,
      displayTimeZoneId: 'Europe/London',
    );

    var secondaryNow = start;
    final tasksB = LocalTaskRepository(
      database: database,
      userId: 'user-b',
      remote: InMemoryTaskRemote(),
      now: () => secondaryNow,
    );
    final focusB = LocalFocusRepository(
      database: database,
      userId: 'user-b',
      remote: InMemoryFocusRemote(),
      now: () => secondaryNow,
    );
    await _seedSession(
      tasks: tasksB,
      focus: focusB,
      advance: (d) => secondaryNow = secondaryNow.add(d),
    );
    final profileB = LocalProfileRepository(
      database: database,
      userId: 'user-b',
      remote: remote,
      now: () => secondaryNow,
    );

    await tester.pumpWidget(buildApp(deviceTimeZoneId: 'Asia/Tokyo'));
    await pumpBoard(tester);
    await expectDayValue(tester, 23, '30分00秒');

    await tester.pumpWidget(
      buildApp(
        userId: 'user-b',
        deviceTimeZoneId: 'Asia/Tokyo',
        taskRepository: tasksB,
        focusRepository: focusB,
        profileRepository: profileB,
      ),
    );
    await pumpBoard(tester);
    await expectDayValue(tester, 22, '30分00秒');
    // 伦敦此时仍是 9/22：整段落在 9/22，9/23 的有效专注为 0。
    await expectDayValue(tester, 23, '0分00秒');
    expect(remote.stored['user-a']?.displayTimeZoneId, 'Asia/Tokyo');
    expect(remote.stored['user-b']?.displayTimeZoneId, 'Europe/London');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

/// 可见证据：点选热力月历中的某一天后，日期详情显示的有效专注时长。
///
/// 看板已把"近期专注活动"列表融合成一张热力月历，日期时长不再以列表行呈现，
/// 而是落在同卡片的「日期详情」里；这里只读页面文字，不依赖无障碍语义。
Future<void> expectDayValue(
  WidgetTester tester,
  int day,
  String duration,
) async {
  final cell = find.byKey(ValueKey('board-focus-day-$day'));
  if (cell.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      cell,
      200,
      scrollable: find
          .descendant(
            of: find.byType(BoardPage),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 40,
    );
  }
  expect(cell, findsOneWidget, reason: '9 月 $day 日应出现在热力月历里');
  await tester.ensureVisible(cell);
  // 热力月历在看板首屏之下：ensureVisible 只改滚动位置，必须再走一帧布局，
  // 点击坐标才是滚动后的真实位置。
  await tester.pump();
  await tester.tap(cell);
  await tester.pump();
  final detail = tester.widget<Text>(
    find.byKey(const ValueKey('board-focus-day-duration')),
  );
  expect(detail.data, duration, reason: '9 月 $day 日的有效专注');
}

/// 让真实数据库与流有机会推进，不依赖 pumpAndSettle（应用里有周期计时器）。
Future<void> pumpBoard(WidgetTester tester) async {
  await tester.pump();
  for (var index = 0; index < 10; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 造一条 30 分钟有效时间的失败会话：15:50Z 到 16:20Z。
Future<void> _seedSession({
  required LocalTaskRepository tasks,
  required LocalFocusRepository focus,
  required void Function(Duration) advance,
}) async {
  final goal = await tasks.createGoal(
    const GoalDraft(title: '时区验收', classification: TaskClassification.both),
  );
  final task = await tasks.createTask(
    goal.id,
    const TaskDraft(title: '跨日投入', classification: TaskClassification.both),
  );
  final session = await focus.startSession(
    taskId: task.id,
    mode: FocusChainMode.regular,
    duration: const Duration(hours: 1),
  );
  advance(const Duration(minutes: 30));
  await focus.abandonSession(sessionId: session.id, failureReason: '验收结束');
}
