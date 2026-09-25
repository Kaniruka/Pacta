import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('T18 两份设备存储离线确认后延迟同步并自动协调漏收推断', (tester) async {
    final result = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'pacta-ticket-18-device-',
      );
      final firstDatabase = PactaDatabase(
        NativeDatabase(File('${directory.path}/first.sqlite')),
      );
      final secondDatabase = PactaDatabase(
        NativeDatabase(File('${directory.path}/second.sqlite')),
      );
      final remote = InMemoryNationalFocusRemoteDataSource();
      var now = DateTime.utc(2026, 9, 20, 19, 59);
      final firstDevice = LocalNationalFocusRepository(
        database: firstDatabase,
        userId: 'ticket-18-device-user',
        remote: remote,
        now: () => now,
      );
      final secondDevice = LocalNationalFocusRepository(
        database: secondDatabase,
        userId: 'ticket-18-device-user',
        remote: remote,
        now: () => now,
      );

      try {
        final card = await firstDevice.createCard(
          const NationalFocusCardDraft(
            triggerCondition: '开始阅读',
            action: '阅读 5 页',
          ),
        );
        await firstDevice.placeCard(cardId: card.id, parentId: null);
        await firstDevice.lightCard(card.id);
        now = DateTime.utc(2026, 9, 20, 20);
        await firstDevice.settleDueCheckpoints();
        await firstDevice.sync();
        await secondDevice.sync();

        now = DateTime.utc(2026, 9, 21, 19);
        final confirmedCount = await firstDevice.confirmToday();
        now = DateTime.utc(2026, 9, 21, 20);
        await secondDevice.settleDueCheckpoints();
        await secondDevice.sync();

        now = DateTime.utc(2026, 9, 23, 21);
        await firstDevice.sync();
        await secondDevice.sync();
        final failures = await secondDevice.getFailures(cardId: card.id);
        final syncedCard = await secondDevice.getCard(card.id);
        return (
          confirmedCount: confirmedCount,
          failures: failures,
          successfulDays: syncedCard.successfulDays,
        );
      } finally {
        await firstDevice.dispose();
        await secondDevice.dispose();
        await firstDatabase.close();
        await secondDatabase.close();
        await directory.delete(recursive: true);
      }
    });

    expect(result, isNotNull);
    expect(result!.confirmedCount, 1);
    expect(result.failures, hasLength(1));
    expect(
      result.failures.single.checkpointAt.toUtc(),
      DateTime.utc(2026, 9, 22, 20),
    );
    expect(result.successfulDays, 2);
  });
}
