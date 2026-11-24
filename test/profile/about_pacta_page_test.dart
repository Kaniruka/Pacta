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
    expect(find.text('v0.3.1+4'), findsOneWidget);
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
    expect(page.applicationVersion, '0.3.1+4');
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
    expect(find.text('v0.3.1+4'), findsOneWidget);

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
}
