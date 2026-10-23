import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _phase = String.fromEnvironment('ISSUE68_PHASE', defaultValue: 'seed');
const _runId = String.fromEnvironment(
  'ISSUE68_RUN_ID',
  defaultValue: 'default',
);
const _user = 'issue68-native-$_runId';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Issue 68 native view preference $_phase', (tester) async {
    final root = await getApplicationSupportDirectory();
    final file = File(
      '${root.path}${Platform.pathSeparator}issue68-native-$_runId.sqlite',
    );
    if (_phase == 'seed' && await file.exists()) await file.delete();

    final database = PactaDatabase(NativeDatabase(file));
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
    );

    try {
      if (_phase == 'seed') {
        final card = await tree.createCard(
          const NationalFocusCardDraft(
            name: 'I68 preserved card',
            action: 'Keep isolated local test data across restarts.',
          ),
        );
        await tree.placeCard(cardId: card.id, parentId: null);
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('issue68-capture'),
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = _user,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
            focusNotificationService: DisabledFocusNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navigation = find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is NavigationRail,
      );
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('国策树')).last,
      );
      await tester.pumpAndSettle();
      final savedCards = await tree.getTreeCards();
      expect(savedCards, hasLength(1));
      expect(savedCards.single.name, 'I68 preserved card');

      switch (_phase) {
        case 'seed':
          _expectView(tester, '简洁视图');
          await _selectView(tester, '详细视图');
          _expectView(tester, '详细视图');
        case 'baseline-restart':
          // The pre-fix page keeps this selection only in widget state.
          _expectView(tester, '简洁视图');
        case 'restored-detailed':
          _expectView(tester, '详细视图');
          await _selectView(tester, '简洁视图');
          _expectView(tester, '简洁视图');
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
        case 'restored-simple':
          _expectView(tester, '简洁视图');
        default:
          fail('Unknown ISSUE68_PHASE: $_phase');
      }

      expect(tester.takeException(), isNull);
      await _capture(tester, _phase);
      // ignore: avoid_print
      print(
        'ISSUE68_NATIVE_PASS platform=${Platform.operatingSystem} pid=$pid phase=$_phase user=$_user database=${file.path}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await focus.dispose();
      await tasks.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}

void _expectView(WidgetTester tester, String label) {
  expect(find.text(label), findsOneWidget);
}

Future<void> _selectView(WidgetTester tester, String label) async {
  await tester.tap(find.byType(PopupMenuButton<bool>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String stage) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('issue68-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}${Platform.pathSeparator}issue68-$stage.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}
