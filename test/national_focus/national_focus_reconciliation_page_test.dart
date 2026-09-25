import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_reconciliation_page.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';

void main() {
  testWidgets('展示完整来源与影响并将所选完整分支交给仓储', (tester) async {
    final repository = _ReviewRepository(_conflictState());
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusReconciliationPage(repository: repository),
      ),
    );
    await _pumpUi(tester);

    expect(find.text('涉及节点：晨间计划、阅读计划'), findsOneWidget);
    expect(find.textContaining('成功日 1→2'), findsWidgets);
    expect(find.text('查看完整来源操作'), findsNWidgets(2));
    await tester.tap(find.text('查看完整来源操作').first);
    await _pumpUi(tester);
    expect(find.text('调整父子关系'), findsOneWidget);
    expect(find.textContaining('· 平板'), findsWidgets);

    final selectedSource =
        repository.review.reconciliationCases.single.options.first.sourceId;
    await tester.tap(find.byType(RadioListTile<String>).first);
    await _pumpUi(tester);
    final adoptButton = find.text('采用此完整分支');
    await tester.ensureVisible(adoptButton);
    await tester.pump();
    await tester.tap(adoptButton);
    await _pumpUi(tester);

    expect(repository.resolvedCaseId, 'review-1');
    expect(repository.resolvedSourceId, selectedSource);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

NationalFocusReviewState _conflictState() {
  final occurredAt = DateTime.utc(2026, 9, 21, 19);
  final firstEffect = NationalFocusReconciliationCardEffect(
    cardId: 'child',
    triggerCondition: '阅读计划',
    previousState: 'lit',
    newState: 'lit',
    previousParentId: null,
    newParentId: 'parent',
    previousIsInTree: true,
    newIsInTree: true,
    previousSuccessfulDays: 1,
    newSuccessfulDays: 2,
    previousCurrentConsecutiveDays: 1,
    newCurrentConsecutiveDays: 2,
  );
  final secondEffect = NationalFocusReconciliationCardEffect(
    cardId: 'parent',
    triggerCondition: '晨间计划',
    previousState: 'lit',
    newState: 'lit',
    previousParentId: null,
    newParentId: 'child',
    previousIsInTree: true,
    newIsInTree: true,
    previousSuccessfulDays: 3,
    newSuccessfulDays: 4,
    previousCurrentConsecutiveDays: 3,
    newCurrentConsecutiveDays: 4,
  );
  NationalFocusReconciliationOption option(
    String sourceId,
    String deviceId,
    NationalFocusReconciliationCardEffect effect,
  ) {
    return NationalFocusReconciliationOption(
      sourceId: sourceId,
      effects: [effect],
      operations: [
        NationalFocusReconciliationOperation(
          sourceId: sourceId,
          deviceId: deviceId,
          operation: 'place_card',
          occurredAt: occurredAt,
          effects: [effect],
        ),
      ],
    );
  }

  return NationalFocusReviewState(
    reconciliationCases: [
      NationalFocusReconciliationCase(
        id: 'review-1',
        createdAt: occurredAt,
        cardIds: const ['parent', 'child'],
        cardNames: const {'parent': '晨间计划', 'child': '阅读计划'},
        options: [
          option('source-a', '平板', firstEffect),
          option('source-b', '手机', secondEffect),
        ],
      ),
    ],
  );
}

class _ReviewRepository extends UnavailableNationalFocusRepository {
  _ReviewRepository(this.review);

  final NationalFocusReviewState review;
  String? resolvedCaseId;
  String? resolvedSourceId;

  @override
  Stream<NationalFocusReviewState> watchNationalFocusReviewState() =>
      Stream.value(review);

  @override
  Future<void> resolveNationalFocusReconciliation({
    required String caseId,
    required String selectedSourceId,
  }) async {
    resolvedCaseId = caseId;
    resolvedSourceId = selectedSourceId;
  }
}
