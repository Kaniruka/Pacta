import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/presentation/focus_chain_page.dart';
import 'package:pacta/features/goals_tasks/presentation/board_page.dart';
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
  const AppShell({this.userId, super.key});

  final AppUserId? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedDestinationProvider);
    final destinations = _destinations;

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: selectedIndex,
          children: [for (final destination in destinations) destination.page],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: ref
            .read(selectedDestinationProvider.notifier)
            .select,
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }

  List<_AppDestination> get _destinations => [
    _AppDestination(
      label: 'Board',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      page: userId == null
          ? const _DestinationPage(
              title: "Today's Board",
              eyebrow: 'MONDAY / 04:00—04:00',
              description:
                  'Choose the next concrete Task before reviewing progress.',
              icon: Icons.dashboard_outlined,
            )
          : BoardPage(userId: userId!),
    ),
    const _AppDestination(
      label: 'National Focus Tree',
      icon: Icons.account_tree_outlined,
      selectedIcon: Icons.account_tree,
      page: NationalFocusTreePage(),
    ),
    _AppDestination(
      label: 'Focus Chain',
      icon: Icons.radio_button_unchecked,
      selectedIcon: Icons.radio_button_checked,
      page: userId == null
          ? const _DestinationPage(
              title: 'Start a Focus Session',
              eyebrow: 'FOCUS CHAIN / SETUP',
              description:
                  'Select a Task and explicitly choose the chain for today.',
              icon: Icons.radio_button_checked,
            )
          : FocusChainPage(userId: userId!),
    ),
    const _AppDestination(
      label: 'My',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      page: _DestinationPage(
        title: 'My',
        eyebrow: 'ACCOUNT / RECORD',
        description: 'Review personal records and global settings.',
        icon: Icons.person_outline,
      ),
    ),
  ];
}

class _AppDestination {
  const _AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
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
