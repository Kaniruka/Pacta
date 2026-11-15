import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/plan_ui_composite_scenarios.dart';

/// 运行根由入口整轮校验一次：同一个运行根要能承载多个场景，同时场景目录
/// 仍然拒绝覆盖。native 入口正是这样用一个根跑四个场景。
void main() {
  late Directory root;

  setUp(() {
    root = Directory(
      '${Directory.systemTemp.path}/pacta-plan-ui-root-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('同一个运行根可承载多个场景，重复场景拒绝覆盖', () {
    final first = PlanUiCompositeFixture.open(
      scenario: 'calendar-unsupported-dark-narrow',
      runDirectory: root,
      scope: PlanUiScope.widget,
    );
    expect(first.directory.isAbsolute, isTrue);
    // 第一个场景已经写过证据：运行根当然不再为空，第二场仍必须能打开。
    File('${first.directory.path}/manifest.json').writeAsStringSync('{}');

    final second = PlanUiCompositeFixture.open(
      scenario: 'profile-zone-conflict-light-wide',
      runDirectory: root,
      scope: PlanUiScope.native,
    );
    expect(second.directory.existsSync(), isTrue);
    expect(first.directory.existsSync(), isTrue);
    expect(
      File('${first.directory.path}/manifest.json').readAsStringSync(),
      '{}',
      reason: '后开的场景不改动前一个场景的证据',
    );

    expect(
      () => PlanUiCompositeFixture.open(
        scenario: 'calendar-unsupported-dark-narrow',
        runDirectory: root,
        scope: PlanUiScope.widget,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('场景目录已存在'),
          '拒绝覆盖同名场景目录',
        ),
      ),
    );
  });

  test('运行根必须是绝对路径', () {
    expect(
      () => PlanUiCompositeFixture.open(
        scenario: 'relative-root',
        runDirectory: Directory('relative/plan-ui-root'),
        scope: PlanUiScope.widget,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('绝对路径'),
          '相对路径直接拒绝',
        ),
      ),
    );
  });
}
