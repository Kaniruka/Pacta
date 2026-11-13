import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';

NationalFocusCard cardWithSuccessfulDays(int days) => NationalFocusCard(
  id: 'card',
  name: '晨光校准',
  triggerCondition: '',
  action: '打开床边灯',
  isInTree: false,
  state: NationalFocusCardState.extinguished,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  successfulDays: days,
);

void main() {
  test('显示四舍五入为100%不能提前计为已内化', () {
    final almost = cardWithSuccessfulDays(179);
    expect(almost.internalizationProgress.toStringAsFixed(0), '100');
    expect(almost.isInternalized, isFalse);
    expect(cardWithSuccessfulDays(180).isInternalized, isTrue);
    expect(cardWithSuccessfulDays(365).isInternalized, isTrue);
  });

  test('累计成功180天达到内化终点，熄灭及入库不改变判定', () {
    expect(cardWithSuccessfulDays(0).internalizationProgress, 0);
    expect(
      cardWithSuccessfulDays(60).internalizationProgress,
      closeTo(66.524, 0.001),
    );
    expect(cardWithSuccessfulDays(179).internalizationProgress, lessThan(100));
    expect(cardWithSuccessfulDays(180).internalizationProgress, 100);
    expect(cardWithSuccessfulDays(365).internalizationProgress, 100);
  });
}
