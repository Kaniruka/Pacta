import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../focus/focus_time_zones.dart';
import '../schedules/calendar_import_models.dart';
import '../schedules/schedule_repository.dart';

/// 计划页的一次性手动导入。
///
/// 只在用户点击时读取系统日历：先预览、再确认，取消任一步都不写任何数据。
/// 导入的副本与源日历无关，之后也不做持续同步；已导入过的项按现有的
/// [ScheduleRepository.previewCalendarImport] / [ScheduleRepository.confirmCalendarImport]
/// 语义跳过，已存在副本的内容不会被覆盖。
///
/// 返回给用户看的结果文案；用户取消或没有可做的事时返回 null。
Future<String?> runPlanManualImport(
  BuildContext context, {
  required CalendarRepository calendar,
  required ScheduleRepository schedules,
  required DateTime now,
  required String displayTimeZoneId,
  DateTime? initialDay,
}) async {
  CalendarImportState state;
  try {
    state = await calendar.loadImportState();
    if (state.permission != CalendarPermissionState.granted) {
      state = await calendar.requestAccess();
    }
  } catch (_) {
    return '系统日历暂时不可用；你自己的安排仍可新建和编辑。';
  }
  if (!context.mounted) return null;

  if (state.permission == CalendarPermissionState.unsupported) {
    return '这台设备暂时不能读取系统日历；你自己的安排仍可新建和编辑。';
  }
  if (state.permission != CalendarPermissionState.granted) {
    return '没有得到日历读取权限；你自己的安排仍可新建和编辑。';
  }
  final sources = state.availableSources;
  if (sources.isEmpty) {
    return '设备中没有可读取的系统日历。';
  }

  final day = initialDay ?? _planDay(displayTimeZoneId, now);
  final selection = await _showSourceDialog(
    context,
    sources: sources,
    day: day,
  );
  if (selection == null || !context.mounted) return null;

  final List<CalendarEventOccurrence> occurrences;
  try {
    occurrences = await calendar.readOccurrences(
      sourceIds: selection.sourceIds,
      from: selection.from,
      to: selection.to,
    );
  } catch (_) {
    return '系统日历读取没有完成；已导入的安排和你自己的安排不受影响。';
  }
  if (!context.mounted) return null;

  final CalendarImportPreview preview;
  try {
    preview = await schedules.previewCalendarImport(
      CalendarImportRequest(
        sources: [
          for (final source in sources)
            if (selection.sourceIds.contains(source.id))
              CalendarImportSource(
                id: source.id,
                displayName: source.displayName,
                localCalendarId: source.localCalendarId,
              ),
        ],
        occurrences: occurrences,
        from: selection.from,
        to: selection.to,
      ),
    );
  } catch (_) {
    return '这次导入没有完成；已有的安排不受影响。';
  }
  if (!context.mounted) return null;

  if (!preview.hasPending && !preview.hasAliasUpdates) {
    return preview.duplicateCount > 0
        ? '所选范围内都是已导入过的安排，已跳过 '
              '${preview.duplicateCount} 项。'
        : '所选范围内没有可导入的安排。';
  }

  final confirmed = await _showPreviewDialog(context, preview: preview);
  if (confirmed != true || !context.mounted) return null;

  try {
    final outcome = await schedules.confirmCalendarImport(preview);
    if (outcome.createdCount > 0) {
      return '已复制 ${outcome.createdCount} 项安排；跳过 '
          '${outcome.skippedDuplicates} 项已经导入过的。';
    }
    return '这些安排此前已经导入过，内容保持原样。';
  } catch (_) {
    return '这次导入没有完成；已有的安排不受影响。';
  }
}

DateTime _planDay(String displayTimeZoneId, DateTime now) {
  final location = FocusTimeZones.location(displayTimeZoneId);
  final zoned = timezone.TZDateTime.from(now.toUtc(), location);
  return DateTime(zoned.year, zoned.month, zoned.day);
}

class _PlanImportSelection {
  const _PlanImportSelection({
    required this.sourceIds,
    required this.from,
    required this.to,
  });

  final Set<String> sourceIds;
  final DateTime from;
  final DateTime to;
}

Future<_PlanImportSelection?> _showSourceDialog(
  BuildContext context, {
  required List<CalendarSource> sources,
  required DateTime day,
}) {
  final selected = <String>{};
  var from = day;
  var to = day.add(const Duration(days: 7));
  return showDialog<_PlanImportSelection>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('从系统日历导入'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择来源日历和日期范围。导入后由 Pacta 保存副本，系统日历不会被修改。'),
                const SizedBox(height: 8),
                for (final source in sources)
                  CheckboxListTile(
                    key: ValueKey('plan-import-source-${source.id}'),
                    value: selected.contains(source.id),
                    title: Text(source.displayName),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(source.id);
                      } else {
                        selected.remove(source.id);
                      }
                    }),
                  ),
                ListTile(
                  key: const Key('plan-import-range'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range_outlined),
                  title: const Text('日期范围'),
                  subtitle: Text(
                    '${_dateText(from)} 至 '
                    '${_dateText(to.subtract(const Duration(days: 1)))}',
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(day.year - 2),
                      lastDate: DateTime(day.year + 3),
                      initialDateRange: DateTimeRange(
                        start: from,
                        end: to.subtract(const Duration(days: 1)),
                      ),
                    );
                    if (picked == null) return;
                    setDialogState(() {
                      from = picked.start;
                      to = picked.end.add(const Duration(days: 1));
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('plan-import-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('plan-import-preview'),
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    _PlanImportSelection(
                      sourceIds: Set<String>.of(selected),
                      from: from,
                      to: to,
                    ),
                  ),
            child: const Text('预览'),
          ),
        ],
      ),
    ),
  );
}

Future<bool?> _showPreviewDialog(
  BuildContext context, {
  required CalendarImportPreview preview,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('确认导入'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将复制 ${preview.pending.length} 项安排'),
          const SizedBox(height: 6),
          Text(
            '已导入过的 ${preview.duplicateCount} 项会跳过：'
            '不会重复添加，也不会覆盖你改过的内容。',
          ),
          if (preview.ignoredCount > 0) ...[
            const SizedBox(height: 6),
            Text('${preview.ignoredCount} 项无法成为安排，会跳过。'),
          ],
          if (preview.pendingAliasUpdates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${preview.pendingAliasUpdates.length} 项此前已导入过，内容保持原样。'),
          ],
          if (preview.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final warning in preview.warnings) Text(warning),
          ],
          const SizedBox(height: 12),
          const Text('导入后这些安排由 Pacta 管理；系统日历不会被修改。'),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('plan-import-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('plan-import-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认导入'),
        ),
      ],
    ),
  );
}

String _dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
