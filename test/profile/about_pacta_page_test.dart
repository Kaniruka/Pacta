import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/profile/about_pacta_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('关于页展示版本、理论出处与字体／许可入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: const AboutPactaPage(),
      ),
    );
    await tester.pumpAndSettle();

    // 版本胶囊与 pubspec 同源：单一常量同时喂给版本胶囊与许可页。
    expect(find.text('v0.4.0+5'), findsOneWidget);
    expect(find.byKey(const ValueKey('about-version-pill')), findsOneWidget);
    expect(find.text('Pacta'), findsOneWidget);
    expect(find.text('理论出处'), findsOneWidget);
    expect(find.text('知乎原回答'), findsOneWidget);
    expect(find.text('字体与开源许可'), findsOneWidget);
    // 出处链接与 GitHub 项目地址完整可见。
    expect(find.text(pactaTheorySourceUrl), findsOneWidget);
    expect(find.text('GitHub 项目主页'), findsOneWidget);
    expect(find.text(pactaGithubRepoUrl), findsOneWidget);
    expect(find.text('小米 MiSans 字体'), findsOneWidget);
    expect(find.byKey(const ValueKey('about-license-entry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击出处链接与 GitHub 项目主页直接跳转外部浏览器，失败时提示', (tester) async {
    final launchedUris = <Uri>[];
    var shouldSucceed = true;

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: AboutPactaPage(
          launchExternalUrl: (uri) async {
            launchedUris.add(uri);
            return shouldSucceed;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about-theory-source-entry')));
    await tester.pumpAndSettle();
    expect(launchedUris, [Uri.parse(pactaTheorySourceUrl)]);

    await tester.tap(find.byKey(const ValueKey('about-github-repo-entry')));
    await tester.pumpAndSettle();
    expect(launchedUris, [
      Uri.parse(pactaTheorySourceUrl),
      Uri.parse(pactaGithubRepoUrl),
    ]);

    shouldSucceed = false;
    await tester.tap(find.byKey(const ValueKey('about-github-repo-entry')));
    await tester.pumpAndSettle();
    expect(find.text('无法打开浏览器，请检查系统默认浏览器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开源许可入口打开 LicensePage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: const AboutPactaPage(),
      ),
    );
    await tester.pumpAndSettle();

    final licenseEntry = find.byKey(const ValueKey('about-license-entry'));
    await tester.ensureVisible(licenseEntry);
    await tester.pumpAndSettle();
    await tester.tap(licenseEntry);
    // LicensePage 加载许可时一直有一枚进度指示器，pumpAndSettle 永远等不到
    // 静止，因此只推进路由动画。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(LicensePage), findsOneWidget);
    final page = tester.widget<LicensePage>(find.byType(LicensePage));
    expect(page.applicationName, 'Pacta');
    expect(page.applicationVersion, '0.4.0+5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的页不再常驻退出登录，改为关于 Pacta 入口', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      PactaApp(authRepository: FakeAuthRepository()..signedInUser = 'about-me'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MyPage), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);

    final entry = find.byKey(const ValueKey('my-about-entry'));
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find
          .descendant(
            of: find.byType(MyPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(AboutPactaPage), findsOneWidget);
    expect(find.text('v0.4.0+5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('pactaAppVersion 与 pubspec.yaml 的 version 唯一真源一致', () {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);
    final match = RegExp(
      r'^version:\s*([^\s#]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    expect(match?.group(1), pactaAppVersion);
  });

  group('版本同步机械守卫', () {
    const pubspec = 'name: pacta\nversion: 9.8.7+6\n';
    const runnerRc = '''
#define VERSION_AS_NUMBER 9,8,7,6
#define VERSION_AS_STRING "9.8.7+6"
''';
    const pactaIss = '#define MyAppVersion "9.8.7"';
    const readme = 'version-9.8.7%2B6-blue';
    const readmeEn = 'version-9.8.7%2B6-blue';
    const appVersion = '9.8.7+6';

    test('有效样本零违规，破坏任一同步点各自产生可区分的违规', () {
      expect(
        _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc,
          pactaIssContent: pactaIss,
          readmeContent: readme,
          readmeEnContent: readmeEn,
          appVersion: appVersion,
        ),
        isEmpty,
      );

      final mutations = <String, List<String>>{
        'appVersion': _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc,
          pactaIssContent: pactaIss,
          readmeContent: readme,
          readmeEnContent: readmeEn,
          appVersion: '9.8.7+5',
        ),
        'VERSION_AS_NUMBER': _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc.replaceFirst('9,8,7,6', '9,8,7,5'),
          pactaIssContent: pactaIss,
          readmeContent: readme,
          readmeEnContent: readmeEn,
          appVersion: appVersion,
        ),
        'VERSION_AS_STRING': _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc.replaceFirst(
            'VERSION_AS_STRING "9.8.7+6"',
            'VERSION_AS_STRING "9.8.7+5"',
          ),
          pactaIssContent: pactaIss,
          readmeContent: readme,
          readmeEnContent: readmeEn,
          appVersion: appVersion,
        ),
        'MyAppVersion': _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc,
          pactaIssContent: pactaIss.replaceFirst('9.8.7', '9.8.6'),
          readmeContent: readme,
          readmeEnContent: readmeEn,
          appVersion: appVersion,
        ),
        'README.md badge': _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc,
          pactaIssContent: pactaIss,
          readmeContent: readme.replaceFirst('9.8.7', '9.8.6'),
          readmeEnContent: readmeEn,
          appVersion: appVersion,
        ),
        'README.en.md badge': _findVersionSyncViolations(
          pubspecContent: pubspec,
          runnerRcContent: runnerRc,
          pactaIssContent: pactaIss,
          readmeContent: readme,
          readmeEnContent: readmeEn.replaceFirst('9.8.7', '9.8.6'),
          appVersion: appVersion,
        ),
      };

      for (final entry in mutations.entries) {
        expect(entry.value, isNotEmpty, reason: '破坏 ${entry.key} 后必须报告版本漂移');
      }
      expect(
        mutations.values.map((violations) => violations.single).toSet(),
        hasLength(mutations.length),
        reason: '每个同步点缺失都必须给出可区分的违规文本',
      );
    });

    test('真实仓库的版本同步点全部一致', () {
      final pubspecFile = File('pubspec.yaml');
      final runnerRcFile = File('windows/runner/Runner.rc');
      final pactaIssFile = File('windows/packaging/pacta.iss');
      final readmeFile = File('README.md');
      final readmeEnFile = File('README.en.md');
      for (final file in <File>[
        pubspecFile,
        runnerRcFile,
        pactaIssFile,
        readmeFile,
        readmeEnFile,
      ]) {
        expect(file.existsSync(), isTrue, reason: '缺少同步源文件 ${file.path}');
      }

      final violations = _findVersionSyncViolations(
        pubspecContent: pubspecFile.readAsStringSync(),
        runnerRcContent: runnerRcFile.readAsStringSync(),
        pactaIssContent: pactaIssFile.readAsStringSync(),
        readmeContent: readmeFile.readAsStringSync(),
        readmeEnContent: readmeEnFile.readAsStringSync(),
        appVersion: pactaAppVersion,
      );
      expect(violations, isEmpty);
    });
  });
}

/// 版本同步机械守卫：以 pubspec.yaml 的版本为真源，逐项核对客户端常量、
/// Windows 资源回退宏、安装包展示版本与两份 README badge。
List<String> _findVersionSyncViolations({
  required String pubspecContent,
  required String runnerRcContent,
  required String pactaIssContent,
  required String readmeContent,
  required String readmeEnContent,
  required String appVersion,
}) {
  final match = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)',
    multiLine: true,
  ).firstMatch(pubspecContent);
  if (match == null) {
    return <String>['pubspec.yaml 缺少 MAJOR.MINOR.PATCH+BUILD 形式的 version'];
  }
  final major = match.group(1)!;
  final minor = match.group(2)!;
  final patch = match.group(3)!;
  final build = match.group(4)!;
  final fullVersion = '$major.$minor.$patch+$build';
  final shortVersion = '$major.$minor.$patch';
  final violations = <String>[];

  if (appVersion != fullVersion) {
    violations.add('pactaAppVersion=$appVersion 应为 $fullVersion');
  }
  if (!runnerRcContent.contains(
    '#define VERSION_AS_NUMBER $major,$minor,$patch,$build',
  )) {
    violations.add(
      'windows/runner/Runner.rc 缺少 VERSION_AS_NUMBER '
      '$major,$minor,$patch,$build',
    );
  }
  if (!runnerRcContent.contains('#define VERSION_AS_STRING "$fullVersion"')) {
    violations.add(
      'windows/runner/Runner.rc 缺少 VERSION_AS_STRING "$fullVersion"',
    );
  }
  if (!pactaIssContent.contains('#define MyAppVersion "$shortVersion"')) {
    violations.add(
      'windows/packaging/pacta.iss 的 MyAppVersion 应为 $shortVersion',
    );
  }
  final badge = 'version-$major.$minor.$patch%2B$build-blue';
  if (!readmeContent.contains(badge)) {
    violations.add('README.md 缺少 $badge badge');
  }
  if (!readmeEnContent.contains(badge)) {
    violations.add('README.en.md 缺少 $badge badge');
  }
  return violations;
}
