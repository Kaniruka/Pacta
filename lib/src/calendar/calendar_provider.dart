import 'package:flutter/services.dart';

import 'calendar_models.dart';

abstract interface class CalendarProvider {
  bool get isSupported;

  Future<CalendarPermissionState> permissionStatus();
  Future<CalendarPermissionState> requestPermission();
  Future<List<CalendarSource>> listCalendars();
  Future<List<CalendarEventOccurrence>> readEvents({
    required Set<String> sourceIds,
    required DateTime from,
    required DateTime to,
  });
}

class AndroidCalendarProvider implements CalendarProvider {
  const AndroidCalendarProvider({
    this.channel = const MethodChannel('com.pacta/calendar'),
  });

  final MethodChannel channel;

  @override
  bool get isSupported => true;

  @override
  Future<CalendarPermissionState> permissionStatus() async =>
      _permission(await channel.invokeMethod<String>('permissionStatus'));

  @override
  Future<CalendarPermissionState> requestPermission() async =>
      _permission(await channel.invokeMethod<String>('requestPermission'));

  @override
  Future<List<CalendarSource>> listCalendars() async {
    final rows = await channel.invokeListMethod<Object?>('listCalendars') ?? [];
    return [
      for (final row in rows)
        if (row is Map<Object?, Object?>)
          CalendarSource(
            id: row['sourceId'] as String,
            displayName: (row['displayName'] as String?) ?? '未命名日历',
            timeZoneId: (row['timeZoneId'] as String?) ?? 'Etc/UTC',
            localCalendarId: row['localCalendarId']?.toString(),
          ),
    ];
  }

  @override
  Future<List<CalendarEventOccurrence>> readEvents({
    required Set<String> sourceIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final sources = await listCalendars();
    final localIds = [
      for (final source in sources)
        if (sourceIds.contains(source.id) && source.localCalendarId != null)
          int.tryParse(source.localCalendarId!),
    ].whereType<int>().toList();
    if (localIds.isEmpty) return const [];

    final rows =
        await channel.invokeListMethod<Object?>('readEvents', {
          'calendarIds': localIds,
          'from': from.toUtc().millisecondsSinceEpoch,
          'to': to.toUtc().millisecondsSinceEpoch,
        }) ??
        [];
    return [
      for (final row in rows)
        if (row is Map<Object?, Object?>) _eventFromPlatform(row),
    ];
  }

  CalendarEventOccurrence _eventFromPlatform(Map<Object?, Object?> row) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      row['startsAt'] as int,
      isUtc: true,
    );
    final end = DateTime.fromMillisecondsSinceEpoch(
      row['endsAt'] as int,
      isUtc: true,
    );
    return CalendarEventOccurrence(
      sourceId: row['sourceId'] as String,
      sourceEventId: row['sourceEventId'] as String,
      occurrenceId: row['occurrenceId'] as String,
      eventIdentity: row['eventIdentity'] as String,
      title: (row['title'] as String?)?.trim().isNotEmpty == true
          ? (row['title'] as String).trim()
          : '无标题日历块',
      startsAt: start,
      endsAt: end,
      allDay: row['allDay'] as bool,
      allDayStartDate: row['allDayStartDate'] as String?,
      allDayEndDateExclusive: row['allDayEndDateExclusive'] as String?,
      availability: CalendarAvailability.fromName(row['availability']),
      timeZoneId: (row['timeZoneId'] as String?) ?? 'Etc/UTC',
    );
  }

  CalendarPermissionState _permission(String? value) => switch (value) {
    'granted' => CalendarPermissionState.granted,
    'denied' => CalendarPermissionState.denied,
    'unsupported' => CalendarPermissionState.unsupported,
    _ => CalendarPermissionState.unknown,
  };
}

class UnsupportedCalendarProvider implements CalendarProvider {
  const UnsupportedCalendarProvider();

  @override
  bool get isSupported => false;

  @override
  Future<CalendarPermissionState> permissionStatus() async =>
      CalendarPermissionState.unsupported;

  @override
  Future<CalendarPermissionState> requestPermission() async =>
      CalendarPermissionState.unsupported;

  @override
  Future<List<CalendarSource>> listCalendars() async => const [];

  @override
  Future<List<CalendarEventOccurrence>> readEvents({
    required Set<String> sourceIds,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}
