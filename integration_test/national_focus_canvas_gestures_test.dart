import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../test/support/national_focus_reference_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android touch can pinch-zoom and pan the full reference tree', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: 'national-focus-android-gesture-fixture',
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 9, 25, 10),
    );
    final fixture = await NationalFocusReferenceFixture.load();
    final seed = await fixture.seed(repository);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(child: NationalFocusTreePage(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repository.dispose();
      await database.close();
    });

    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    expect(canvas, findsOneWidget);
    expect(seed.totalNodeCount, 50);
    expect(
      find.byKey(ValueKey('national-focus-node-${seed.cardId('router')}')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('national-focus-node-${seed.cardId('pain_free_early_rise')}'),
      ),
      findsOneWidget,
    );

    final gestureSurface = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final pageOffset = position.pixels;
    final beforeSingle = tester.widget<Transform>(canvas).transform.clone();
    await tester.drag(gestureSurface, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(pageOffset));
    expect(tester.widget<Transform>(canvas).transform, beforeSingle);
    final bounds = tester.getRect(gestureSurface);
    final focal = bounds.center;
    final initialTransform = tester.widget<Transform>(canvas).transform;
    final initialScale = initialTransform.entry(0, 0).abs();

    final leftFinger = await tester.startGesture(
      focal - const Offset(18, 0),
      pointer: 11,
    );
    final rightFinger = await tester.startGesture(
      focal + const Offset(18, 0),
      pointer: 12,
    );
    await leftFinger.moveBy(const Offset(-24, 0));
    await rightFinger.moveBy(const Offset(24, 0));
    await tester.pump(const Duration(milliseconds: 100));

    final zoomedTransform = tester.widget<Transform>(canvas).transform;
    final zoomedScale = zoomedTransform.entry(0, 0).abs();
    expect(zoomedScale, greaterThan(initialScale));
    final translationBeforePan = zoomedTransform.getTranslation();

    await leftFinger.moveBy(const Offset(28, 18));
    await rightFinger.moveBy(const Offset(28, 18));
    await tester.pump(const Duration(milliseconds: 100));
    await leftFinger.up();
    await rightFinger.up();
    await tester.pumpAndSettle();

    final pannedTransform = tester.widget<Transform>(canvas).transform;
    expect(pannedTransform.entry(0, 0).abs(), closeTo(zoomedScale, 0.02));
    expect(pannedTransform.getTranslation(), isNot(translationBeforePan));
    expect(tester.takeException(), isNull);
  });
}
