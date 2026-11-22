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

  testWidgets(
    'failed appointment reads show retry instead of a false zero preparation total',
    (tester) async {
      final repository = _FailOnceAppointmentsRepository();
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()
            ..signedInUser = 'appointment-read-user',
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
      expect(
        find.text('0分00秒'),
        findsNothing,
        reason: '读不到预约记录时不得把未知的准备时长显示成 0 分',
      );
      expect(find.text('预约链'), findsNothing);
      expect(tester.takeException(), isNull);

      repository.failAppointments = false;
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('链记录读取失败，请重试。'), findsNothing);
      for (final chain in ['精锐链', '普通链', '预约链']) {
        expect(find.text(chain), findsOneWidget);
      }
      // 预约统计来自真实记录：180 + 300 = 480 秒，平均 240 秒。预约链的
      // 「累计/平均」与专注链同一口径，重试后不再停留在虚假的 0 分。
      expect(find.text('8分00秒'), findsOneWidget);
      expect(find.text('4分00秒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
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

/// 预约记录首轮读取失败、重试后成功。
///
/// 首屏会先由 initState、再由首帧投影各创建一次预约读取，两次拿到同一个失败
/// Future；真实数据由测试翻转 [failAppointments] 后交给重试路径。
class _FailOnceAppointmentsRepository extends UnavailableFocusRepository {
  int appointmentReads = 0;
  bool failAppointments = true;
  Future<List<AppointmentPreparation>>? _failure;

  @override
  Future<List<AppointmentPreparation>> getAppointments() {
    appointmentReads++;
    if (!failAppointments) {
      return Future.value([
        _settledAppointment(
          'appointment-a',
          startedAt: DateTime.utc(2026, 10, 7, 9),
          seconds: 180,
        ),
        _settledAppointment(
          'appointment-b',
          startedAt: DateTime.utc(2026, 10, 7, 10),
          seconds: 300,
        ),
      ]);
    }
    return _failure ??= _unobservedFailure();
  }

  /// 首帧里预约 FutureBuilder 要等外层链记录先读到数据才会挂上，这段空窗里
  /// 失败会先落到无人监听的 zone 上，被测试框架记成未捕获异常。ignore() 只
  /// 关掉这条报告，FutureBuilder 之后仍会收到同一个错误并进入 hasError。
  Future<List<AppointmentPreparation>> _unobservedFailure() {
    final future = Future<List<AppointmentPreparation>>.error(
      StateError('Fixture appointment read failure'),
    );
    future.ignore();
    return future;
  }
}

AppointmentPreparation _settledAppointment(
  String id, {
  required DateTime startedAt,
  required int seconds,
}) => AppointmentPreparation(
  id: id,
  taskId: 'task-$id',
  mode: FocusChainMode.regular,
  durationSeconds: 25 * 60,
  startedAt: startedAt,
  endsAt: startedAt.add(const Duration(minutes: 15)),
  status: AppointmentPreparationStatus.succeeded,
  settledAt: startedAt.add(Duration(seconds: seconds)),
  updatedAt: startedAt.add(Duration(seconds: seconds)),
  preparationSeconds: 15 * 60,
);
