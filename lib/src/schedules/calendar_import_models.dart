import 'dart:convert';

import '../calendar/calendar_models.dart';
import 'schedule_models.dart';

/// Serialized identity version for an imported occurrence.
///
/// Version 1 was one namespaced string (`calendar-import/1|<scope>|...`) and
/// could only express a single namespace, so a device-local event and the
/// provider identity that later appeared on the same device row never met.
/// Version 2 stores every alias that proves the occurrence as a structured
/// record, and one persisted copy keeps all of them without rewriting its
/// content.
const int calendarImportIdentityVersion = 2;

const String calendarImportAliasSync = 'sync';
const String calendarImportAliasDevice = 'device';

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
    required List<CalendarImportAlias> identityAliases,
  }) : identityAliases = List.unmodifiable(identityAliases);

  final CalendarEventOccurrence occurrence;
  final String sourceName;

  /// Every alias that proves this occurrence on this installation.
  final List<CalendarImportAlias> identityAliases;

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
  final Map<String, List<CalendarImportAlias>> pendingAliasUpdates;

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

/// One alias that proves an imported occurrence.
///
/// Aliases are structured records, never delimiter-joined: a public source,
/// event, calendar or occurrence id may contain any character, and two
/// different tuples must never encode to the same value.
class CalendarImportAlias {
  const CalendarImportAlias._({
    required this.kind,
    this.sourceId,
    this.sourceEventId,
    this.installId,
    this.calendarId,
    this.deviceRowId,
    this.occurrenceId,
  });

  /// Cross-device provider identity for one event occurrence.
  const CalendarImportAlias.sync({
    required String sourceId,
    required String sourceEventId,
    String? occurrenceId,
  }) : this._(
         kind: calendarImportAliasSync,
         sourceId: sourceId,
         sourceEventId: sourceEventId,
         occurrenceId: occurrenceId,
       );

  /// This installation's own row identity for one event occurrence.
  const CalendarImportAlias.device({
    required String installId,
    required String calendarId,
    required String deviceRowId,
    String? occurrenceId,
  }) : this._(
         kind: calendarImportAliasDevice,
         installId: installId,
         calendarId: calendarId,
         deviceRowId: deviceRowId,
         occurrenceId: occurrenceId,
       );

  final String kind;
  final String? sourceId;
  final String? sourceEventId;
  final String? installId;
  final String? calendarId;
  final String? deviceRowId;

  /// The occurrence this alias names, or null for a single (non-recurring)
  /// event whose start time is not part of its identity.
  final String? occurrenceId;

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (sourceId != null) 'source': sourceId,
    if (sourceEventId != null) 'event': sourceEventId,
    if (installId != null) 'install': installId,
    if (calendarId != null) 'calendar': calendarId,
    if (deviceRowId != null) 'row': deviceRowId,
    if (occurrenceId != null) 'occurrence': occurrenceId,
  };

  String encode() => jsonEncode(toJson());

  /// Whether this persisted alias proves [incoming].
  ///
  /// A single event's start time is not part of its identity, so an incoming
  /// alias without an occurrence matches a persisted one whatever occurrence it
  /// recorded — including the earlier development format that always recorded
  /// one. An incoming recurring occurrence still needs an identical occurrence.
  bool proves(CalendarImportAlias incoming) {
    if (kind != incoming.kind) return false;
    switch (kind) {
      case calendarImportAliasSync:
        if (sourceId != incoming.sourceId ||
            sourceEventId != incoming.sourceEventId) {
          return false;
        }
      case calendarImportAliasDevice:
        if (installId != incoming.installId ||
            calendarId != incoming.calendarId ||
            deviceRowId != incoming.deviceRowId) {
          return false;
        }
      default:
        return false;
    }
    final incomingOccurrence = incoming.occurrenceId;
    if (incomingOccurrence == null) return true;
    return occurrenceId == incomingOccurrence;
  }

  static CalendarImportAlias? fromJson(Object? value) {
    if (value is! Map) return null;
    String? text(Object? raw) =>
        raw is String && raw.trim().isNotEmpty ? raw : null;
    String? optional(Object? raw) {
      if (raw == null) return null;
      return raw is String && raw.isNotEmpty ? raw : '';
    }

    final kind = value['kind'];
    final occurrenceId = optional(value['occurrence']);
    if (occurrenceId == '') return null;
    if (kind == calendarImportAliasSync) {
      final sourceId = text(value['source']);
      final sourceEventId = text(value['event']);
      if (sourceId == null || sourceEventId == null) return null;
      return CalendarImportAlias.sync(
        sourceId: sourceId,
        sourceEventId: sourceEventId,
        occurrenceId: occurrenceId,
      );
    }
    if (kind == calendarImportAliasDevice) {
      final installId = text(value['install']);
      final calendarId = text(value['calendar']);
      final deviceRowId = text(value['row']);
      if (installId == null || calendarId == null || deviceRowId == null) {
        return null;
      }
      return CalendarImportAlias.device(
        installId: installId,
        calendarId: calendarId,
        deviceRowId: deviceRowId,
        occurrenceId: occurrenceId,
      );
    }
    return null;
  }
}

/// Every alias that proves one imported occurrence.
///
/// A provider identity is provable across devices, so it contributes a `sync`
/// alias and equal provider occurrences still deduplicate after a snapshot
/// restore. A recurring event names its occurrence by the original instance
/// start; a single event has no occurrence part, so moving it never changes its
/// identity.
///
/// The platform's own row identity contributes a `device` alias. It is only
/// meaningful together with [deviceProvenance] — the persisted installation
/// identity from `focus_source_devices`, deliberately excluded from business
/// snapshots — never as a bare numeric calendar or event row.
///
/// A copy keeps both aliases as soon as they are known: an event imported while
/// it was still device-local stays deduplicated when Android later assigns a
/// provider id to that same row, and the canonical provider identity then
/// travels to other installations through the business snapshot.
///
/// [deviceProvenance] is required as soon as a `device` alias is produced and
/// ignored for provider occurrences that carry no device row identity.
List<CalendarImportAlias> calendarImportIdentityAliases({
  required CalendarImportSource source,
  required CalendarEventOccurrence occurrence,
  String? deviceProvenance,
}) {
  final aliases = <CalendarImportAlias>[];
  final deviceLocal = calendarImportEventIsDeviceLocal(
    occurrence.sourceEventId,
  );
  if (!deviceLocal) {
    aliases.add(
      CalendarImportAlias.sync(
        sourceId: source.id,
        sourceEventId: occurrence.sourceEventId,
        occurrenceId: occurrence.isRecurring
            ? _occurrenceToken(occurrence)
            : null,
      ),
    );
  }
  final deviceAlias = _deviceAlias(
    source: source,
    occurrence: occurrence,
    deviceProvenance: deviceProvenance,
    deviceLocal: deviceLocal,
  );
  if (deviceAlias != null) aliases.add(deviceAlias);
  return aliases;
}

CalendarImportAlias? _deviceAlias({
  required CalendarImportSource source,
  required CalendarEventOccurrence occurrence,
  required String? deviceProvenance,
  required bool deviceLocal,
}) {
  final reported = occurrence.deviceOccurrenceId?.trim();
  final token = reported != null && reported.isNotEmpty
      ? reported
      : (deviceLocal ? _occurrenceToken(occurrence) : null);
  if (token == null) return null;
  final parts = _splitDeviceOccurrence(token);
  if (parts == null) return null;
  return CalendarImportAlias.device(
    installId: _requireProvenance(deviceProvenance),
    calendarId: source.localCalendarId ?? source.id,
    deviceRowId: parts.$1,
    occurrenceId: parts.$2,
  );
}

String _occurrenceToken(CalendarEventOccurrence occurrence) {
  final token = occurrence.occurrenceId.trim();
  return token.isNotEmpty
      ? token
      : 'start:${occurrence.startsAt.toUtc().toIso8601String()}';
}

/// Splits a device occurrence identity into its row and occurrence parts.
///
/// `local:<row>` is a single event whose start is not part of its identity;
/// `local:<row>@<start>` is one occurrence of a recurring event (or an
/// exception, where the original instance start stays stable).
(String, String?)? _splitDeviceOccurrence(String value) {
  final at = value.indexOf('@');
  if (at < 0) return value.isEmpty ? null : (value, null);
  final row = value.substring(0, at);
  if (row.isEmpty) return null;
  return (row, value);
}

String _requireProvenance(String? deviceProvenance) {
  final provenance = deviceProvenance?.trim() ?? '';
  if (provenance.isEmpty) {
    throw ArgumentError.value(
      deviceProvenance,
      'deviceProvenance',
      'installation identity is required for a device alias',
    );
  }
  return provenance;
}

/// Structured identity stored on a copy.
String encodeCalendarImportIdentity(List<CalendarImportAlias> aliases) =>
    jsonEncode({
      'v': calendarImportIdentityVersion,
      'aliases': [for (final alias in aliases) alias.toJson()],
    });

/// Aliases recorded by one persisted identity.
///
/// Version 2 JSON objects are authoritative. Two earlier development formats are
/// read conservatively and only when their component counts are unambiguous:
/// a version 2 raw pipe alias, and a version 1 identity
/// (`calendar-import/1|sync|…` or `calendar-import/1|device:<install>:<cal>|…`).
/// A version 1 device scope is converted only when its installation equals
/// [deviceProvenance]; a numeric-only legacy scope and any unpublished or
/// malformed payload stay opaque and can never alias another copy.
List<CalendarImportAlias> decodeCalendarImportIdentityAliases(
  String? storedIdentity, {
  String? deviceProvenance,
}) {
  final stored = storedIdentity?.trim() ?? '';
  if (stored.isEmpty) return const [];
  if (stored.startsWith('{')) {
    final List<CalendarImportAlias> aliases = [];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map<String, dynamic> &&
          decoded['v'] == calendarImportIdentityVersion) {
        final raw = decoded['aliases'];
        if (raw is List) {
          for (final entry in raw) {
            final alias = entry is String
                ? _legacyPipeAlias(entry, deviceProvenance: deviceProvenance)
                : CalendarImportAlias.fromJson(entry);
            if (alias != null) aliases.add(alias);
          }
        }
      }
    } on FormatException {
      return const [];
    }
    return aliases;
  }
  final legacy = _legacyPipeAlias(stored, deviceProvenance: deviceProvenance);
  return legacy == null ? const [] : [legacy];
}

CalendarImportAlias? _legacyPipeAlias(
  String stored, {
  String? deviceProvenance,
}) {
  const versionOnePrefix = 'calendar-import/1|';
  if (stored.startsWith(versionOnePrefix)) {
    final parts = stored.substring(versionOnePrefix.length).split('|');
    if (parts.length != 4) return null;
    final scope = parts[0];
    final sourceId = parts[1];
    final sourceEventId = parts[2];
    final occurrence = parts[3];
    if (sourceId.isEmpty || sourceEventId.isEmpty || occurrence.isEmpty) {
      return null;
    }
    if (scope == 'sync') {
      return CalendarImportAlias.sync(
        sourceId: sourceId,
        sourceEventId: sourceEventId,
        occurrenceId: occurrence,
      );
    }
    if (!scope.startsWith('device:')) return null;
    final scopeParts = scope.split(':');
    if (scopeParts.length != 3) return null;
    final installId = scopeParts[1];
    final calendarId = scopeParts[2];
    if (installId.isEmpty || calendarId.isEmpty) return null;
    if (deviceProvenance?.trim() != installId) return null;
    final deviceParts = _splitDeviceOccurrence(occurrence);
    if (deviceParts == null) return null;
    return CalendarImportAlias.device(
      installId: installId,
      calendarId: calendarId,
      deviceRowId: deviceParts.$1,
      occurrenceId: deviceParts.$2,
    );
  }
  final parts = stored.split('|');
  if (parts.length != 4) return null;
  final occurrence = parts[3];
  if (parts[1].isEmpty || parts[2].isEmpty || occurrence.isEmpty) return null;
  if (parts[0] == calendarImportAliasSync) {
    return CalendarImportAlias.sync(
      sourceId: parts[1],
      sourceEventId: parts[2],
      occurrenceId: occurrence,
    );
  }
  if (parts[0] == calendarImportAliasDevice) {
    final deviceParts = _splitDeviceOccurrence(occurrence);
    if (deviceParts == null) return null;
    return CalendarImportAlias.device(
      installId: parts[1],
      calendarId: parts[2],
      deviceRowId: deviceParts.$1,
      occurrenceId: deviceParts.$2,
    );
  }
  return null;
}

/// Identity recorded by the one-time legacy calendar-block promotion.
///
/// Legacy copies kept the provider's raw occurrence identity and a source id
/// list, so a provable match needs both parts.
String calendarImportLegacyIdentityKey({
  required String sourceId,
  required String rawIdentity,
}) => 'legacy|$sourceId|$rawIdentity';
