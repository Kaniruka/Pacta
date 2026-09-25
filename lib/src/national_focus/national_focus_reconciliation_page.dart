import 'package:flutter/material.dart';

import 'national_focus_models.dart';
import 'national_focus_repository.dart';

class NationalFocusReviewPrompt extends StatelessWidget {
  const NationalFocusReviewPrompt({super.key, required this.repository});

  final NationalFocusRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<NationalFocusReviewState>(
    stream: repository.watchNationalFocusReviewState(),
    builder: (context, snapshot) {
      final state = snapshot.data;
      if (state == null ||
          (state.reconciliationCases.isEmpty &&
              state.clockReviewCases.isEmpty &&
              state.reconciliationHistory.isEmpty &&
              state.clockReviewHistory.isEmpty)) {
        return const SizedBox.shrink();
      }
      final pendingCount =
          state.reconciliationCases.length + state.clockReviewCases.length;
      return Semantics(
        button: true,
        label: pendingCount == 0
            ? '查看国策核对记录'
            : '有 $pendingCount 项国策记录待核对，打开核对记录',
        child: Card(
          child: ListTile(
            leading: Icon(
              pendingCount == 0
                  ? Icons.fact_check_outlined
                  : Icons.warning_amber_rounded,
            ),
            title: Text(
              pendingCount == 0 ? '国策核对记录' : '$pendingCount 项国策记录待核对',
            ),
            subtitle: Text(
              pendingCount == 0
                  ? '查看已完成的分支裁决与时钟记录。'
                  : '查看完整操作来源和影响；未决定前相关节点会保持待核对。',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    NationalFocusReconciliationPage(repository: repository),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class NationalFocusReconciliationPage extends StatefulWidget {
  const NationalFocusReconciliationPage({super.key, required this.repository});

  final NationalFocusRepository repository;

  @override
  State<NationalFocusReconciliationPage> createState() =>
      _NationalFocusReconciliationPageState();
}

class _NationalFocusReconciliationPageState
    extends State<NationalFocusReconciliationPage> {
  final Map<String, String> _selectedSourceByCase = {};
  final Set<String> _busyIds = {};
  String? _error;

  Future<void> _run(String id, Future<void> Function() action) async {
    if (!_busyIds.add(id)) return;
    setState(() => _error = null);
    try {
      await action();
      try {
        await widget.repository.sync();
      } catch (error) {
        if (mounted) {
          setState(() => _error = '本机已保存核对结果，但跨设备同步失败：$error');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = '保存核对结果失败：$error');
    } finally {
      _busyIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('国策冲突与时间核对')),
    body: StreamBuilder<NationalFocusReviewState>(
      stream: widget.repository.watchNationalFocusReviewState(),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (snapshot.hasError) {
          return Center(child: Text('无法读取核对记录：${snapshot.error}'));
        }
        if (state == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              '完整操作分支会一并采用。未裁决的节点保留待核对状态，不会被当作成功或失败。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (state.reconciliationCases.isNotEmpty) ...[
              _sectionHeading(context, '真实分支冲突'),
              for (final review in state.reconciliationCases)
                _reconciliationCard(context, review),
            ],
            if (state.clockReviewCases.isNotEmpty) ...[
              _sectionHeading(context, '时钟异常'),
              for (final review in state.clockReviewCases)
                _clockReviewCard(context, review),
            ],
            if (state.reconciliationHistory.isNotEmpty ||
                state.clockReviewHistory.isNotEmpty) ...[
              _sectionHeading(context, '已完成的核对'),
              for (final result in state.reconciliationHistory.reversed)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text('已裁决 ${result.cardIds.length} 个节点的分支'),
                    subtitle: Text(
                      '${_dateTime(result.resolvedAt)} · '
                      '采用 ${result.acceptedSourceIds.length} 条来源，'
                      '保留 ${result.retainedSourceIds.length} 条来源记录',
                    ),
                  ),
                ),
              for (final review in state.clockReviewHistory.reversed)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text('已核对${_directionLabel(review.direction)}时钟变更'),
                    subtitle: Text(
                      '${_dateTime(review.detectedAt)} · 连续计时约 '
                      '${review.estimatedElapsedSeconds} 秒 · '
                      '检查点推进至 ${_dateTime(review.reliableThroughTime)}',
                    ),
                  ),
                ),
            ],
            if (state.reconciliationCases.isEmpty &&
                state.clockReviewCases.isEmpty &&
                state.reconciliationHistory.isEmpty &&
                state.clockReviewHistory.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('目前没有待核对记录'),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _sectionHeading(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _reconciliationCard(
    BuildContext context,
    NationalFocusReconciliationCase review,
  ) {
    final selectedSource = _selectedSourceByCase[review.id];
    final affectedCardNames =
        review.cardIds.map((id) => review.cardNames[id] ?? id).toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '涉及节点：${affectedCardNames.join('、')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '检测于 ${_dateTime(review.createdAt)}。请选择一个完整来源分支；'
              '系统会按该分支恢复状态、父子关系及连续统计。',
            ),
            RadioGroup<String>(
              groupValue: selectedSource,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedSourceByCase[review.id] = value);
              },
              child: Column(
                children: [
                  for (final option in review.options)
                    _branchOption(context, review, option),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      selectedSource == null || _busyIds.contains(review.id)
                      ? null
                      : () => _run(review.id, () async {
                          await widget.repository
                              .resolveNationalFocusReconciliation(
                                caseId: review.id,
                                selectedSourceId: selectedSource,
                              );
                        }),
                  icon: const Icon(Icons.check),
                  label: const Text('采用此完整分支'),
                ),
                OutlinedButton(
                  onPressed: _busyIds.contains(review.id)
                      ? null
                      : () => _run(
                          review.id,
                          () => widget.repository
                              .deferNationalFocusReconciliation(review.id),
                        ),
                  child: Text(review.isDeferred ? '仍待处理' : '稍后处理'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchOption(
    BuildContext context,
    NationalFocusReconciliationCase review,
    NationalFocusReconciliationOption option,
  ) {
    final deviceIds = option.operations.map((item) => item.deviceId).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: option.sourceId,
          title: Text(
            '完整分支 ${option.sourceId.length <= 8 ? option.sourceId : option.sourceId.substring(0, 8)}',
          ),
          subtitle: Text(
            '${option.operations.length} 条操作 · ${deviceIds.join('、')}',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final effect in option.effects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_effectLabel(effect, review.cardNames)),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('查看完整来源操作'),
                subtitle: Text('${option.operations.length} 条原始操作记录'),
                children: [
                  for (final operation in option.operations)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(_operationLabel(operation.operation)),
                      subtitle: Text(
                        '${_dateTime(operation.occurredAt)} · ${operation.deviceId}\n'
                        '${operation.effects.map((effect) => _effectLabel(effect, review.cardNames)).join('\n')}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _effectLabel(
    NationalFocusReconciliationCardEffect effect,
    Map<String, String> names,
  ) {
    final name =
        names[effect.cardId] ?? effect.triggerCondition ?? effect.cardId;
    final oldParent = effect.previousParentId == null
        ? '顶层'
        : names[effect.previousParentId] ?? effect.previousParentId!;
    final newParent = effect.newParentId == null
        ? '顶层'
        : names[effect.newParentId] ?? effect.newParentId!;
    final oldState = effect.previousState ?? '无';
    final newState = effect.newState ?? '无';
    final treeLocation =
        effect.previousIsInTree == null && effect.newIsInTree == null
        ? ''
        : '；所在位置 ${effect.previousIsInTree == true ? '树中' : '卡片库'}→${effect.newIsInTree == true ? '树中' : '卡片库'}';
    final successful =
        effect.previousSuccessfulDays == null &&
            effect.newSuccessfulDays == null
        ? ''
        : '；成功日 ${effect.previousSuccessfulDays ?? 0}→${effect.newSuccessfulDays ?? 0}';
    final consecutive =
        effect.previousCurrentConsecutiveDays == null &&
            effect.newCurrentConsecutiveDays == null
        ? ''
        : '；连续日 ${effect.previousCurrentConsecutiveDays ?? 0}→${effect.newCurrentConsecutiveDays ?? 0}';
    final best =
        effect.previousBestConsecutiveDays == null &&
            effect.newBestConsecutiveDays == null
        ? ''
        : '；最高连续日 ${effect.previousBestConsecutiveDays ?? 0}→${effect.newBestConsecutiveDays ?? 0}';
    final cycle =
        effect.previousMaintenanceCycleStarted == null &&
            effect.newMaintenanceCycleStarted == null
        ? ''
        : '；维护周期 ${effect.previousMaintenanceCycleStarted == true ? '已开始' : '未开始'}→${effect.newMaintenanceCycleStarted == true ? '已开始' : '未开始'}';
    final failure = effect.newFailureReason == null
        ? ''
        : '；失败原因 ${effect.newFailureReason}';
    return '$name：$oldState→$newState，父节点 $oldParent→$newParent$treeLocation$successful$consecutive$best$cycle$failure';
  }

  Widget _clockReviewCard(
    BuildContext context,
    NationalFocusClockReviewCase review,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_directionLabel(review.direction)}时钟变更',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text('上次可信时间：${_dateTime(review.previousWallTime)}'),
          Text('设备当前时间：${_dateTime(review.observedWallTime)}'),
          Text('连续计时估算：${review.estimatedElapsedSeconds} 秒'),
          Text('可靠部分最多推进至：${_dateTime(review.reliableThroughTime)}'),
          const SizedBox(height: 8),
          const Text(
            '系统只按连续计时确认的时间结算固定 UTC 20:00 检查点（北京时间 04:00）。'
            '不确定区间不会自动判定成功或失败。',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busyIds.contains(review.id)
                    ? null
                    : () => _run(
                        review.id,
                        () => widget.repository.resolveNationalFocusClockReview(
                          review.id,
                        ),
                      ),
                icon: const Icon(Icons.check),
                label: const Text('按连续计时核对并重算'),
              ),
              OutlinedButton(
                onPressed: _busyIds.contains(review.id)
                    ? null
                    : () => _run(
                        review.id,
                        () => widget.repository.deferNationalFocusClockReview(
                          review.id,
                        ),
                      ),
                child: Text(review.isDeferred ? '仍待处理' : '稍后处理'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _operationLabel(String operation) {
    const labels = <String, String>{
      'create_card': '创建节点',
      'place_card': '调整父子关系',
      'move_to_library': '移出树',
      'light_card': '点亮节点',
      'extinguish_card': '熄灭节点',
      'confirm_today': '确认今日继续',
      'settle_checkpoint': '结算固定检查点',
      'synchronization_merge': '同步合并',
      'resolve_national_focus_reconciliation': '完成分支裁决',
      'resolve_national_focus_clock_review': '完成时钟核对',
    };
    return labels[operation] ?? operation;
  }

  String _directionLabel(NationalFocusClockChangeDirection direction) =>
      direction == NationalFocusClockChangeDirection.forward ? '前跳' : '回拨';

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$minute';
  }
}
