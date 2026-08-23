import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/app/pacta_app.dart';

void main() {
  testWidgets('launches on Board with exactly four primary destinations', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PactaApp()));

    expect(find.text('Today\'s Board'), findsOneWidget);

    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.destinations, hasLength(4));
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('National Focus Tree'), findsOneWidget);
    expect(find.text('Focus Chain'), findsOneWidget);
    expect(find.text('My'), findsOneWidget);
  });

  testWidgets('switches destinations and preserves destination state', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PactaApp()));

    await tester.tap(_navigationLabel('National Focus Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Structure only'), findsOneWidget);

    await tester.tap(find.text('Detailed'));
    await tester.pumpAndSettle();
    expect(find.text('Card details visible'), findsOneWidget);

    await tester.tap(_navigationLabel('Focus Chain'));
    await tester.pumpAndSettle();
    expect(find.text('Start a Focus Session'), findsOneWidget);

    await tester.tap(_navigationLabel('My'));
    await tester.pumpAndSettle();
    expect(
      find.text('Review personal records and global settings.'),
      findsOneWidget,
    );

    await tester.tap(_navigationLabel('National Focus Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Card details visible'), findsOneWidget);
  });
}

Finder _navigationLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
