import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 简体中文：脚本码固定为 `Hans`，系统只给裸 `zh` 时也不会掉到英文文案。
final Locale pactaSimplifiedChineseLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
);

/// 繁体中文：脚本码固定为 `Hant`，`zh_TW` / `zh_HK` / `zh_MO` 都归到这里。
final Locale pactaTraditionalChineseLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
);

/// 英文。
const Locale pactaEnglishLocale = Locale('en');

/// 声明给 [MaterialApp.supportedLocales] 的系统级三语集合。
///
/// 只负责框架文案（长按选字菜单、日期时间选择器、Tooltip、返回键提示）；
/// 业务文案仍按现有中文硬编码维护。
final List<Locale> pactaSupportedLocales = List<Locale>.unmodifiable(<Locale>[
  pactaSimplifiedChineseLocale,
  pactaTraditionalChineseLocale,
  pactaEnglishLocale,
]);

/// Material / Widgets / Cupertino 三套框架本地化委托。
const List<LocalizationsDelegate<dynamic>> pactaLocalizationsDelegates =
    GlobalMaterialLocalizations.delegates;

const Set<String> _traditionalChineseCountryCodes = <String>{'TW', 'HK', 'MO'};

/// 按 [locales] 的首选顺序解析，结果只会是简体中文、繁体中文、英文之一。
///
/// 繁体判定只看脚本码 `Hant` 或 `TW` / `HK` / `MO` 区域；其余中文
/// （`zh`、`zh_CN`、`zh_SG`、`zh_Hans`）都归简体中文。其余语种、
/// 空列表与 `null` 统一回退简体中文。
Locale resolvePactaLocaleList(
  List<Locale>? locales,
  Iterable<Locale> supportedLocales,
) {
  for (final Locale locale in locales ?? const <Locale>[]) {
    switch (locale.languageCode.toLowerCase()) {
      case 'zh':
        final String? scriptCode = locale.scriptCode?.toLowerCase();
        final String? countryCode = locale.countryCode?.toUpperCase();
        final bool isTraditional =
            scriptCode == 'hant' ||
            (countryCode != null &&
                _traditionalChineseCountryCodes.contains(countryCode));
        return isTraditional
            ? pactaTraditionalChineseLocale
            : pactaSimplifiedChineseLocale;
      case 'en':
        return pactaEnglishLocale;
    }
  }
  return pactaSimplifiedChineseLocale;
}

/// 单语言版本的 [resolvePactaLocaleList]，供只拿到一个 [Locale] 的调用方复用。
Locale resolvePactaLocale(Locale? locale, Iterable<Locale> supportedLocales) =>
    resolvePactaLocaleList(
      locale == null ? null : <Locale>[locale],
      supportedLocales,
    );
