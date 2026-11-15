import 'dart:convert';

import '../calendar/calendar_models.dart';
import 'schedule_models.dart';

/// Serialized identity version for an imported occurrence.
///
/// Version 1 was one namespaced string (`calendar-import/1|<scope>|...`) and
/// could only express a single namespace, so a device-local event and the
/// provider identity that later appeared on the same device row never met.
/// Version 2 stores every alias that proves the occurrence, and one persisted
/// copy keeps all of them without rewriting its content.
const int calendarImportIdentityVersion = 2;

/// One system-calendar source the user picked for a manual import.
///
/// [id] is the provider's cross-device source identity when it has one.
/// [localCalendarId] is the device-local calendar row id. It only helps scope
/// identities of events that carry no provider identity at all, and it is
/// always combined with the persisted installation identity: a bare numeric
/// row id is not a device namespace.
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
  CalendarImportCandidate({
    required this.occurrence,
    required this.sourceName,
    required List<String> identityAliases,
  }) : identityAliases = List.unmodifiable(identityAliases);

  final CalendarEventOccurrence occurrence;
  final String sourceName;

  /// Every alias that proves this occurrence on this installation.
  final List<String> identityAliases;

  /// Structured identity stored on the created copy and compared through
  /// business snapshots.
  String get identityKey => encodeCalendarImportIdentity(identityAliases);
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
    this.pendingAliasUpdates = const {},
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

  /// Aliases learned for copies that already exist, keyed by schedule id.
  ///
  /// A device-local copy stays the same arrangement when the platform later
  /// assigns a provider id to that device row, so the new alias is remembered on
  /// that copy instead of creating another one. Nothing is written here: the
  /// update is applied only by [ScheduleRepository.confirmCalendarImport], so
  /// cancelling a preview still leaves no trace.
  final Map<String, List<String>> pendingAliasUpdates;

  int get totalCount => pending.length + duplicateCount + ignoredCount;

  bool get hasPending => pending.isNotEmpty;

  /// True when confirming would only record identity aliases on existing copies.
  bool get hasAliasUpdates => pendingAliasUpdates.isNotEmpty;
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

/// Every alias that proves one imported occurrence.
///
/// A provider identity is provable across devices, so it contributes a `sync`
/// alias and equal provider occurrences still deduplicate after a snapshot
/// restore.
///
/// The platform's own row identity contributes a `device` alias. It is only
/// meaningful together with [deviceProvenance] — the persisted installation
/// identity from `focus_source_devices`, deliberately excluded from business
/// snapshots — never as a bare numeric calendar or event row. Two installations
/// that happen to reuse the same rows therefore keep distinct copies, while the
/// same installation keeps skipping its own.
///
/// A copy keeps both aliases as soon as they are known: an event imported while
/// it was still device-local stays deduplicated when Android later assigns a
/// provider id to that same row, and the canonical provider identity then
/// travels to other installations through the business snapshot.
///
/// [deviceProvenance] is required as soon as a `device` alias is produced and
/// ignored for provider occurrences that carry no device row identity.
List<String> calendarImportIdentityAliases({
  required CalendarImportSource source,
  required CalendarEventOccurrence occurrence,
  String? deviceProvenance,
}) {
  final aliases = <String>[];
  final deviceLocal = calendarImportEventIsDeviceLocal(
    occurrence.sourceEventId,
  );
  if (!deviceLocal) {
    aliases.add(
      'sync|${source.id}|${occurrence.sourceEventId}|'
      '${_occurrenceToken(occurrence)}',
    );
  }
  final deviceOccurrence = _deviceOccurrenceIdentity(occurrence, deviceLocal);
  if (deviceOccurrence != null) {
    aliases.add(
      'device|${_requireProvenance(deviceProvenance)}|'
      '${source.localCalendarId ?? source.id}|$deviceOccurrence',
    );
  }
  return aliases;
}

String _occurrenceToken(CalendarEventOccurrence occurrence) {
  final token = occurrence.occurrenceId.trim();
  return token.isNotEmpty
      ? token
      : 'start:${occurrence.startsAt.toUtc().toIso8601String()}';
}

/// Device-local occurrence identity reported by the platform, or the fallback
/// occurrence id when the event still has no provider identity.
String? _deviceOccurrenceIdentity(
  CalendarEventOccurrence occurrence,
  bool deviceLocal,
) {
  final reported = occurrence.deviceOccurrenceId?.trim();
  if (reported != null && reported.isNotEmpty) return reported;
  return deviceLocal ? _occurrenceToken(occurrence) : null;
}

String _requireProvenance(String? deviceProvenance) {
  final provenance = deviceProvenance?.trim() ?? '';
  if (provenance.isEmpty || provenance.contains('|')) {
    throw ArgumentError.value(
      deviceProvenance,
      'deviceProvenance',
      'installation identity must be a non-empty key segment',
    );
  }
  return provenance;
}

/// Structured identity stored on a copy.
String encodeCalendarImportIdentity(List<String> aliases) =>
    jsonEncode({'v': calendarImportIdentityVersion, 'aliases': aliases});

/// Aliases recorded by one persisted identity.
///
/// Version 2 JSON is authoritative. A version 1 `sync` scope still proves the
/// same provider occurrence and stays readable as one synced alias. Anything
/// else — a version 1 numeric device scope, a legacy raw occurrence identity, or
/// an unknown payload — stays opaque, so it can never alias another copy.
List<String> decodeCalendarImportIdentityAliases(String? storedIdentity) {
  final stored = storedIdentity?.trim() ?? '';
  if (stored.isEmpty) return const [];
  if (stored.startsWith('{')) {
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map<String, dynamic> &&
          decoded['v'] == calendarImportIdentityVersion) {
        final aliases = decoded['aliases'];
        if (aliases is List) {
          return [
            for (final alias in aliases)
              if (alias is String && alias.trim().isNotEmpty) alias,
          ];
        }
      }
    } on FormatException {
      // Keep the opaque token below.
    }
  }
  const legacySyncPrefix = 'calendar-import/1|sync|';
  if (stored.startsWith(legacySyncPrefix)) {
    return ['sync|${stored.substring(legacySyncPrefix.length)}'];
  }
  return [stored];
}

/// Identity recorded by the one-time legacy calendar-block promotion.
///
/// Legacy copies kept the provider's raw occurrence identity and a source id
/// list, so a provable match needs both parts.
String calendarImportLegacyIdentityKey({
  required String sourceId,
  required String rawIdentity,
}) => 'legacy|$sourceId|$rawIdentity';
