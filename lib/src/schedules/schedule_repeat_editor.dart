import 'package:flutter/material.dart';

import 'schedule_repeat.dart';

/// 用户在一次编辑里选好的重复设置，含"不重复"这一档。
///
/// 只承载用户可配置的三项（频率、星期、结束日期）；时区与窗口模板由调用方
/// 在建规则时注入，界面不读取设备或当前显示时区。
@immutable
class ScheduleRepeatSelection {
  const ScheduleRepeatSelection._({
    required this.repeats,
    required this.frequency,
    required this.weekdays,
    required this.endDate,
  });

  const ScheduleRepeatSelection.none()
    : repeats = false,
      frequency = ScheduleRepeatFrequency.daily,
      weekdays = const {},
      endDate = null;

  const ScheduleRepeatSelection.repeating({
    required this.frequency,
    this.weekdays = const {},
    this.endDate,
  }) : repeats = true;

  /// 从已有设置还原（编辑既有重复日程时使用）。
  factory ScheduleRepeatSelection.fromSpec(ScheduleRepeatSpec? spec) =>
      spec == null
      ? const ScheduleRepeatSelection.none()
      : ScheduleRepeatSelection.repeating(
          frequency: spec.frequency,
          weekdays: spec.weekdays,
          endDate: spec.endDate,
        );

  final bool repeats;
  final ScheduleRepeatFrequency frequency;
  final Set<int> weekdays;
  final String? endDate;

  /// 当前选择能否直接落库。每周至少要选一天；结束日期必须是合法日历日。
  bool get isValid {
    if (!repeats) return true;
    if (frequency == ScheduleRepeatFrequency.weekly &&
        (weekdays.isEmpty || weekdays.any((day) => day < 1 || day > 7))) {
      return false;
    }
    final end = endDate;
    if (end != null && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(end)) {
      return false;
    }
    return true;
  }

  /// 仓储可直接使用的设置；不重复返回 null，非法选择抛 [ArgumentError]。
  ScheduleRepeatSpec? get spec {
    if (!repeats) return null;
    if (!isValid) throw ArgumentError('重复设置不完整，请先补全频率、星期与结束日期。');
    return ScheduleRepeatSpec(
      frequency: frequency,
      weekdays: weekdays,
      endDate: endDate,
    );
  }

  ScheduleRepeatSelection copyWith({
    bool? repeats,
    ScheduleRepeatFrequency? frequency,
    Set<int>? weekdays,
    String? endDate,
    bool clearEndDate = false,
  }) => ScheduleRepeatSelection._(
    repeats: repeats ?? this.repeats,
    frequency: frequency ?? this.frequency,
    weekdays: weekdays ?? this.weekdays,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
  );

  @override
  bool operator ==(Object other) =>
      other is ScheduleRepeatSelection &&
      other.repeats == repeats &&
      other.frequency == frequency &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(
    repeats,
    frequency,
    Object.hashAllUnordered(weekdays),
    endDate,
  );
}

/// 可复用的重复设置控件：不重复 / 每天 / 每周指定星期 / 结束日期。
///
/// 纯表单控件，不含页面、导航或保存动作；07 的计划页与 06 的提醒入口都可直接
/// 嵌入，由调用方决定保存时机与位置。
class ScheduleRepeatEditor extends StatelessWidget {
  const ScheduleRepeatEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.enabled = true,
    this.compact = false,
  });

  final ScheduleRepeatSelection value;
  final ValueChanged<ScheduleRepeatSelection> onChanged;

  /// 结束日期选择器的下界锚点，通常是首个实例的开始日期。
  final DateTime? firstDate;

  final bool enabled;

  /// 紧凑模式只保留开关与一行摘要，适合已有表单的折叠区。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekly = value.frequency == ScheduleRepeatFrequency.weekly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          contentPadding: compact ? EdgeInsets.zero : null,
          dense: compact,
          title: const Text('重复'),
          subtitle: Text(value.repeats ? _summary() : '不重复，只发生这一次'),
          value: value.repeats,
          onChanged: enabled
              ? (on) => onChanged(
                  on
                      ? value.copyWith(repeats: true)
                      : const ScheduleRepeatSelection.none(),
                )
              : null,
        ),
        if (value.repeats && !compact) ...[
          const SizedBox(height: 4),
          SegmentedButton<ScheduleRepeatFrequency>(
            segments: const [
              ButtonSegment(
                value: ScheduleRepeatFrequency.daily,
                label: Text('每天'),
              ),
              ButtonSegment(
                value: ScheduleRepeatFrequency.weekly,
                label: Text('每周'),
              ),
            ],
            selected: {value.frequency},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (selected) {
                    final next = selected.first;
                    onChanged(
                      value.copyWith(
                        frequency: next,
                        // 每天不携带星期集合；切回每周时从空集合重新选。
                        weekdays: next == ScheduleRepeatFrequency.daily
                            ? const {}
                            : value.weekdays,
                      ),
                    );
                  }
                : null,
          ),
          if (weekly) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final day in weekdayLabels.keys)
                  FilterChip(
                    label: Text('周${weekdayLabels[day]}'),
                    selected: value.weekdays.contains(day),
                    onSelected: enabled
                        ? (selected) => onChanged(
                            value.copyWith(
                              weekdays: {...value.weekdays, if (selected) day}
                                ..removeWhere(
                                  (existing) => !selected && existing == day,
                                ),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
            if (!value.isValid)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '每周至少选一天',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: enabled ? () => _pickEndDate(context) : null,
                icon: const Icon(Icons.event_repeat),
                label: Text(value.endDate ?? '不结束'),
              ),
              if (value.endDate != null)
                IconButton(
                  key: const ValueKey('schedule-repeat-clear-end'),
                  tooltip: '清除结束日期',
                  icon: const Icon(Icons.close),
                  onPressed: enabled
                      ? () => onChanged(value.copyWith(clearEndDate: true))
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _summary() {
    final end = value.endDate;
    final tail = end == null ? '不结束' : '至 $end';
    if (value.frequency == ScheduleRepeatFrequency.daily) return '每天，$tail';
    final days = value.weekdays.toList()..sort();
    final labels = days.map((day) => '周${weekdayLabels[day]}').join('、');
    return '每周 $labels，$tail';
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final anchor = firstDate ?? DateTime.now();
    final first = DateUtils.dateOnly(anchor);
    final parsed = value.endDate == null
        ? null
        : DateTime.tryParse(value.endDate!);
    final initial = parsed == null || parsed.isBefore(first) ? first : parsed;
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      initialDate: initial,
      lastDate: DateTime(first.year + 5, 12, 31),
      helpText: '选择结束日期',
    );
    if (picked == null) return;
    onChanged(
      value.copyWith(
        endDate: formatRecurrenceDate(
          DateTime.utc(picked.year, picked.month, picked.day),
        ),
      ),
    );
  }
}

/// 修改重复日程时的范围选择：仅本次、本次及以后。
///
/// 与编辑表单分离，07 的日程详情或编辑弹窗可直接复用；选择值原样传给
/// ScheduleRepository.editRecurringSchedule。
class ScheduleRepeatScopeSelector extends StatelessWidget {
  const ScheduleRepeatScopeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ScheduleRepeatScope value;
  final ValueChanged<ScheduleRepeatScope> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('修改范围', style: theme.textTheme.titleSmall),
        ),
        _tile(
          scope: ScheduleRepeatScope.onlyThis,
          title: '仅本次',
          subtitle: '只改这一个实例，其他实例保持原样',
        ),
        _tile(
          scope: ScheduleRepeatScope.thisAndFuture,
          title: '本次及以后',
          subtitle: '从这次起改用新规则，已过去的不变',
        ),
      ],
    );
  }

  Widget _tile({
    required ScheduleRepeatScope scope,
    required String title,
    required String subtitle,
  }) {
    final selected = value == scope;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: enabled ? () => onChanged(scope) : null,
    );
  }
}
