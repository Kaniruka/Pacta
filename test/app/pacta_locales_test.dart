import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/app/pacta_locales.dart';

import '../support/fake_auth_repository.dart';

/// Flutter 3.47.2 的 zh-Hant 文案是「複製 / 貼上 / 剪下 / 全部選取」；
/// 「全選」只出现在 zh-Hant-TW 的区域覆写里，本应用统一解析为不带区域的
/// zh-Hant，所以繁体断言取「全部選取」。
const String kHantSelectAllLabel = '全部選取';

MaterialLocalizations _localizations(WidgetTester tester) =>
    MaterialLocalizations.of(tester.element(find.byType(AuthScreen)));

Future<void> _pumpPactaApp(WidgetTester tester, {Locale? locale}) async {
  await tester.pumpWidget(
    PactaApp(authRepository: FakeAuthRepository(), locale: locale),
  );
  await tester.pumpAndSettle();
}

void _setSystemLocales(WidgetTester tester, List<Locale> locales) {
  tester.platformDispatcher.localesTestValue = locales;
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

void _expectSelectionLabels(
  MaterialLocalizations localizations, {
  required String copy,
  required String paste,
  required String cut,
  required String selectAll,
}) {
  expect(localizations.copyButtonLabel, copy);
  expect(localizations.pasteButtonLabel, paste);
  expect(localizations.cutButtonLabel, cut);
  expect(localizations.selectAllButtonLabel, selectAll);
}

void main() {
  group('resolvePactaLocaleList', () {
    test('简体区域、Hans 脚本与裸 zh 都解析为简体中文', () {
      for (final Locale locale in <Locale>[
        const Locale('zh', 'CN'),
        const Locale('zh', 'SG'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        const Locale('zh'),
      ]) {
        expect(
          resolvePactaLocaleList(<Locale>[locale], pactaSupportedLocales),
          pactaSimplifiedChineseLocale,
          reason: '$locale 应落到简体中文',
        );
      }
    });

    test('繁体区域与 Hant 脚本都解析为繁体中文', () {
      for (final Locale locale in <Locale>[
        const Locale('zh', 'TW'),
        const Locale('zh', 'HK'),
        const Locale('zh', 'MO'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]) {
        expect(
          resolvePactaLocaleList(<Locale>[locale], pactaSupportedLocales),
          pactaTraditionalChineseLocale,
          reason: '$locale 应落到繁体中文',
        );
      }
    });

    test('英文与英文区域解析为英文', () {
      for (final Locale locale in <Locale>[
        const Locale('en'),
        const Locale('en', 'US'),
        const Locale('en', 'GB'),
      ]) {
        expect(
          resolvePactaLocaleList(<Locale>[locale], pactaSupportedLocales),
          pactaEnglishLocale,
          reason: '$locale 应落到英文',
        );
      }
    });

    test('多语言列表按首选顺序命中第一个可支持语种', () {
      expect(
        resolvePactaLocaleList(<Locale>[
          const Locale('ja', 'JP'),
          const Locale('zh', 'TW'),
          const Locale('en', 'US'),
        ], pactaSupportedLocales),
        pactaTraditionalChineseLocale,
      );
      expect(
        resolvePactaLocaleList(<Locale>[
          const Locale('fr', 'FR'),
          const Locale('en', 'GB'),
        ], pactaSupportedLocales),
        pactaEnglishLocale,
      );
      expect(
        resolvePactaLocaleList(<Locale>[
          const Locale('ja', 'JP'),
          const Locale('de', 'DE'),
        ], pactaSupportedLocales),
        pactaSimplifiedChineseLocale,
      );
    });

    test('空列表与 null 回退简体中文', () {
      expect(
        resolvePactaLocaleList(const <Locale>[], pactaSupportedLocales),
        pactaSimplifiedChineseLocale,
      );
      expect(
        resolvePactaLocaleList(null, pactaSupportedLocales),
        pactaSimplifiedChineseLocale,
      );
    });

    test('解析结果始终落在支持的三种语言内', () {
      for (final List<Locale> locales in <List<Locale>>[
        <Locale>[const Locale('zh', 'TW')],
        <Locale>[const Locale('zh', 'CN')],
        <Locale>[const Locale('en', 'GB')],
        const <Locale>[],
      ]) {
        expect(
          pactaSupportedLocales,
          contains(resolvePactaLocaleList(locales, pactaSupportedLocales)),
        );
      }
    });
  });

  group('resolvePactaLocale', () {
    test('单语言委托与单元素列表结果一致', () {
      expect(
        resolvePactaLocale(const Locale('zh', 'TW'), pactaSupportedLocales),
        pactaTraditionalChineseLocale,
      );
      expect(
        resolvePactaLocale(const Locale('zh', 'CN'), pactaSupportedLocales),
        pactaSimplifiedChineseLocale,
      );
      expect(
        resolvePactaLocale(const Locale('en', 'US'), pactaSupportedLocales),
        pactaEnglishLocale,
      );
      expect(
        resolvePactaLocale(null, pactaSupportedLocales),
        pactaSimplifiedChineseLocale,
      );
    });
  });

  group('PactaApp 系统级本地化', () {
    testWidgets('系统首选 zh_CN 时选字菜单为简体中文', (tester) async {
      _setSystemLocales(tester, <Locale>[const Locale('zh', 'CN')]);
      await _pumpPactaApp(tester);

      _expectSelectionLabels(
        _localizations(tester),
        copy: '复制',
        paste: '粘贴',
        cut: '剪切',
        selectAll: '全选',
      );
    });

    testWidgets('系统首选 zh_TW 时选字菜单为繁体中文', (tester) async {
      _setSystemLocales(tester, <Locale>[const Locale('zh', 'TW')]);
      await _pumpPactaApp(tester);

      _expectSelectionLabels(
        _localizations(tester),
        copy: '複製',
        paste: '貼上',
        cut: '剪下',
        selectAll: kHantSelectAllLabel,
      );
    });

    testWidgets('系统首选 en_US 时选字菜单为英文', (tester) async {
      _setSystemLocales(tester, <Locale>[const Locale('en', 'US')]);
      await _pumpPactaApp(tester);

      _expectSelectionLabels(
        _localizations(tester),
        copy: 'Copy',
        paste: 'Paste',
        cut: 'Cut',
        selectAll: 'Select all',
      );
    });

    testWidgets('显式 locale zh_CN 覆盖英文系统语言', (tester) async {
      _setSystemLocales(tester, <Locale>[const Locale('en', 'US')]);
      await _pumpPactaApp(tester, locale: const Locale('zh', 'CN'));

      _expectSelectionLabels(
        _localizations(tester),
        copy: '复制',
        paste: '粘贴',
        cut: '剪切',
        selectAll: '全选',
      );
    });

    testWidgets('显式 locale zh_TW 覆盖简体系统语言', (tester) async {
      _setSystemLocales(tester, <Locale>[const Locale('zh', 'CN')]);
      await _pumpPactaApp(tester, locale: const Locale('zh', 'TW'));

      _expectSelectionLabels(
        _localizations(tester),
        copy: '複製',
        paste: '貼上',
        cut: '剪下',
        selectAll: kHantSelectAllLabel,
      );
    });

    testWidgets('显式 locale en_US 覆盖简体系统语言', (tester) async {
      _setSystemLocales(tester, <Locale>[const Locale('zh', 'CN')]);
      await _pumpPactaApp(tester, locale: const Locale('en', 'US'));

      _expectSelectionLabels(
        _localizations(tester),
        copy: 'Copy',
        paste: 'Paste',
        cut: 'Cut',
        selectAll: 'Select all',
      );
    });
  });
}
