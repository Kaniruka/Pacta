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

  /// The cached row this attempt observed when it failed. The transient reason
  /// is only shown while the cache is still in that same state: a newer row
  /// (save or adopted profile) makes it stale.
  ProfileAccount? _syncErrorCache;

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
    // 错误归属在请求开始前固定：这次尝试只对当时那一版缓存负责。请求期间
    // 另一入口把缓存推进到新版本后，失败就不属于新版本，不能再显示。
    final observed = await _readCachedRow();
    ProfileAccount? profile;
    String? failure;
    try {
      profile = await widget.repository.syncProfile();
    } catch (error) {
      failure = error is StateError ? error.message : error.toString();
    }
    if (!mounted) return;
    final error = failure ?? profile?.syncError;
    setState(() {
      if (profile != null) _profile = profile;
      _syncError = error;
      _syncErrorCache = error == null ? null : observed;
      _syncing = false;
    });
  }

  /// The cached row this attempt starts from. Read before the request instead
  /// of after a failure, so a concurrent save cannot hand the older error to a
  /// newer version; a failed read falls back to what the card already shows.
  Future<ProfileAccount?> _readCachedRow() async {
    try {
      final cached = await widget.repository.getProfile();
      return cached.updatedAt == null ? null : cached;
    } catch (_) {
      final known = _profile;
      return known == null || known.updatedAt == null ? null : known;
    }
  }

  void _retryStatistics() => setState(() => _statisticsAttempt++);

  /// A cached row reports its own last error, but a failure of this attempt may
  /// never have reached the row (the write itself can fail). Such a transient
  /// reason still belongs on the card while the cache has not moved on; a newer
  /// row means the older reason is stale and must not be shown again.
  String? _profileError(ProfileAccount? stored) {
    final storedError = stored?.syncError;
    if (storedError != null) return storedError;
    final transient = _syncError;
    if (transient == null) return null;
    final cached = stored != null && stored.updatedAt != null ? stored : null;
    final observed = _syncErrorCache;
    if (observed == null) return cached == null ? transient : null;
    if (observed.updatedAt == null) return cached == null ? transient : null;
    if (cached == null) return null;
    final sameRow =
        cached.updatedAt == observed.updatedAt &&
        cached.editSequence == observed.editSequence;
    return sameRow ? transient : null;
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

  Widget _syncErrorRow(BuildContext context, String message) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
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
        trailing: const Icon(Icons.chevron_right, size: 18),
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
                  size: 16,
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
