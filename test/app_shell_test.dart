import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/app/chain_theme.dart';
import 'package:pacta/app/shell/app_shell.dart';

void main() {
  testWidgets('launches on Board with exactly four primary destinations', (
    tester,
  ) async {
    await _pumpShell(tester);

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
    await _pumpShell(tester);

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

Future<void> _pumpShell(WidgetTester tester) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: buildChainTheme(), home: const AppShell()),
    ),
  );
}
