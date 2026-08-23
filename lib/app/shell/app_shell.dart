import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/features/national_focus/national_focus_tree_page.dart';

final selectedDestinationProvider = NotifierProvider<SelectedDestination, int>(
  SelectedDestination.new,
);

class SelectedDestination extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _pages = <Widget>[
    _DestinationPage(
      title: "Today's Board",
      eyebrow: 'MONDAY / 04:00—04:00',
      description: 'Choose the next concrete Task before reviewing progress.',
      icon: Icons.dashboard_outlined,
    ),
    NationalFocusTreePage(),
    _DestinationPage(
      title: 'Start a Focus Session',
      eyebrow: 'FOCUS CHAIN / SETUP',
      description: 'Select a Task and explicitly choose the chain for today.',
      icon: Icons.radio_button_checked,
    ),
    _DestinationPage(
      title: 'My',
      eyebrow: 'ACCOUNT / RECORD',
      description: 'Review personal records and global settings.',
      icon: Icons.person_outline,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedDestinationProvider);

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: ref
            .read(selectedDestinationProvider.notifier)
            .select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Board',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'National Focus Tree',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio_button_unchecked),
            selectedIcon: Icon(Icons.radio_button_checked),
            label: 'Focus Chain',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'My',
          ),
        ],
      ),
    );
  }
}

class _DestinationPage extends StatelessWidget {
  const _DestinationPage({
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.icon,
  });

  final String title;
  final String eyebrow;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      key: PageStorageKey<String>(title),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          sliver: SliverList.list(
            children: [
              Text(
                eyebrow,
                style: textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(title, style: textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(description, style: textTheme.bodyLarge),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Icon(
                    icon,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
