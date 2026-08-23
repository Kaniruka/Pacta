import 'package:flutter/material.dart';
import 'package:pacta/app/chain_theme.dart';

enum TreeViewDensity { simple, detailed }

class NationalFocusTreePage extends StatefulWidget {
  const NationalFocusTreePage({super.key});

  @override
  State<NationalFocusTreePage> createState() => _NationalFocusTreePageState();
}

class _NationalFocusTreePageState extends State<NationalFocusTreePage> {
  TreeViewDensity _density = TreeViewDensity.simple;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chainColors = theme.extension<ChainColors>()!;
    final isDetailed = _density == TreeViewDensity.detailed;

    return CustomScrollView(
      key: const PageStorageKey<String>('national-focus-tree'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          sliver: SliverList.list(
            children: [
              Text(
                'NATIONAL FOCUS / TREE',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: chainColors.nationalFocus,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'National Focus Tree',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              SegmentedButton<TreeViewDensity>(
                segments: const [
                  ButtonSegment(
                    value: TreeViewDensity.simple,
                    label: Text('Simple'),
                    icon: Icon(Icons.hub_outlined),
                  ),
                  ButtonSegment(
                    value: TreeViewDensity.detailed,
                    label: Text('Detailed'),
                    icon: Icon(Icons.view_agenda_outlined),
                  ),
                ],
                selected: {_density},
                onSelectionChanged: (selection) {
                  setState(() => _density = selection.single);
                },
              ),
              const SizedBox(height: 28),
              Card(
                color: chainColors.nationalFocus.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.account_tree,
                        size: 56,
                        color: chainColors.nationalFocus,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isDetailed ? 'Card details visible' : 'Structure only',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (isDetailed) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Trigger, action, dates, records, and visible state.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
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
