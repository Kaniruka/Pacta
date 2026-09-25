import 'dart:async';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tasks/task_database.dart';
import 'calendar_models.dart';
import 'calendar_provider.dart';

class CalendarRemoteSnapshot {
  const CalendarRemoteSnapshot({
    this.sources = const [],
    this.events = const [],
  });

  final List<CalendarSource> sources;
  final List<CalendarEventOccurrence> events;
}

abstract interface class CalendarRemoteDataSource {
  Future<CalendarRemoteSnapshot> pull({required String userId});
  Future<void> upsertSources({
    required String userId,
    required List<CalendarSource> sources,
  });
  Future<void> upsertEvents({
    required String userId,
    required List<CalendarEventOccurrence> events,
  });
}

class UnavailableCalendarRemoteDataSource implements CalendarRemoteDataSource {
  const UnavailableCalendarRemoteDataSource();

  StateError _notConfigured() => StateError('当前未配置 Supabase，日历块将先保存在本机。');

  @override
  Future<CalendarRemoteSnapshot> pull({required String userId}) async =>
      throw _notConfigured();

  @override
  Future<void> upsertSources({
    required String userId,
    required List<CalendarSource> sources,
  }) async => throw _notConfigured();

  @override
  Future<void> upsertEvents({
    required String userId,
    required List<CalendarEventOccurrence> events,
  }) async => throw _notConfigured();
}

abstract interface class CalendarRepository {
  Future<CalendarImportState> loadImportState();
  Future<CalendarImportState> requestAccess();
  Future<CalendarImportResult> importCalendars(Set<String> sourceIds);
  Future<CalendarAgenda> getAgenda({
    required DateTime from,
    required DateTime to,
  });
  Stream<CalendarAgenda> watchAgenda({
    required DateTime from,
    required DateTime to,
  });
  Future<void> sync();
  Future<void> dispose();
}

class UnavailableCalendarRepository implements CalendarRepository {
  const UnavailableCalendarRepository();

  @override
  Future<CalendarImportState> loadImportState() async =>
      const CalendarImportState(
        permission: CalendarPermissionState.unsupported,
        availableSources: [],
        importedSources: [],
      );

  @override
  Future<CalendarImportState> requestAccess() => loadImportState();

  @override
  Future<CalendarImportResult> importCalendars(Set<String> sourceIds) async =>
      throw UnsupportedError('当前日历功能暂不可用。');

  @override
  Future<CalendarAgenda> getAgenda({
    required DateTime from,
    required DateTime to,
  }) async => CalendarAgenda(blocks: const [], from: from, to: to);

  @override
  Stream<CalendarAgenda> watchAgenda({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield CalendarAgenda(blocks: const [], from: from, to: to);
  }

  @override
  Future<void> sync() async => throw StateError('当前日历同步未配置。');

  @override
  Future<void> dispose() async {}
}

class LocalCalendarRepository implements CalendarRepository {
  LocalCalendarRepository({
    required this.database,
    required this.userId,
    required this.provider,
    required this.remote,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PactaDatabase database;
  final String userId;
  final CalendarProvider provider;
  final CalendarRemoteDataSource remote;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<CalendarImportState> loadImportState() async {
    final permission = provider.isSupported
        ? await provider.permissionStatus()
        : CalendarPermissionState.unsupported;
    final availableSources = permission == CalendarPermissionState.granted
        ? await provider.listCalendars()
        : const <CalendarSource>[];
    return CalendarImportState(
      permission: permission,
      availableSources: availableSources,
      importedSources: provider.isSupported
          ? await _selectedSources()
          : await _allSources(),
    );
  }

  @override
  Future<CalendarImportState> requestAccess() async {
    final permission = provider.isSupported
        ? await provider.requestPermission()
        : CalendarPermissionState.unsupported;
    final availableSources = permission == CalendarPermissionState.granted
        ? await provider.listCalendars()
        : const <CalendarSource>[];
    return CalendarImportState(
      permission: permission,
      availableSources: availableSources,
      importedSources: provider.isSupported
          ? await _selectedSources()
          : await _allSources(),
    );
  }

  @override
  Future<CalendarImportResult> importCalendars(Set<String> sourceIds) async {
    if (!provider.isSupported) {
      throw UnsupportedError('请在 Android 设备上选择系统日历。');
    }
    if (sourceIds.isEmpty) {
      return const CalendarImportResult(importedOccurrences: 0, synced: true);
    }
    if (await provider.permissionStatus() != CalendarPermissionState.granted) {
      throw StateError('尚未获得读取日历权限。');
    }

    final available = await provider.listCalendars();
    final selected = [
      for (final source in available)
        if (sourceIds.contains(source.id)) source,
    ];
    if (selected.length != sourceIds.length) {
      throw ArgumentError('所选日历已不可用，请重新选择。');
    }

    final importAt = _now().toUtc();
    await database.transaction(() async {
      for (final source in selected) {
        await _saveSource(source, isSelected: true, updatedAt: importAt);
      }
    });

    final from = DateTime(
      _now().year,
      _now().month,
      _now().day,
    ).subtract(const Duration(days: 30));
    final to = DateTime(
      _now().year,
      _now().month,
      _now().day,
    ).add(const Duration(days: 91));
    final imported = await provider.readEvents(
      sourceIds: {for (final source in selected) source.id},
      from: from,
      to: to,
    );
    final selectedIds = {for (final source in selected) source.id};
    final sourcesById = {for (final source in selected) source.id: source};
    await database.transaction(() async {
      for (final event in imported) {
        if (!selectedIds.contains(event.sourceId) ||
            !sourcesById.containsKey(event.sourceId)) {
          continue;
        }
        _validateOccurrence(event);
        await _saveEvent(event, updatedAt: importAt);
      }
    });
    await _publish();

    // Event-source removal and change reconciliation are handled by Ticket 21.
    var synced = true;
    try {
      await sync();
    } catch (_) {
      synced = false;
    }
    return CalendarImportResult(
      importedOccurrences: imported.length,
      synced: synced,
    );
  }

  @override
  Future<CalendarAgenda> getAgenda({
    required DateTime from,
    required DateTime to,
  }) async {
    final sourceRows = await (database.select(
      database.localCalendarSources,
    )..where((source) => source.userId.equals(userId))).get();
    final sourceNames = {
      for (final row in sourceRows) row.sourceId: row.displayName,
    };
    final eventRows =
        await (database.select(database.localCalendarBlocks)
              ..where((event) => event.userId.equals(userId))
              ..orderBy([(event) => OrderingTerm(expression: event.startsAt)]))
            .get();
    final byIdentity = <String, CalendarBlock>{};
    for (final row in eventRows) {
      final event = _occurrenceFromRow(row);
      if (!_overlaps(event, from, to)) continue;
      final current = byIdentity[event.eventIdentity];
      if (current == null) {
        byIdentity[event.eventIdentity] = CalendarBlock(
          sourceIds: [event.sourceId],
          sourceNames: [sourceNames[event.sourceId] ?? '日历'],
          sourceEventId: event.sourceEventId,
          occurrenceId: event.occurrenceId,
          eventIdentity: event.eventIdentity,
          title: event.title,
          startsAt: event.startsAt,
          endsAt: event.endsAt,
          allDay: event.allDay,
          allDayStartDate: event.allDayStartDate,
          allDayEndDateExclusive: event.allDayEndDateExclusive,
          availability: event.availability,
          timeZoneId: event.timeZoneId,
        );
      } else if (!current.sourceIds.contains(event.sourceId)) {
        byIdentity[event.eventIdentity] = current.withSource(
          sourceId: event.sourceId,
          sourceName: sourceNames[event.sourceId] ?? '日历',
        );
      }
    }
    final blocks = byIdentity.values.toList()
      ..sort((left, right) {
        final leftStart = left.allDay
            ? DateTime.parse('${left.allDayStartDate}T00:00:00Z')
            : left.startsAt;
        final rightStart = right.allDay
            ? DateTime.parse('${right.allDayStartDate}T00:00:00Z')
            : right.startsAt;
        return leftStart.compareTo(rightStart);
      });
    return CalendarAgenda(blocks: blocks, from: from, to: to);
  }

  @override
  Stream<CalendarAgenda> watchAgenda({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield await getAgenda(from: from, to: to);
    await for (final _ in _changes.stream) {
      yield await getAgenda(from: from, to: to);
    }
  }

  @override
  Future<void> sync() async {
    final sourceRows = await (database.select(
      database.localCalendarSources,
    )..where((source) => source.userId.equals(userId))).get();
    final eventRows = await (database.select(
      database.localCalendarBlocks,
    )..where((event) => event.userId.equals(userId))).get();
    final localSources = [for (final row in sourceRows) _sourceFromRow(row)];
    final localEvents = [for (final row in eventRows) _occurrenceFromRow(row)];

    // Upload first so a newly imported offline Calendar Block reaches another
    // device before applying the remote snapshot to this local cache.
    if (localSources.isNotEmpty) {
      await remote.upsertSources(userId: userId, sources: localSources);
    }
    if (localEvents.isNotEmpty) {
      await remote.upsertEvents(userId: userId, events: localEvents);
    }
    final snapshot = await remote.pull(userId: userId);
    await database.transaction(() async {
      for (final source in snapshot.sources) {
        await _saveSource(source, updatedAt: _now().toUtc());
      }
      for (final event in snapshot.events) {
        _validateOccurrence(event);
        final existing = await _findEvent(event.sourceId, event.occurrenceId);
        if (existing == null) {
          await _saveEvent(event, updatedAt: _now().toUtc());
        }
      }
    });
    await _publish();
  }

  Future<List<CalendarSource>> _selectedSources() async {
    final rows =
        await (database.select(database.localCalendarSources)
              ..where((source) => source.userId.equals(userId))
              ..where((source) => source.isSelected.equals(true))
              ..orderBy([
                (source) => OrderingTerm(expression: source.displayName),
              ]))
            .get();
    return [for (final row in rows) _sourceFromRow(row)];
  }

  Future<List<CalendarSource>> _allSources() async {
    final rows =
        await (database.select(database.localCalendarSources)
              ..where((source) => source.userId.equals(userId))
              ..orderBy([
                (source) => OrderingTerm(expression: source.displayName),
              ]))
            .get();
    return [for (final row in rows) _sourceFromRow(row)];
  }

  Future<void> _saveSource(
    CalendarSource source, {
    bool? isSelected,
    required DateTime updatedAt,
  }) async {
    final existing =
        await (database.select(database.localCalendarSources)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.sourceId.equals(source.id)))
            .getSingleOrNull();
    await database
        .into(database.localCalendarSources)
        .insertOnConflictUpdate(
          LocalCalendarSourcesCompanion.insert(
            userId: userId,
            sourceId: source.id,
            displayName: source.displayName,
            timeZoneId: source.timeZoneId,
            localCalendarId: Value(
              source.localCalendarId ?? existing?.localCalendarId,
            ),
            isSelected: Value(isSelected ?? existing?.isSelected ?? false),
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> _saveEvent(
    CalendarEventOccurrence event, {
    required DateTime updatedAt,
  }) async {
    await database
        .into(database.localCalendarBlocks)
        .insertOnConflictUpdate(
          LocalCalendarBlocksCompanion.insert(
            userId: userId,
            sourceId: event.sourceId,
            sourceEventId: event.sourceEventId,
            occurrenceId: event.occurrenceId,
            eventIdentity: event.eventIdentity,
            title: event.title,
            startsAt: event.startsAt.toUtc(),
            endsAt: event.endsAt.toUtc(),
            allDay: Value(event.allDay),
            allDayStartDate: Value(event.allDayStartDate),
            allDayEndDateExclusive: Value(event.allDayEndDateExclusive),
            availability: event.availability.name,
            timeZoneId: event.timeZoneId,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<LocalCalendarBlock?> _findEvent(
    String sourceId,
    String occurrenceId,
  ) =>
      (database.select(database.localCalendarBlocks)
            ..where((event) => event.userId.equals(userId))
            ..where((event) => event.sourceId.equals(sourceId))
            ..where((event) => event.occurrenceId.equals(occurrenceId)))
          .getSingleOrNull();

  Future<void> _publish() async {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _validateOccurrence(CalendarEventOccurrence event) {
    if (event.sourceId.isEmpty ||
        event.sourceEventId.isEmpty ||
        event.occurrenceId.isEmpty ||
        event.eventIdentity.isEmpty ||
        event.title.trim().isEmpty ||
        !event.endsAt.isAfter(event.startsAt)) {
      throw ArgumentError('日历块缺少来源、标题或有效时间。');
    }
    if (event.allDay &&
        (event.allDayStartDate == null ||
            event.allDayEndDateExclusive == null ||
            event.allDayEndDateExclusive!.compareTo(event.allDayStartDate!) <=
                0)) {
      throw ArgumentError('全天日历块必须提供有效的原始日期范围。');
    }
  }

  bool _overlaps(CalendarEventOccurrence event, DateTime from, DateTime to) {
    if (event.allDay) {
      final fromDate = _dateKey(from);
      final toDate = _dateKey(to);
      return event.allDayStartDate!.compareTo(toDate) < 0 &&
          event.allDayEndDateExclusive!.compareTo(fromDate) > 0;
    }
    return event.startsAt.isBefore(to) && event.endsAt.isAfter(from);
  }

  CalendarSource _sourceFromRow(LocalCalendarSource row) => CalendarSource(
    id: row.sourceId,
    displayName: row.displayName,
    timeZoneId: row.timeZoneId,
    localCalendarId: row.localCalendarId,
  );

  CalendarEventOccurrence _occurrenceFromRow(LocalCalendarBlock row) =>
      CalendarEventOccurrence(
        sourceId: row.sourceId,
        sourceEventId: row.sourceEventId,
        occurrenceId: row.occurrenceId,
        eventIdentity: row.eventIdentity,
        title: row.title,
        startsAt: row.startsAt.toUtc(),
        endsAt: row.endsAt.toUtc(),
        allDay: row.allDay,
        allDayStartDate: row.allDayStartDate,
        allDayEndDateExclusive: row.allDayEndDateExclusive,
        availability: CalendarAvailability.fromName(row.availability),
        timeZoneId: row.timeZoneId,
      );

  @override
  Future<void> dispose() async => _changes.close();
}

class SupabaseCalendarRemoteDataSource implements CalendarRemoteDataSource {
  SupabaseCalendarRemoteDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<CalendarRemoteSnapshot> pull({required String userId}) async {
    final sourceRows = await _selectAll('calendar_sources', userId);
    final eventRows = await _selectAll('calendar_blocks', userId);
    return CalendarRemoteSnapshot(
      sources: [
        for (final row in sourceRows)
          CalendarSource(
            id: row['source_id'] as String,
            displayName: row['display_name'] as String,
            timeZoneId: row['time_zone_id'] as String,
          ),
      ],
      events: [for (final row in eventRows) _eventFromJson(row)],
    );
  }

  Future<List<Map<String, dynamic>>> _selectAll(
    String table,
    String userId,
  ) async {
    const pageSize = 500;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await client
          .from(table)
          .select()
          .eq('user_id', userId)
          .order('source_id')
          .range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) return rows;
      offset += pageSize;
    }
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<CalendarSource> sources,
  }) async {
    for (var offset = 0; offset < sources.length; offset += 200) {
      final page = sources.skip(offset).take(200);
      await client.from('calendar_sources').upsert([
        for (final source in page)
          {
            'user_id': userId,
            'source_id': source.id,
            'display_name': source.displayName,
            'time_zone_id': source.timeZoneId,
          },
      ], onConflict: 'user_id,source_id');
    }
  }

  @override
  Future<void> upsertEvents({
    required String userId,
    required List<CalendarEventOccurrence> events,
  }) async {
    for (var offset = 0; offset < events.length; offset += 200) {
      final page = events.skip(offset).take(200);
      await client.from('calendar_blocks').upsert([
        for (final event in page)
          {
            'user_id': userId,
            'source_id': event.sourceId,
            'source_event_id': event.sourceEventId,
            'occurrence_id': event.occurrenceId,
            'event_identity': event.eventIdentity,
            'title': event.title,
            'starts_at': event.startsAt.toUtc().toIso8601String(),
            'ends_at': event.endsAt.toUtc().toIso8601String(),
            'is_all_day': event.allDay,
            'all_day_start_date': event.allDayStartDate,
            'all_day_end_date_exclusive': event.allDayEndDateExclusive,
            'availability': event.availability.name,
            'time_zone_id': event.timeZoneId,
          },
      ], onConflict: 'user_id,source_id,occurrence_id');
    }
  }

  CalendarEventOccurrence _eventFromJson(Map<String, dynamic> row) =>
      CalendarEventOccurrence(
        sourceId: row['source_id'] as String,
        sourceEventId: row['source_event_id'] as String,
        occurrenceId: row['occurrence_id'] as String,
        eventIdentity: row['event_identity'] as String,
        title: row['title'] as String,
        startsAt: DateTime.parse(row['starts_at'] as String).toUtc(),
        endsAt: DateTime.parse(row['ends_at'] as String).toUtc(),
        allDay: row['is_all_day'] as bool,
        allDayStartDate: row['all_day_start_date'] as String?,
        allDayEndDateExclusive: row['all_day_end_date_exclusive'] as String?,
        availability: CalendarAvailability.fromName(row['availability']),
        timeZoneId: row['time_zone_id'] as String,
      );
}

class InMemoryCalendarRemote implements CalendarRemoteDataSource {
  final _sources = <String, Map<String, CalendarSource>>{};
  final _events = <String, Map<String, CalendarEventOccurrence>>{};

  @override
  Future<CalendarRemoteSnapshot> pull({required String userId}) async =>
      CalendarRemoteSnapshot(
        sources: (_sources[userId] ?? {}).values.toList(),
        events: (_events[userId] ?? {}).values.toList(),
      );

  @override
  Future<void> upsertSources({
    required String userId,
    required List<CalendarSource> sources,
  }) async {
    final target = _sources.putIfAbsent(userId, () => {});
    for (final source in sources) {
      target[source.id] = CalendarSource(
        id: source.id,
        displayName: source.displayName,
        timeZoneId: source.timeZoneId,
      );
    }
  }

  @override
  Future<void> upsertEvents({
    required String userId,
    required List<CalendarEventOccurrence> events,
  }) async {
    final target = _events.putIfAbsent(userId, () => {});
    for (final event in events) {
      target['${event.sourceId}:${event.occurrenceId}'] = event;
    }
  }
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
