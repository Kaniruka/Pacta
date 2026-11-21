import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/focus_models.dart';
import '../national_focus/national_focus_models.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_error_text.dart';
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
/// and never computes settlement itself. Loading and failure are shown as
/// themselves: a record store that could not be read is never reported as a
/// zero figure, and a failed profile read keeps its reason and a retry.
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

  /// The first sync reports a failed read in memory only, because the
  /// repository must not invent a local version for it. The card therefore
  /// keeps that reason so an empty cache still says what went wrong.
  String? _syncError;

  bool _syncing = false;

  /// Rebuilding with a new key resubscribes the record streams; retrying a
  /// failed read never repeats a profile or business write.
  int _statisticsAttempt = 0;

  @override
  void initState() {
    super.initState();
    // initState runs before the first build, so this first pass must not
    // schedule a rebuild.
    unawaited(_syncProfile(initial: true));
  }

  Future<void> _syncProfile({bool initial = false}) async {
    if (_syncing) return;
    if (initial) {
      _syncing = true;
    } else {
      setState(() => _syncing = true);
    }
    ProfileAccount? profile;
    String? failure;
    try {
      profile = await widget.repository.syncProfile();
    } catch (error) {
      failure = formatUserError(error, fallback: '资料暂时无法读取，请稍后重试。');
    }
    if (!mounted) return;
    setState(() {
      if (profile != null) _profile = profile;
      _syncError = failure ?? profile?.syncError;
      _syncing = false;
    });
  }

  void _retryStatistics() => setState(() => _statisticsAttempt++);

  /// 只读名片只在"没有可展示资料"时报告错误。
  ///
  /// 编辑页保存失败属于编辑页：它在原地显示原因并提供就地重试，退出编辑页
  /// 后这张只读名片不得继续展示那条保存报错。仓库也只把读取/初始化失败写进
  /// 缓存行，因此这里按"本机是否已有资料版本"决定是否显示。
  String? _profileError(ProfileAccount? stored) {
    if (stored != null && stored.updatedAt != null) return null;
    final message = _syncError ?? stored?.syncError;
    if (message == null) return null;
    return formatUserError(message, fallback: '资料暂时无法读取，请稍后重试。');
  }

  Future<void> _openEdit() async {
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
      final stored = profileSnapshot.data;
      final profile = stored ?? _profile ?? ProfileAccount(userId: '');
      if (stored != null) _profile = stored;
      final errorText = _profileError(stored);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, profile),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                _syncErrorRow(context, errorText),
              ],
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(child: _nationalFocusGroup()),
                  const SizedBox(width: 8),
                  Expanded(child: _focusGroup()),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _nationalFocusGroup() => StreamBuilder<List<NationalFocusCard>>(
    key: ValueKey<int>(_statisticsAttempt),
    stream: widget.overview.watchCards(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _StatisticsStatus(
          icon: Icons.account_tree_outlined,
          label: '国策',
          primary: '统计暂时无法读取',
          secondary: '记录仍在本机，可稍后重试',
          onRetry: _retryStatistics,
        );
      }
      final cards = snapshot.data;
      if (cards == null) {
        return const _StatisticsStatus(
          icon: Icons.account_tree_outlined,
          label: '国策',
          primary: '正在读取…',
          secondary: '稍后自动显示',
        );
      }
      final statistics = computeProfileStatistics(
        cards: cards,
        sessions: const <FocusSession>[],
      );
      return _StatisticsGroup(
        icon: Icons.account_tree_outlined,
        label: '国策',
        primary: '点亮 ${statistics.litCardCount}',
        secondary: '已内化 ${statistics.internalizedCardCount}',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                NationalFocusStatisticsPage(overview: widget.overview),
          ),
        ),
      );
    },
  );

  Widget _focusGroup() => StreamBuilder<List<FocusSession>>(
    key: ValueKey<int>(_statisticsAttempt),
    stream: widget.overview.watchSessions(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _StatisticsStatus(
          icon: Icons.timer_outlined,
          label: '专注',
          primary: '统计暂时无法读取',
          secondary: '记录仍在本机，可稍后重试',
          onRetry: _retryStatistics,
        );
      }
      final sessions = snapshot.data;
      if (sessions == null) {
        return const _StatisticsStatus(
          icon: Icons.timer_outlined,
          label: '专注',
          primary: '正在读取…',
          secondary: '稍后自动显示',
        );
      }
      final statistics = computeProfileStatistics(
        cards: const <NationalFocusCard>[],
        sessions: sessions,
      );
      return _StatisticsGroup(
        icon: Icons.timer_outlined,
        label: '专注',
        primary: '完成 ${statistics.completedFocusCount} 次',
        secondary:
            '累计 ${formatFocusDuration(statistics.effectiveFocusSeconds)}',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => FocusStatisticsPage(overview: widget.overview),
          ),
        ),
      );
    },
  );

  /// 身份整行即编辑入口：头像 + 昵称 + 账号 + 右侧箭头，命中高度 ≥48dp。
  Widget _header(BuildContext context, ProfileAccount profile) {
    final avatar = profile.avatar;
    final texts = Theme.of(context).textTheme;
    return Semantics(
      button: profile.userId.isNotEmpty,
      label: '编辑资料',
      child: Tooltip(
        message: '编辑资料',
        excludeFromSemantics: true,
        child: InkWell(
          onTap: profile.userId.isEmpty ? null : _openEdit,
          borderRadius: BorderRadius.circular(PactaSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: PactaSpacing.xs),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: avatar == null
                        ? null
                        : MemoryImage(avatar.bytes),
                    child: avatar == null
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  const SizedBox(width: PactaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.effectiveDisplayName,
                          style: texts.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: PactaSpacing.xxs),
                        Text(
                          widget.accountIdentifier ?? '账号资料 · 随账号同步',
                          style: texts.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: PactaSpacing.sm),
                  const Icon(Icons.chevron_right, size: PactaIconSizes.compact),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _syncErrorRow(BuildContext context, String message) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: PactaSpacing.sm,
    children: [
      Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
      TextButton(
        onPressed: _syncing ? null : () => _syncProfile(),
        child: const Text('重试'),
      ),
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
      child: _StatisticsBody(
        icon: icon,
        label: label,
        primary: primary,
        secondary: secondary,
        trailing: const Icon(Icons.chevron_right, size: PactaIconSizes.sm),
      ),
    ),
  );
}

/// Loading or failed statistics: the same frame as a figure, with the reason
/// and, when the read can be repeated, a retry inside the group.
class _StatisticsStatus extends StatelessWidget {
  const _StatisticsStatus({
    required this.icon,
    required this.label,
    required this.primary,
    required this.secondary,
    this.onRetry,
  });

  final IconData icon;
  final String label;
  final String primary;
  final String secondary;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label统计',
    child: _StatisticsBody(
      icon: icon,
      label: label,
      primary: primary,
      secondary: secondary,
      muted: onRetry != null,
      trailing: onRetry == null
          ? null
          : TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试'),
            ),
    ),
  );
}

class _StatisticsBody extends StatelessWidget {
  const _StatisticsBody({
    required this.icon,
    required this.label,
    required this.primary,
    required this.secondary,
    this.trailing,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String primary;
  final String secondary;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
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
                  size: PactaIconSizes.sm,
                  color: muted ? colors.outline : colors.primary,
                ),
                const SizedBox(width: 4),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 4),
            Text(primary, style: Theme.of(context).textTheme.titleSmall),
            Text(secondary, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
