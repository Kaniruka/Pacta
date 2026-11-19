import 'package:flutter/painting.dart';

/// 全站唯一字体族：不得在页面、组件或独立 TextStyle 里另起字体。
///
/// 字体文件与字重在 `pubspec.yaml` 的 `flutter.fonts` 中声明：
/// MiSans-Regular 400、MiSans-Medium 500、MiSans-Semibold 600、
/// MiSans-Bold 700。主题只通过 [family] 提供字体族，字重沿用语义字号
/// （正文 400、标题/按钮 500、需要真正层级时才用 600）。
abstract final class PactaFonts {
  static const String family = 'MiSans';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
