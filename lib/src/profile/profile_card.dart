import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/focus_models.dart';
import '../national_focus/national_focus_models.dart';
import 'avatar_picker.dart';
import 'profile_edit_page.dart';
import 'profile_format.dart';
import 'profile_models.dart';
import 'profile_overview.dart';
import 'profile_repository.dart';
import 'profile_statistics.dart';
import 'profile_statistics_pages.dart';

/// Account identity plus the two retained-record statistics groups.
///
/// Every figure comes from retained records; the card owns no business state
/// and never computes settlement itself.
class MyProfileCard extends StatefulWidget {
  const MyProfileCard({
    super.key,
    required this.repository,
    required this.overview,
    required this.avatarPicker,
    this.accountIdentifier,
  });

  final ProfileRepository repository;
  final ProfileOverviewSource overview;
  final AvatarPicker avatarPicker;
  final String? accountIdentifier;

  @override
  State<MyProfileCard> createState() => _MyProfileCardState();
}

class _MyProfileCardState extends State<MyProfileCard> {
  ProfileAccount? _profile;

  @override
  void initState() {
    super.initState();
    unawaited(widget.repository.syncProfile().catchError((Object _) => _empty));
  }

  ProfileAccount get _empty => ProfileAccount(userId: '', displayName: '');

  Future<void> _retrySync() async {
    try {
      final profile = await widget.repository.syncProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      // The stored profile keeps the failure text; nothing else to show here.
    }
  }

  Future<void> _openEdit() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileEditPage(
          repository: widget.repository,
          avatarPicker: widget.avatarPicker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ProfileAccount>(
    stream: widget.repository.watchProfile(),
    builder: (context, profileSnapshot) {
      final profile =
          profileSnapshot.data ?? _profile ?? ProfileAccount(userId: '');
      if (profileSnapshot.data != null) _profile = profileSnapshot.data;
      return StreamBuilder<List<NationalFocusCard>>(
        stream: widget.overview.watchCards(),
        builder: (context, cardsSnapshot) => StreamBuilder<List<FocusSession>>(
          stream: widget.overview.watchSessions(),
          builder: (context, sessionsSnapshot) {
            final statistics =
                cardsSnapshot.data == null || sessionsSnapshot.data == null
                ? ProfileStatistics.empty
                : computeProfileStatistics(
                    cards: cardsSnapshot.data!,
                    sessions: sessionsSnapshot.data!,
                  );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, profile),
                    if (profile.syncError != null) ...[
                      const SizedBox(height: 8),
                      _syncError(context, profile.syncError!),
                    ],
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _StatisticsGroup(
                            icon: Icons.account_tree_outlined,
                            label: '国策',
                            primary: '点亮 ${statistics.litCardCount}',
                            secondary:
                                '已内化 ${statistics.internalizedCardCount}',
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => NationalFocusStatisticsPage(
                                  overview: widget.overview,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatisticsGroup(
                            icon: Icons.timer_outlined,
                            label: '专注',
                            primary: '完成 ${statistics.completedFocusCount} 次',
                            secondary:
                                '累计 ${formatFocusDuration(statistics.effectiveFocusSeconds)}',
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => FocusStatisticsPage(
                                  overview: widget.overview,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _header(BuildContext context, ProfileAccount profile) {
    final avatar = profile.avatar;
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundImage: avatar == null ? null : MemoryImage(avatar.bytes),
          child: avatar == null ? const Icon(Icons.person_outline) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.effectiveDisplayName,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                widget.accountIdentifier ?? '账号资料 · 随账号同步',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '数据仅供你使用',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _openEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('编辑'),
        ),
      ],
    );
  }

  Widget _syncError(BuildContext context, String message) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
      TextButton(onPressed: _retrySync, child: const Text('重试')),
    ],
  );
}

class _StatisticsGroup extends StatelessWidget {
  const _StatisticsGroup({
    required this.icon,
    required this.label,
    required this.primary,
    required this.secondary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String primary;
  final String secondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label统计明细',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Text(primary, style: Theme.of(context).textTheme.titleSmall),
              Text(secondary, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    ),
  );
}
