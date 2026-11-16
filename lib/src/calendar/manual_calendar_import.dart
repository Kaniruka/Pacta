import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import '../schedules/calendar_import_models.dart';
import '../schedules/schedule_repository.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

/// 手动导入系统日历的共享流程：计划页与“我的 → 日历块”使用同一套来源选择、
/// 预览、确认与文案。
///
/// 只做一次性复制：预览不写任何数据，确认后由 [ScheduleRepository] 跳过已
/// 导入过的项，已存在的副本保持用户改过的内容。系统日历始终只读，导入之后
/// 也不做持续同步。
///
/// 日期选择是**账号显示时区的公民日（civil date）**，不是设备本地时刻：
/// 查询边界由 [calendarZoneRange] 在该时区构造，全天事件按原始日期字段
/// （或 UTC 哨兵日的公民日）判断，避免负时区把次日、正时区把前日多导进来。
///
/// 返回给用户看的结果文案；用户取消或无事可做时返回 null。
Future<String?> runManualCalendarImport(
  BuildContext context, {
  required CalendarRepository calendar,
  required ScheduleRepository schedules,
  required String displayTimeZoneId,
  required DateTime now,
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

  final firstDay = _civilDate(
    initialDay ?? accountToday(displayTimeZoneId, now),
  );
  final selection = await _showSourceDialog(
    context,
    sources: sources,
    firstDay: firstDay,
  );
  if (selection == null || !context.mounted) return null;

  final exact = calendarZoneRange(
    displayTimeZoneId: displayTimeZoneId,
    firstDay: selection.firstDay,
    lastDayInclusive: selection.lastDayInclusive,
  );
  final query = calendarImportQueryRange(
    displayTimeZoneId: displayTimeZoneId,
    firstDay: selection.firstDay,
    lastDayInclusive: selection.lastDayInclusive,
  );

  final List<CalendarEventOccurrence> fetched;
  try {
    fetched = await calendar.readOccurrences(
      sourceIds: selection.sourceIds,
      from: query.from,
      to: query.to,
    );
  } catch (_) {
    return '系统日历读取没有完成；已导入的安排和你自己的安排不受影响。';
  }
  if (!context.mounted) return null;

  final occurrences = occurrencesWithinAccountDays(
    fetched,
    displayTimeZoneId: displayTimeZoneId,
    firstDay: selection.firstDay,
    lastDayInclusive: selection.lastDayInclusive,
  );

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
        from: exact.from,
        to: exact.toExclusive,
      ),
    );
  } catch (_) {
    return '这次导入没有完成；已有的安排不受影响。';
  }
  if (!context.mounted) return null;

  if (!preview.hasPending && !preview.hasAliasUpdates) {
    return preview.duplicateCount > 0
        ? '所选范围内都是已导入过的安排，已跳过 ${preview.duplicateCount} 项。'
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

/// 账号显示时区里的“今天”，只取公民日。
DateTime accountToday(String displayTimeZoneId, DateTime now) {
  final location = FocusTimeZones.location(displayTimeZoneId);
  final zoned = timezone.TZDateTime.from(now.toUtc(), location);
  return DateTime.utc(zoned.year, zoned.month, zoned.day);
}

/// 把所选公民日区间换成账号时区的 UTC 半开区间。
///
/// 结束边界是“结束日的次日 00:00”在该时区的瞬时；夏令时按日历加一天，
/// 不使用固定 24 小时，因此春季缺口/秋季回拨都不会偏移边界。
({DateTime from, DateTime toExclusive}) calendarZoneRange({
  required String displayTimeZoneId,
  required DateTime firstDay,
  required DateTime lastDayInclusive,
}) {
  final location = FocusTimeZones.location(displayTimeZoneId);
  DateTime zonedStart(DateTime civil) =>
      timezone.TZDateTime(location, civil.year, civil.month, civil.day).toUtc();
  final firstCivil = _civilDate(firstDay);
  final endCivil = _civilDate(
    DateTime.utc(
      lastDayInclusive.year,
      lastDayInclusive.month,
      lastDayInclusive.day + 1,
    ),
  );
  return (from: zonedStart(firstCivil), toExclusive: zonedStart(endCivil));
}

/// 提供给平台读取的查询区间：两侧各放宽一个 UTC 日，用来接住全天事件的
/// UTC 午夜哨兵（Android 以整天 00:00Z 表示），再按公民日精确过滤。
({DateTime from, DateTime to}) calendarImportQueryRange({
  required String displayTimeZoneId,
  required DateTime firstDay,
  required DateTime lastDayInclusive,
}) {
  final exact = calendarZoneRange(
    displayTimeZoneId: displayTimeZoneId,
    firstDay: firstDay,
    lastDayInclusive: lastDayInclusive,
  );
  return (
    from: exact.from.subtract(const Duration(days: 1)),
    to: exact.toExclusive.add(const Duration(days: 1)),
  );
}

/// 只保留真正落在所选公民日内的发生项。
///
/// 定时事件按 UTC 半开区间重叠判断；全天事件改看原始日期字段，缺失时退回
/// 开始/结束时刻的 UTC 公民日，绝不用本地时区或瞬时边界推断。
List<CalendarEventOccurrence> occurrencesWithinAccountDays(
  Iterable<CalendarEventOccurrence> occurrences, {
  required String displayTimeZoneId,
  required DateTime firstDay,
  required DateTime lastDayInclusive,
}) {
  final exact = calendarZoneRange(
    displayTimeZoneId: displayTimeZoneId,
    firstDay: firstDay,
    lastDayInclusive: lastDayInclusive,
  );
  final firstCivil = _civilDate(firstDay);
  final endCivil = _civilDate(
    DateTime.utc(
      lastDayInclusive.year,
      lastDayInclusive.month,
      lastDayInclusive.day + 1,
    ),
  );
  return [
    for (final occurrence in occurrences)
      if (_withinSelection(
        occurrence,
        firstCivil: firstCivil,
        endCivil: endCivil,
        from: exact.from,
        toExclusive: exact.toExclusive,
      ))
        occurrence,
  ];
}

bool _withinSelection(
  CalendarEventOccurrence occurrence, {
  required DateTime firstCivil,
  required DateTime endCivil,
  required DateTime from,
  required DateTime toExclusive,
}) {
  if (!occurrence.allDay) {
    // 定时事件是瞬时区间：只保留与账号时区半开区间真实重叠的项。
    return occurrence.startsAt.toUtc().isBefore(toExclusive) &&
        occurrence.endsAt.toUtc().isAfter(from);
  }
  final start = _allDayStartCivil(occurrence);
  final end = _allDayEndCivil(occurrence, start);
  return start.isBefore(endCivil) && end.isAfter(firstCivil);
}

DateTime _allDayStartCivil(CalendarEventOccurrence occurrence) {
  final text = occurrence.allDayStartDate;
  if (text != null) {
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      return DateTime.utc(parsed.year, parsed.month, parsed.day);
    }
  }
  return _utcCivil(occurrence.startsAt);
}

DateTime _allDayEndCivil(
  CalendarEventOccurrence occurrence,
  DateTime startCivil,
) {
  final text = occurrence.allDayEndDateExclusive;
  if (text != null) {
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      final end = DateTime.utc(parsed.year, parsed.month, parsed.day);
      if (end.isAfter(startCivil)) return end;
    }
  }
  final sentinel = _utcCivil(occurrence.endsAt);
  return sentinel.isAfter(startCivil)
      ? sentinel
      : DateTime.utc(startCivil.year, startCivil.month, startCivil.day + 1);
}

DateTime _utcCivil(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime _civilDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

class _ImportSelection {
  const _ImportSelection({
    required this.sourceIds,
    required this.firstDay,
    required this.lastDayInclusive,
  });

  final Set<String> sourceIds;
  final DateTime firstDay;
  final DateTime lastDayInclusive;
}

Future<_ImportSelection?> _showSourceDialog(
  BuildContext context, {
  required List<CalendarSource> sources,
  required DateTime firstDay,
}) {
  final selected = <String>{};
  var start = _civilDate(firstDay);
  var lastInclusive = DateTime.utc(start.year, start.month, start.day + 6);
  return showDialog<_ImportSelection>(
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
                    key: ValueKey('calendar-import-source-${source.id}'),
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
                  key: const Key('calendar-import-range'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range_outlined),
                  title: const Text('日期范围'),
                  subtitle: Text(
                    '${_dateText(start)} 至 ${_dateText(lastInclusive)}',
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(start.year - 2),
                      lastDate: DateTime(start.year + 3),
                      initialDateRange: DateTimeRange(
                        start: DateTime(start.year, start.month, start.day),
                        end: DateTime(
                          lastInclusive.year,
                          lastInclusive.month,
                          lastInclusive.day,
                        ),
                      ),
                    );
                    if (picked == null) return;
                    setDialogState(() {
                      start = DateTime.utc(
                        picked.start.year,
                        picked.start.month,
                        picked.start.day,
                      );
                      lastInclusive = DateTime.utc(
                        picked.end.year,
                        picked.end.month,
                        picked.end.day,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('calendar-import-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('calendar-import-preview'),
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    _ImportSelection(
                      sourceIds: Set<String>.of(selected),
                      firstDay: start,
                      lastDayInclusive: lastInclusive,
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
          key: const Key('calendar-import-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('calendar-import-confirm'),
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
