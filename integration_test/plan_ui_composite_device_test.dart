// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/plan_ui_composite_scenarios.dart';

/// 07 计划 UI 的原生入口：真实 Windows 窗口、真实 pactaTheme/MiSans、内存
/// Drift 与内存远端。四个场景与 `test/plan/windows_plan_composite_fixture_test.dart`
/// 共用同一份实现，但这里的证据 `scope=native`，并写入 PNG 与 manifest。
///
/// root 独立运行（本会话不启动 Windows GUI/native）：
///
/// ```
/// flutter test integration_test/plan_ui_composite_device_test.dart -d windows \
///   --dart-define=PACTA_PLAN_RUN_DIR=C:/abs/empty/plan-ui-run
/// ```
///
/// 运行目录必须是绝对路径且为空；每个场景写入 `<run>/<scenario>/`，同名文件
/// 一律拒绝覆盖。窗口逻辑尺寸由夹具显式设置（360×800 与 1280×900/1600），
/// 亮暗、MiSans 与实测 MediaQuery 都写进 manifest 并断言。
const _runDirDefine = String.fromEnvironment('PACTA_PLAN_RUN_DIR');

Directory _resolveRunDirectory() {
  final raw = _runDirDefine.trim();
  if (raw.isEmpty) {
    fail(
      '必须提供空的绝对运行目录：'
      '--dart-define=PACTA_PLAN_RUN_DIR=<绝对路径>',
    );
  }
  final directory = Directory(raw);
  if (!directory.isAbsolute) {
    fail('运行目录必须是绝对路径，当前为：$raw');
  }
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    fail('拒绝复用或覆盖已有证据目录：${directory.absolute.path}');
  }
  return directory;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final runDirectory = _resolveRunDirectory();

  PlanUiCompositeFixture open(String scenario) => PlanUiCompositeFixture.open(
    scenario: scenario,
    runDirectory: runDirectory,
    scope: PlanUiScope.native,
  );

  testWidgets('Windows 无系统日历：导入说明可读，自有安排仍可增改', (tester) async {
    final fixture = open('calendar-unsupported-dark-narrow');
    try {
      expect(fixture.directory.isAbsolute, isTrue);
      await runUnsupportedCalendarScenario(tester, fixture);
      expect(fixture.screenshots, isNotEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('账号时区决定 Plan 时间；另一台设备先写入时采用最新值', (tester) async {
    final fixture = open('profile-zone-conflict-light-wide');
    try {
      await runAccountZoneScenario(tester, fixture);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('重复创建可改范围，提醒配置在重开后保留', (tester) async {
    final fixture = open('recurrence-scopes-light-wide');
    try {
      await runRecurrenceScenario(tester, fixture);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('预约准备 5/10/15/自定义可用，准备结束只交接一次', (tester) async {
    final fixture = open('preparation-handoff-light-wide');
    try {
      await runPreparationScenario(tester, fixture);
    } finally {
      await fixture.dispose(tester);
    }
  });

  tearDownAll(() {
    final scenarios = [
      for (final entry in runDirectory.listSync().whereType<Directory>())
        entry.path.replaceAll('\\', '/'),
    ]..sort();
    final manifest = File('${runDirectory.path}/run.json');
    if (manifest.existsSync()) {
      fail('拒绝覆盖已有运行清单：${manifest.absolute.path}');
    }
    manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'scope': PlanUiScope.native.id,
        'scopeDescription': PlanUiScope.native.description,
        'platform': Platform.operatingSystem,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'runDirectory': runDirectory.absolute.path,
        'scenarios': scenarios,
        'isolation': {
          'database': 'in-memory',
          'remotes': 'in-memory',
          'userData': 'none',
          'systemCalendar': 'none',
          'services': 'none',
        },
      }),
      flush: true,
    );
    print('[plan-ui-native] run dir=${runDirectory.absolute.path}');
    for (final scenario in scenarios) {
      print('[plan-ui-native] $scenario');
    }
  });
}
