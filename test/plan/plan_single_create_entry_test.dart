import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// T3：日历只有一个创建入口（页头「新建安排」），空状态文案指向它。
const _user = 'plan-single-create-entry';

class _Harness {
  _Harness(this.database);

  final PactaDatabase database;
  late LocalTaskRepository tasks;
  late LocalFocusRepository focus;
  late LocalNationalFocusRepository nationalFocus;
  late LocalScheduleRepository schedules;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(411, 731),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
    focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
    );
    nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
    );
    schedules = LocalScheduleRepository(database: database, userId: _user);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => nationalFocus,
        scheduleRepositoryFactory: (_) => schedules,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    const limit = Duration(seconds: 10);
    await focus.dispose().timeout(limit, onTimeout: () {});
    await nationalFocus.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'Etc/UTC' : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  testWidgets('日历只剩页头一个创建入口，空状态指向它', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();

      expect(find.text('新建安排'), findsOneWidget, reason: '页头入口必须保留');
      expect(find.text('添加事项'), findsNothing, reason: '日区重复入口应删除');
      expect(
        find.textContaining('用上方「新建安排」添加'),
        findsOneWidget,
        reason: '空状态文案要指回页头入口',
      );
    } finally {
      await harness.dispose(tester);
    }
  });
}
