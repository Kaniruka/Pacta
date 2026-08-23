import 'package:flutter/material.dart';

@immutable
class ChainColors extends ThemeExtension<ChainColors> {
  const ChainColors({
    required this.focus,
    required this.nationalFocus,
    required this.warning,
    required this.canvas,
  });

  final Color focus;
  final Color nationalFocus;
  final Color warning;
  final Color canvas;

  static const light = ChainColors(
    focus: Color(0xFF246BFD),
    nationalFocus: Color(0xFF168B72),
    warning: Color(0xFFE47B28),
    canvas: Color(0xFFF7F7F2),
  );

  @override
  ChainColors copyWith({
    Color? focus,
    Color? nationalFocus,
    Color? warning,
    Color? canvas,
  }) {
    return ChainColors(
      focus: focus ?? this.focus,
      nationalFocus: nationalFocus ?? this.nationalFocus,
      warning: warning ?? this.warning,
      canvas: canvas ?? this.canvas,
    );
  }

  @override
  ChainColors lerp(ChainColors? other, double t) {
    if (other is! ChainColors) return this;
    return ChainColors(
      focus: Color.lerp(focus, other.focus, t)!,
      nationalFocus: Color.lerp(nationalFocus, other.nationalFocus, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
    );
  }
}

ThemeData buildChainTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ChainColors.light.focus,
    brightness: Brightness.light,
    surface: ChainColors.light.canvas,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ChainColors.light.canvas,
    extensions: const [ChainColors.light],
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}
