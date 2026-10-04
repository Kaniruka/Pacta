import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('亮暗主题正文与主要操作达到4.5对比度', (tester) async {
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpWidget(PactaApp(authRepository: auth));
      await tester.pumpAndSettle();
      final colors = Theme.of(tester.element(find.text('今天先做什么'))).colorScheme;
      for (final pair in [
        (colors.onSurface, colors.surface),
        (colors.onSurfaceVariant, colors.surface),
        (colors.onPrimary, colors.primary),
      ]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('窄屏大字可访问四个入口且页面不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();
    for (final label in ['看板', '专注链', '我的', '国策树']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('宽屏以侧边导航访问页面并跟随系统深色', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final auth = FakeAuthRepository()..signedInUser = 'layout-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('layout-user'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('layout-user'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
