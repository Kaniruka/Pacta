/// Availability reported by the source calendar. Unknown states count as busy.
enum CalendarAvailability {
  busy,
  free,
  tentative,
  unknown;

  static CalendarAvailability fromName(Object? value) => values.firstWhere(
    (availability) => availability.name == value,
    orElse: () => CalendarAvailability.unknown,
  );
}

enum CalendarPermissionState { granted, denied, unknown, unsupported }

class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.displayName,
    required this.timeZoneId,
    this.localCalendarId,
    this.isStale = false,
  });

  /// A stable, opaque identifier shared by devices for the same calendar.
  final String id;
  final String displayName;
  final String timeZoneId;

  /// Android Calendar Provider's local row id. Never sent to the remote store.
  final String? localCalendarId;
  final bool isStale;
}

class CalendarEventOccurrence {
  const CalendarEventOccurrence({
    required this.sourceId,
    required this.sourceEventId,
    required this.occurrenceId,
    required this.eventIdentity,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.availability,
    required this.timeZoneId,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
  });

  final String sourceId;
  final String sourceEventId;

  /// Stable within a source, including the original instance time for repeats.
  final String occurrenceId;

  /// Source-independent key used to collapse the same imported occurrence.
  final String eventIdentity;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;
  final CalendarAvailability availability;
  final String timeZoneId;

  bool get occupiesTime => !allDay && availability != CalendarAvailability.free;
}

class CalendarBlock {
  const CalendarBlock({
    required this.sourceIds,
    required this.sourceNames,
    required this.sourceEventId,
    required this.occurrenceId,
    required this.eventIdentity,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.availability,
    required this.timeZoneId,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
  });

  final List<String> sourceIds;
  final List<String> sourceNames;
  final String sourceEventId;
  final String occurrenceId;
  final String eventIdentity;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;
  final CalendarAvailability availability;
  final String timeZoneId;

  bool get occupiesTime => !allDay && availability != CalendarAvailability.free;

  CalendarBlock withSource({
    required String sourceId,
    required String sourceName,
  }) => CalendarBlock(
    sourceIds: [...sourceIds, sourceId],
    sourceNames: [...sourceNames, sourceName],
    sourceEventId: sourceEventId,
    occurrenceId: occurrenceId,
    eventIdentity: eventIdentity,
    title: title,
    startsAt: startsAt,
    endsAt: endsAt,
    allDay: allDay,
    allDayStartDate: allDayStartDate,
    allDayEndDateExclusive: allDayEndDateExclusive,
    availability: availability,
    timeZoneId: timeZoneId,
  );
}

class CalendarAgenda {
  CalendarAgenda({
    required this.blocks,
    required DateTime from,
    required DateTime to,
    this.isStale = false,
  }) : occupiedDuration = _unionBusyDuration(blocks, from.toUtc(), to.toUtc());

  final List<CalendarBlock> blocks;
  final bool isStale;
  final Duration occupiedDuration;
}

class CalendarImportState {
  const CalendarImportState({
    required this.permission,
    required this.availableSources,
    required this.importedSources,
    this.hasPendingUpdates = false,
  });

  final CalendarPermissionState permission;
  final List<CalendarSource> availableSources;
  final List<CalendarSource> importedSources;
  final bool hasPendingUpdates;

  Set<String> get importedSourceIds => {
    for (final source in importedSources) source.id,
  };
}

class CalendarImportResult {
  const CalendarImportResult({
    required this.importedOccurrences,
    required this.synced,
    this.isStale = false,
  });

  final int importedOccurrences;
  final bool synced;
  final bool isStale;
}

Duration _unionBusyDuration(
  List<CalendarBlock> blocks,
  DateTime from,
  DateTime to,
) {
  final intervals = <(DateTime, DateTime)>[];
  for (final block in blocks) {
    if (!block.occupiesTime ||
        !block.startsAt.toUtc().isBefore(to) ||
        !block.endsAt.toUtc().isAfter(from)) {
      continue;
    }
    final start = block.startsAt.toUtc().isAfter(from)
        ? block.startsAt.toUtc()
        : from;
    final end = block.endsAt.toUtc().isBefore(to) ? block.endsAt.toUtc() : to;
    if (end.isAfter(start)) intervals.add((start, end));
  }
  intervals.sort((left, right) => left.$1.compareTo(right.$1));

  var total = Duration.zero;
  DateTime? activeStart;
  DateTime? activeEnd;
  for (final interval in intervals) {
    final currentStart = activeStart;
    final currentEnd = activeEnd;
    if (currentStart == null || currentEnd == null) {
      activeStart = interval.$1;
      activeEnd = interval.$2;
    } else if (!interval.$1.isAfter(currentEnd)) {
      if (interval.$2.isAfter(currentEnd)) activeEnd = interval.$2;
    } else {
      total += currentEnd.difference(currentStart);
      activeStart = interval.$1;
      activeEnd = interval.$2;
    }
  }
  final lastStart = activeStart;
  final lastEnd = activeEnd;
  if (lastStart != null && lastEnd != null) {
    total += lastEnd.difference(lastStart);
  }
  return total;
}
