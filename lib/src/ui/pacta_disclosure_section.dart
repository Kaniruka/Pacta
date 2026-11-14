import 'package:flutter/material.dart';

/// A quiet, consistently titled disclosure with room for floating form labels.
class PactaDisclosureSection extends StatefulWidget {
  const PactaDisclosureSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.tilePadding = EdgeInsets.zero,
    this.childrenPadding = const EdgeInsets.only(bottom: 8),
  });

  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry tilePadding;
  final EdgeInsetsGeometry childrenPadding;

  @override
  State<PactaDisclosureSection> createState() => _PactaDisclosureSectionState();
}

class _PactaDisclosureSectionState extends State<PactaDisclosureSection> {
  final _contentFocus = FocusNode();

  @override
  void dispose() {
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: widget.tilePadding,
    shape: const Border(),
    collapsedShape: const Border(),
    maintainState: true,
    onExpansionChanged: (expanded) {
      if (!expanded && _contentFocus.hasFocus) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    },
    title: DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.titleSmall,
      child: widget.title,
    ),
    subtitle: widget.subtitle,
    children: [
      Focus(
        focusNode: _contentFocus,
        canRequestFocus: false,
        skipTraversal: true,
        child: Padding(
          key: const ValueKey('pacta-disclosure-content'),
          // InputDecorator paints its floating label above its layout box.
          padding: widget.childrenPadding.add(
            const EdgeInsets.symmetric(vertical: 8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ),
    ],
  );
}
