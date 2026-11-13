import 'package:flutter/material.dart';

/// Status feedback stays distinct from blue navigation and primary actions.
@immutable
class PactaStatusColors extends ThemeExtension<PactaStatusColors> {
  const PactaStatusColors({
    required this.successContainer,
    required this.onSuccessContainer,
  });

  static const light = PactaStatusColors(
    successContainer: Color(0xffc4eed0),
    onSuccessContainer: Color(0xff0f5223),
  );
  static const dark = PactaStatusColors(
    successContainer: Color(0xff17492e),
    onSuccessContainer: Color(0xffb5f0c6),
  );

  static PactaStatusColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PactaStatusColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  final Color successContainer;
  final Color onSuccessContainer;

  @override
  PactaStatusColors copyWith({
    Color? successContainer,
    Color? onSuccessContainer,
  }) => PactaStatusColors(
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
  );

  @override
  PactaStatusColors lerp(covariant PactaStatusColors? other, double t) {
    if (other == null) return this;
    return PactaStatusColors(
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
    );
  }
}
