import '../calendar/calendar_models.dart';
import 'schedule_models.dart';

/// Version prefix for import identities. Bump only with a documented
/// migration: identities are compared across devices through snapshots.
const String calendarImportIdentityPrefix = 'calendar-import/1';

/// One system-calendar source the user picked for a manual import.
///
/// [id] is the provider's cross-device source identity when it has one.
/// [localCalendarId] is the device-local calendar row id and is only used to
/// scope identities of events that carry no provider identity at all.
class CalendarImportSource {
  const CalendarImportSource({
    required this.id,
    this.displayName = '',
    this.localCalendarId,
  });

  final String id;
  final String displayName;
  final String? localCalendarId;
}

/// The occurrence range the user asked to preview or import.
class CalendarImportRequest {
  const CalendarImportRequest({
    required this.sources,
    required this.occurrences,
    required this.from,
    required this.to,
  });

  final List<CalendarImportSource> sources;
  final List<CalendarEventOccurrence> occurrences;
  final DateTime from;
  final DateTime to;

  CalendarImportSource? sourceFor(String sourceId) {
    for (final source in sources) {
      if (source.id == sourceId) return source;
    }
    return null;
  }
}

/// One occurrence that would be written as a new owned copy.
class CalendarImportCandidate {
  const CalendarImportCandidate({
    required this.occurrence,
    required this.sourceName,
    required this.identityKey,
  });

  final CalendarEventOccurrence occurrence;
  final String sourceName;

  /// Namespaced deduplication key stored as the copy's identity.
  final String identityKey;
}

/// Result of reading the selected range. Producing one writes no schedule.
class CalendarImportPreview {
  const CalendarImportPreview({
    required this.from,
    required this.to,
    required this.pending,
    required this.duplicateCount,
    required this.ignoredCount,
    this.warnings = const [],
  });

  final DateTime from;
  final DateTime to;

  /// Occurrences that confirm would create.
  final List<CalendarImportCandidate> pending;

  /// Occurrences already owned by an imported or legacy copy.
  final int duplicateCount;

  /// Occurrences that cannot become a usable arrangement.
  final int ignoredCount;

  final List<String> warnings;

  int get totalCount => pending.length + duplicateCount + ignoredCount;

  bool get hasPending => pending.isNotEmpty;
}

/// Outcome of confirming a preview.
class CalendarImportOutcome {
  const CalendarImportOutcome({
    required this.created,
    required this.skippedDuplicates,
  });

  final List<Schedule> created;
  final int skippedDuplicates;

  int get createdCount => created.length;
}

/// Whether [sourceEventId] is a device-local fallback rather than a provider
/// identity shared across devices.
bool calendarImportEventIsDeviceLocal(String sourceEventId) =>
    sourceEventId.startsWith('local:');

/// Namespaced identity for one imported occurrence.
///
/// The key always names a source so two providers (or two calendars) that use
/// the same raw event id never collapse into one copy. Device-local fallback
/// ids are additionally scoped by the device-local calendar row, because a
/// numeric provider row id is only unique on the device that produced it.
String calendarImportIdentityKey({
  required CalendarImportSource source,
  required CalendarEventOccurrence occurrence,
}) {
  final deviceLocal = calendarImportEventIsDeviceLocal(
    occurrence.sourceEventId,
  );
  final scope = deviceLocal
      ? 'device:${source.localCalendarId ?? source.id}'
      : 'sync';
  final token = occurrence.occurrenceId.trim().isNotEmpty
      ? occurrence.occurrenceId.trim()
      : 'start:${occurrence.startsAt.toUtc().toIso8601String()}';
  return '$calendarImportIdentityPrefix|$scope|${source.id}|'
      '${occurrence.sourceEventId}|$token';
}

/// Identity recorded by the one-time legacy calendar-block promotion.
///
/// Legacy copies kept the provider's raw occurrence identity and a source id
/// list, so a provable match needs both parts.
String calendarImportLegacyIdentityKey({
  required String sourceId,
  required String rawIdentity,
}) => 'legacy|$sourceId|$rawIdentity';
