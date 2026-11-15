import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_ui_composite_scenarios.dart';

/// 07 计划 UI 组合夹具：进程内 `flutter test` 入口。
///
/// 四个场景的实现与 `integration_test/plan_ui_composite_device_test.dart` 完全
/// 共用（[runUnsupportedCalendarScenario] 等）。这里产出的是 **widget 证据**：
/// manifest 的 `scope` 是 `widget`，用于守住行为与布局回归；Windows 原生
/// 验收必须由 integration_test 的 `native` 证据承担，两者不能互相冒充。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontLoader = FontLoader('MiSans')
    ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));

  setUpAll(() async {
    await fontLoader.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'Etc/UTC' : null,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  /// 每次运行一个唯一、绝对、空的目录；场景各自的子目录由夹具创建。
  Directory runDirectory() => Directory(
    '${Directory.systemTemp.path}/pacta-plan-ui-widget-'
    '${DateTime.now().microsecondsSinceEpoch}',
  );

  testWidgets('Windows 无系统日历：导入说明可读，自有安排仍可增改', (tester) async {
    final fixture = PlanUiCompositeFixture.open(
      scenario: 'calendar-unsupported-dark-narrow',
      runDirectory: runDirectory(),
      scope: PlanUiScope.widget,
    );
    try {
      expect(fixture.directory.isAbsolute, isTrue);
      expect(fixture.directory.existsSync(), isTrue);
      await runUnsupportedCalendarScenario(tester, fixture);
      expect(
        File('${fixture.directory.path}/manifest.json').existsSync(),
        isTrue,
        reason: 'widget 证据只写 manifest（PNG 由 native 入口产出）',
      );
      expect(fixture.screenshots, isEmpty, reason: 'widget 入口不冒充原生截图');
      expect(fixture.layout?['measuredBrightness'], 'dark');
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('账号时区决定 Plan 时间；另一台设备先写入时采用最新值', (tester) async {
    final fixture = PlanUiCompositeFixture.open(
      scenario: 'profile-zone-conflict-light-wide',
      runDirectory: runDirectory(),
      scope: PlanUiScope.widget,
    );
    try {
      await runAccountZoneScenario(tester, fixture);
      expect(fixture.layout?['measuredBrightness'], 'light');
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('重复创建可改范围，提醒配置在重开后保留', (tester) async {
    final fixture = PlanUiCompositeFixture.open(
      scenario: 'recurrence-scopes-light-wide',
      runDirectory: runDirectory(),
      scope: PlanUiScope.widget,
    );
    try {
      await runRecurrenceScenario(tester, fixture);
      expect(fixture.assertions, contains('reminder-template'));
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('预约准备 5/10/15/自定义可用，准备结束只交接一次', (tester) async {
    final fixture = PlanUiCompositeFixture.open(
      scenario: 'preparation-handoff-light-wide',
      runDirectory: runDirectory(),
      scope: PlanUiScope.widget,
    );
    try {
      await runPreparationScenario(tester, fixture);
      expect(fixture.assertions, contains('single-handoff'));
    } finally {
      await fixture.dispose(tester);
    }
  });
}
