import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('failed record reads show retry instead of false zero streaks', (
    tester,
  ) async {
    final repository = _FailOnceFocusRepository();
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'record-read-user',
        focusRepositoryFactory: (_) => repository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('专注链'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('链记录读取失败，请重试。'), findsOneWidget);
    expect(find.text('精锐链'), findsNothing);
    expect(find.text('普通链'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(repository.chainReads, 2);
    expect(repository.appointmentReads, 2);
    expect(find.text('链记录读取失败，请重试。'), findsNothing);
    // 精锐链 7/9、普通链 0/0、预约链 4/6 以对齐表格的数字单元格呈现。
    expect(find.text('7'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _FailOnceFocusRepository extends UnavailableFocusRepository {
  int chainReads = 0;
  int appointmentReads = 0;

  @override
  Future<List<FocusChainRecord>> getChainRecords() async {
    chainReads++;
    if (chainReads == 1) throw StateError('Fixture record read failure');
    return [
      FocusChainRecord(
        mode: FocusChainMode.elite,
        currentConsecutive: 7,
        bestConsecutive: 9,
        updatedAt: DateTime.utc(2026, 10, 7),
      ),
    ];
  }

  @override
  Future<AppointmentChainRecord> getAppointmentChainRecord() async {
    appointmentReads++;
    return AppointmentChainRecord(
      currentConsecutive: 4,
      bestConsecutive: 6,
      updatedAt: DateTime.utc(2026, 10, 7),
    );
  }
}
