import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_date_format.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import 'national_focus_ai_access.dart';
import 'national_focus_shared_widgets.dart';

class NationalFocusAiAnalysisEntry extends StatelessWidget {
  const NationalFocusAiAnalysisEntry({
    super.key,
    required this.mcpUrl,
    required this.repository,
    this.onOpenSync,
    this.accountTimeZoneIdLoader,
  });

  final String? mcpUrl;
  final NationalFocusAiGrantRepository? repository;
  final VoidCallback? onOpenSync;
  final Future<String?> Function()? accountTimeZoneIdLoader;

  @override
  Widget build(BuildContext context) => PactaGroupedList(
    children: [
      PactaSettingsTile(
        tileKey: const ValueKey('national-focus-ai-entry'),
        leadingIcon: Icons.auto_awesome_outlined,
        title: '开放能力',
        subtitle: '连接外部 AI 工具与服务，管理访问权限与记录',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => NationalFocusAiAnalysisPage(
              mcpUrl: mcpUrl,
              repository: repository,
              onOpenSync: onOpenSync,
              accountTimeZoneIdLoader: accountTimeZoneIdLoader,
            ),
          ),
        ),
      ),
    ],
  );
}

class NationalFocusAiAnalysisPage extends StatefulWidget {
  const NationalFocusAiAnalysisPage({
    super.key,
    required this.mcpUrl,
    required this.repository,
    this.onOpenSync,
    this.accountTimeZoneIdLoader,
  });

  final String? mcpUrl;
  final NationalFocusAiGrantRepository? repository;
  final VoidCallback? onOpenSync;
  final Future<String?> Function()? accountTimeZoneIdLoader;

  @override
  State<NationalFocusAiAnalysisPage> createState() =>
      _NationalFocusAiAnalysisPageState();
}

class _NationalFocusAiAnalysisPageState
    extends State<NationalFocusAiAnalysisPage> {
  final GlobalKey<TooltipState> _infoTooltipKey = GlobalKey<TooltipState>();
  List<NationalFocusAiGrant> _grants = const [];
  List<NationalFocusAiAuditLog> _auditLogs = const [];
  String? _loadError;
  String? _actionMessage;
  bool _loading = true;
  bool _working = false;
  String? _displayTimeZoneId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTimeZone());
    unawaited(_loadData());
  }

  Future<void> _loadTimeZone() async {
    final loader = widget.accountTimeZoneIdLoader;
    if (loader == null) return;
    try {
      final zone = await loader();
      if (!mounted) return;
      setState(() => _displayTimeZoneId = zone);
    } catch (_) {
      // 时区读取失败时回退到本机时区。
    }
  }

  Future<void> _loadData() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _loadError = null;
        _grants = const [];
        _auditLogs = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<Object>([
        repository.listMyGrants(),
        repository.listRecentAuditLogs(limit: 20),
      ]);
      if (!mounted) return;
      setState(() {
        _grants = results[0] as List<NationalFocusAiGrant>;
        _auditLogs = results[1] as List<NationalFocusAiAuditLog>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendlyError(error);
      });
    }
  }

  Future<void> _openCreateSheet() async {
    final repository = widget.repository;
    final mcpUrl = widget.mcpUrl;
    if (repository == null || mcpUrl == null || _working) return;
    final created = await showModalBottomSheet<CreatedNationalFocusAiGrant>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateConnectionSheet(
        mcpUrl: mcpUrl,
        onCreate:
            ({
              required String label,
              required NationalFocusAiScope scope,
              Duration? ttl,
              String? agentPreset,
            }) => repository.createGrant(
              label: label,
              scope: scope,
              ttl: ttl,
              agentPreset: agentPreset,
            ),
      ),
    );
    if (!mounted || created == null) return;
    setState(() => _actionMessage = '已创建连接「${created.grant.label}」。');
    await _loadData();
  }

  Future<void> _revokeGrant(NationalFocusAiGrant grant) async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('撤销「${grant.label}」？'),
        content: const Text('撤销后，该连接令牌会立即失效，无法再读取或修改你的国策云端快照。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留连接'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _actionMessage = null;
    });
    try {
      await repository.revokeGrant(grant.id);
      if (!mounted) return;
      setState(() => _actionMessage = '已撤销连接「${grant.label}」。');
      await _loadData();
    } catch (error) {
      if (mounted) setState(() => _actionMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteGrant(NationalFocusAiGrant grant) async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除「${grant.label}」？'),
        content: const Text('删除后该条失效连接记录将从列表中移除，历史调用日志仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _actionMessage = null;
    });
    try {
      await repository.deleteGrant(grant.id);
      if (!mounted) return;
      setState(() => _actionMessage = '已删除失效连接「${grant.label}」。');
      await _loadData();
    } catch (error) {
      if (mounted) setState(() => _actionMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revokeAllGrants() async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撤销全部连接？'),
        content: const Text('当前所有有效 MCP 连接令牌都会立即失效，需要重新创建后才能继续使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('全部撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _actionMessage = null;
    });
    try {
      final count = await repository.revokeAllGrants();
      if (!mounted) return;
      setState(() => _actionMessage = '已撤销 $count 个有效连接。');
      await _loadData();
    } catch (error) {
      if (mounted) setState(() => _actionMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now().toUtc();
    final activeGrants = _grants.where((g) => g.isActiveAt(now)).toList();
    final canManage = widget.mcpUrl != null && widget.repository != null;

    return PactaSurfaces.wrapIfMissing(
      context,
      Scaffold(
        appBar: AppBar(
          title: const Text('开放能力'),
          actions: [
            IconButton(
              onPressed: (_loading || _working || widget.repository == null)
                  ? null
                  : _loadData,
              tooltip: '刷新状态',
              icon: const Icon(Icons.refresh, size: PactaIconSizes.md),
            ),
            Tooltip(
              key: _infoTooltipKey,
              message:
                  'AI 读取最近一次上传的云端快照，已内置 better-national-focus 技能。'
                  '读写连接可新建或编辑卡片、管理强化与树挂载，每次写入自动保留历史备份，'
                  '绝不修改点亮状态、连胜与失败记录。',
              child: IconButton(
                onPressed: () =>
                    _infoTooltipKey.currentState?.ensureTooltipVisible(),
                tooltip: '连接说明',
                icon: const Icon(Icons.info_outline, size: PactaIconSizes.md),
              ),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              key: const ValueKey('national-focus-ai-analysis-page'),
              padding: PactaSpacing.pageInsets(context),
              children: [
                _buildHeroCard(
                  context,
                  activeCount: activeGrants.length,
                  canManage: canManage,
                ),
                if (_actionMessage != null) ...[
                  const SizedBox(height: PactaSpacing.md),
                  NationalFocusInfoCallout(message: _actionMessage!),
                ],
                PactaSectionHeader(
                  title: '已授权连接',
                  trailing: activeGrants.length > 1
                      ? TextButton(
                          key: const ValueKey('national-focus-ai-revoke-all'),
                          onPressed: _working ? null : _revokeAllGrants,
                          child: const Text('全部撤销'),
                        )
                      : null,
                ),
                _buildGrantsSection(context, now, colors),
                const PactaSectionHeader(title: '最近调用与写入记录'),
                _buildAuditSection(context, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required int activeCount,
    required bool canManage,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusText = widget.mcpUrl == null || widget.repository == null
        ? '连接服务未配置'
        : activeCount == 0
        ? '支持 Antigravity、Claude Code、Codex、DSH、Cursor 等客户端'
        : '已有 $activeCount 个连接生效，支持只读分析与受限编辑';

    return Card(
      child: Padding(
        padding: PactaSpacing.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(PactaSpacing.sm),
                    child: Icon(
                      Icons.hub_outlined,
                      size: PactaIconSizes.md,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: PactaSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '外部工具接入',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: PactaFonts.semibold,
                        ),
                      ),
                      const SizedBox(height: PactaSpacing.xxs),
                      Text(
                        statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: PactaSpacing.sm),
                const PactaStatusBadge(
                  label: '内置技能',
                  icon: Icons.auto_awesome_outlined,
                  tone: PactaStatusBadgeTone.primary,
                ),
              ],
            ),
            if (!canManage) ...[
              const SizedBox(height: PactaSpacing.md),
              const NationalFocusInfoCallout(
                message: '服务地址或登录会话尚未配置，请联系应用维护者。',
              ),
            ],
            const SizedBox(height: PactaSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final createButton = FilledButton.icon(
                  key: const ValueKey('national-focus-ai-create'),
                  onPressed: canManage && !_working ? _openCreateSheet : null,
                  icon: const Icon(Icons.add_link, size: PactaIconSizes.sm),
                  label: const Text('创建连接'),
                );
                final syncButton = widget.onOpenSync == null
                    ? null
                    : OutlinedButton.icon(
                        key: const ValueKey('national-focus-ai-open-sync'),
                        onPressed: widget.onOpenSync,
                        icon: const Icon(
                          Icons.sync_outlined,
                          size: PactaIconSizes.sm,
                        ),
                        label: const Text('前往数据同步'),
                      );
                if (syncButton == null) return createButton;
                if (constraints.maxWidth >= 420) {
                  return Row(
                    children: [
                      Expanded(child: createButton),
                      const SizedBox(width: PactaSpacing.sm),
                      Expanded(child: syncButton),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    createButton,
                    const SizedBox(height: PactaSpacing.sm),
                    syncButton,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrantsSection(
    BuildContext context,
    DateTime now,
    ColorScheme colors,
  ) {
    final theme = Theme.of(context);
    if (_loading) {
      return PactaGroupedList(
        children: [
          Padding(
            padding: PactaSpacing.cardInsets,
            child: Row(
              children: [
                const SizedBox(
                  width: PactaIconSizes.compact,
                  height: PactaIconSizes.compact,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: PactaSpacing.md),
                Text('正在读取连接状态…', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      );
    }
    if (_loadError != null) {
      return Card(
        child: Padding(
          padding: PactaSpacing.cardInsets,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NationalFocusInlineError(_loadError!),
              const SizedBox(height: PactaSpacing.md),
              OutlinedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: PactaIconSizes.sm),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_grants.isEmpty) {
      return PactaGroupedList(
        children: [
          Padding(
            padding: PactaSpacing.cardInsets,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('尚未创建连接', style: theme.textTheme.titleSmall),
                const SizedBox(height: PactaSpacing.xs),
                Text(
                  '点击上方「创建连接」，选择只读或读写权限并生成一次性配置。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return PactaGroupedList(
      children: [
        for (final grant in _grants) _buildGrantRow(context, grant, now),
      ],
    );
  }

  Widget _buildGrantRow(
    BuildContext context,
    NationalFocusAiGrant grant,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = grant.isActiveAt(now);
    final expired = grant.revokedAt == null && grant.isExpiredAt(now);
    final statusLabel = active
        ? '生效中'
        : expired
        ? '已过期'
        : '已撤销';
    final statusTone = active
        ? PactaStatusBadgeTone.success
        : PactaStatusBadgeTone.neutral;
    final preset = NationalFocusAgentPreset.fromStorage(grant.agentPreset);
    final String timeMetaText;
    if (grant.revokedAt != null) {
      timeMetaText =
          '撤销于 ${formatPactaRelativePast(grant.revokedAt!, now: now, timeZoneId: _displayTimeZoneId)}';
    } else if (grant.expiresAt == null) {
      timeMetaText = '永不过期';
    } else if (expired) {
      timeMetaText =
          '已于 ${formatPactaRelativePast(grant.expiresAt!, now: now, timeZoneId: _displayTimeZoneId)}过期';
    } else {
      timeMetaText =
          '${formatPactaCompactRemaining(grant.expiresAt!.difference(now))}到期';
    }
    final lastUsedText = grant.lastUsedAt == null
        ? '尚未使用'
        : '最近调用 ${formatPactaRelativePast(grant.lastUsedAt!, now: now, timeZoneId: _displayTimeZoneId)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grant.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: PactaFonts.semibold,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (preset != null)
                      PactaStatusBadge(
                        label: preset.label,
                        icon: Icons.smart_toy_outlined,
                        tone: PactaStatusBadgeTone.neutral,
                      ),
                    PactaStatusBadge(
                      label: grant.scope.label,
                      tone: grant.scope == NationalFocusAiScope.readWrite
                          ? PactaStatusBadgeTone.primary
                          : PactaStatusBadgeTone.neutral,
                    ),
                    PactaStatusBadge(label: statusLabel, tone: statusTone),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _GrantMetaItem(
                      icon: Icons.schedule_outlined,
                      text: timeMetaText,
                    ),
                    _GrantMetaItem(
                      icon: Icons.history_outlined,
                      text: lastUsedText,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (active)
            IconButton(
              key: ValueKey('national-focus-ai-revoke-${grant.id}'),
              onPressed: _working ? null : () => _revokeGrant(grant),
              tooltip: '撤销此连接',
              icon: Icon(
                Icons.link_off_outlined,
                size: PactaIconSizes.md,
                color: colors.error,
              ),
            )
          else
            IconButton(
              key: ValueKey('national-focus-ai-delete-${grant.id}'),
              onPressed: _working ? null : () => _deleteGrant(grant),
              tooltip: '删除此记录',
              icon: Icon(
                Icons.delete_outline,
                size: PactaIconSizes.md,
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditSection(BuildContext context, ColorScheme colors) {
    final theme = Theme.of(context);
    if (_loading) {
      return PactaGroupedList(
        children: [
          Padding(
            padding: PactaSpacing.cardInsets,
            child: Text(
              '正在读取最近调用记录…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    if (_auditLogs.isEmpty) {
      return PactaGroupedList(
        children: [
          Padding(
            padding: PactaSpacing.cardInsets,
            child: Text(
              '尚无调用记录',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return PactaGroupedList(
      children: [for (final log in _auditLogs) _buildAuditRow(context, log)],
    );
  }

  Widget _buildAuditRow(BuildContext context, NationalFocusAiAuditLog log) {
    final theme = Theme.of(context);
    final timeLabel = formatPactaRelativePast(
      log.createdAt,
      timeZoneId: _displayTimeZoneId,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: PactaFonts.medium,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PactaStatusBadge(
                label: log.isWrite ? '写入' : '读取',
                tone: log.isWrite
                    ? PactaStatusBadgeTone.primary
                    : PactaStatusBadgeTone.neutral,
              ),
              if (log.snapshotRevision != null)
                PactaStatusBadge(
                  label: 'r${log.snapshotRevision}',
                  tone: PactaStatusBadgeTone.neutral,
                ),
              _GrantMetaItem(icon: Icons.link_outlined, text: log.grantLabel),
              _GrantMetaItem(icon: Icons.schedule_outlined, text: timeLabel),
            ],
          ),
        ],
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is NationalFocusAiAccessError) {
      switch (error.code) {
        case '42501':
          return '当前账号状态不允许执行此操作，请重新登录后重试。';
        case 'PT429':
          return '有效连接数量已达上限，请先撤销不再使用的连接。';
        case '22023':
          return '连接参数无效，请检查名称与有效期后重试。';
      }
    }
    return formatUserError(error, fallback: '无法完成 AI 连接操作，请检查网络后重试。');
  }
}

class _GrantMetaItem extends StatelessWidget {
  const _GrantMetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: PactaIconSizes.micro, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CreateConnectionSheet extends StatefulWidget {
  const _CreateConnectionSheet({required this.mcpUrl, required this.onCreate});

  final String mcpUrl;
  final Future<CreatedNationalFocusAiGrant> Function({
    required String label,
    required NationalFocusAiScope scope,
    Duration? ttl,
    String? agentPreset,
  })
  onCreate;

  @override
  State<_CreateConnectionSheet> createState() => _CreateConnectionSheetState();
}

class _CreateConnectionSheetState extends State<_CreateConnectionSheet> {
  final _labelController = TextEditingController(
    text: NationalFocusAgentPreset.antigravity.defaultConnectionName,
  );
  final _customTtlController = TextEditingController(text: '14');
  NationalFocusAgentPreset _preset = NationalFocusAgentPreset.antigravity;
  NationalFocusAiScope _scope = NationalFocusAiScope.read;
  NationalFocusAiTtlPreset _ttlPreset = NationalFocusAiTtlPreset.sevenDays;
  bool _customTtlSelected = false;
  NationalFocusAiCustomTtlUnit _customTtlUnit =
      NationalFocusAiCustomTtlUnit.days;
  bool _labelEditedManually = false;
  bool _submitting = false;
  String? _error;
  CreatedNationalFocusAiGrant? _created;

  @override
  void dispose() {
    _labelController.dispose();
    _customTtlController.dispose();
    super.dispose();
  }

  void _selectPreset(NationalFocusAgentPreset preset) {
    setState(() {
      _preset = preset;
      if (!_labelEditedManually && _created == null) {
        _labelController.text = preset.defaultConnectionName;
      }
    });
  }

  Future<void> _submit() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _error = '请输入连接名称。');
      return;
    }
    Duration? ttl;
    if (_customTtlSelected) {
      ttl = parseCustomNationalFocusTtl(
        _customTtlController.text,
        _customTtlUnit,
      );
      if (ttl == null) {
        setState(() => _error = '自定义有效期需在 1 分钟至 3650 天之间。');
        return;
      }
    } else {
      ttl = _ttlPreset.duration;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await widget.onCreate(
        label: label,
        scope: _scope,
        ttl: ttl,
        agentPreset: _preset.storageValue,
      );
      if (!mounted) return;
      setState(() {
        _created = created;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is NationalFocusAiAccessError && error.code == 'PT429'
            ? '有效连接数量已达上限，请先撤销不再使用的连接。'
            : formatUserError(error, fallback: '创建连接失败，请稍后重试。');
      });
    }
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: created == null
            ? _buildCreateForm(context)
            : _buildCredentialResult(context, created),
      ),
    );
  }

  Widget _buildCreateForm(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '创建 MCP 连接',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: PactaFonts.semibold,
          ),
        ),
        const SizedBox(height: PactaSpacing.md),
        Text('客户端预设', style: theme.textTheme.labelLarge),
        const SizedBox(height: PactaSpacing.xs),
        Wrap(
          spacing: PactaSpacing.sm,
          runSpacing: PactaSpacing.xs,
          children: [
            for (final preset in NationalFocusAgentPreset.values)
              ChoiceChip(
                label: Text(preset.label),
                selected: _preset == preset,
                onSelected: _submitting ? null : (_) => _selectPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: PactaSpacing.md),
        TextField(
          key: const ValueKey('national-focus-ai-grant-label'),
          controller: _labelController,
          enabled: !_submitting,
          maxLength: 80,
          onChanged: (_) => _labelEditedManually = true,
          decoration: pactaCardInputDecoration(
            context,
            labelText: '连接名称',
            hintText: '例如：MacBook Codex、家里 Antigravity',
          ),
        ),
        const SizedBox(height: PactaSpacing.md),
        Text('授权范围', style: theme.textTheme.labelLarge),
        const SizedBox(height: PactaSpacing.xs),
        SegmentedButton<NationalFocusAiScope>(
          segments: [
            for (final scope in NationalFocusAiScope.values)
              ButtonSegment<NationalFocusAiScope>(
                value: scope,
                label: Text(scope.label),
              ),
          ],
          selected: {_scope},
          onSelectionChanged: _submitting
              ? null
              : (selection) => setState(() => _scope = selection.first),
        ),
        const SizedBox(height: PactaSpacing.xs),
        Text(
          _scope == NationalFocusAiScope.readWrite
              ? '允许 AI 创建/修改卡片、调整强化与树结构并自动备份云端快照；禁止修改点亮状态、连胜与失败记录。'
              : '仅允许读取最近一次上传的云端快照与失败历史，不提供写入工具。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: PactaSpacing.md),
        Text('有效期', style: theme.textTheme.labelLarge),
        const SizedBox(height: PactaSpacing.xs),
        Wrap(
          spacing: PactaSpacing.sm,
          runSpacing: PactaSpacing.xs,
          children: [
            for (final ttl in NationalFocusAiTtlPreset.values)
              ChoiceChip(
                label: Text(ttl.label),
                selected: !_customTtlSelected && _ttlPreset == ttl,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _customTtlSelected = false;
                        _ttlPreset = ttl;
                      }),
              ),
            ChoiceChip(
              key: const ValueKey('national-focus-ai-ttl-custom'),
              label: const Text('自定义'),
              selected: _customTtlSelected,
              onSelected: _submitting
                  ? null
                  : (_) => setState(() => _customTtlSelected = true),
            ),
          ],
        ),
        if (_customTtlSelected) ...[
          const SizedBox(height: PactaSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 108,
                child: TextField(
                  key: const ValueKey('national-focus-ai-ttl-custom-value'),
                  controller: _customTtlController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: pactaCardInputDecoration(
                    context,
                    labelText: '时长',
                    hintText: '14',
                  ),
                ),
              ),
              const SizedBox(width: PactaSpacing.sm),
              Expanded(
                child: SegmentedButton<NationalFocusAiCustomTtlUnit>(
                  segments: [
                    for (final unit in NationalFocusAiCustomTtlUnit.values)
                      ButtonSegment<NationalFocusAiCustomTtlUnit>(
                        value: unit,
                        label: Text(unit.label),
                      ),
                  ],
                  selected: {_customTtlUnit},
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) =>
                            setState(() => _customTtlUnit = selection.first),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: PactaSpacing.md),
          NationalFocusInlineError(_error!),
        ],
        const SizedBox(height: PactaSpacing.lg),
        FilledButton.icon(
          key: const ValueKey('national-focus-ai-submit-create'),
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.vpn_key_outlined, size: PactaIconSizes.sm),
          label: Text(_submitting ? '生成中…' : '生成连接令牌'),
        ),
      ],
    );
  }

  Widget _buildCredentialResult(
    BuildContext context,
    CreatedNationalFocusAiGrant created,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final endpoint = nationalFocusMcpEndpointUrl(
      widget.mcpUrl,
      created.grant.scope,
    );
    final config = buildNationalFocusAgentConfig(
      preset: _preset,
      endpointUrl: endpoint,
      token: created.token,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '连接已创建',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: PactaFonts.semibold,
          ),
        ),
        const SizedBox(height: PactaSpacing.md),
        const NationalFocusInfoCallout(
          message: '令牌仅展示这一次，关闭后无法再次查看；如遗失请撤销后重新创建。',
        ),
        const SizedBox(height: PactaSpacing.md),
        Text('切换客户端配置格式', style: theme.textTheme.labelLarge),
        const SizedBox(height: PactaSpacing.xs),
        Wrap(
          spacing: PactaSpacing.sm,
          runSpacing: PactaSpacing.xs,
          children: [
            for (final preset in NationalFocusAgentPreset.values)
              ChoiceChip(
                label: Text(preset.label),
                selected: _preset == preset,
                onSelected: (_) => setState(() => _preset = preset),
              ),
          ],
        ),
        const SizedBox(height: PactaSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(PactaSpacing.md),
            child: SelectableText(
              config,
              key: const ValueKey('national-focus-ai-config-preview'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: PactaSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('national-focus-ai-copy-token'),
                onPressed: () => _copy(created.token, '已复制连接令牌'),
                icon: const Icon(Icons.key_outlined, size: PactaIconSizes.sm),
                label: const Text('复制令牌'),
              ),
            ),
            const SizedBox(width: PactaSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('national-focus-ai-copy-config'),
                onPressed: () => _copy(config, '已复制 ${_preset.label} 配置'),
                icon: const Icon(Icons.copy_outlined, size: PactaIconSizes.sm),
                label: const Text('复制配置'),
              ),
            ),
          ],
        ),
        const SizedBox(height: PactaSpacing.sm),
        TextButton(
          key: const ValueKey('national-focus-ai-sheet-done'),
          onPressed: () => Navigator.of(context).pop(created),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
