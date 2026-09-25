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
  Future<void> deleteSources({
    required String userId,
    required Set<String> sourceIds,
  });
  Future<void> deleteEvents({
    required String userId,
    required String sourceId,
    required Set<String> occurrenceIds,
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

  @override
  Future<void> deleteSources({
    required String userId,
    required Set<String> sourceIds,
  }) async => throw _notConfigured();

  @override
  Future<void> deleteEvents({
    required String userId,
    required String sourceId,
    required Set<String> occurrenceIds,
  }) async => throw _notConfigured();
}

abstract interface class CalendarRepository {
  Future<CalendarImportState> loadImportState();
  Future<CalendarImportState> requestAccess();
  Future<CalendarImportResult> importCalendars(Set<String> sourceIds);
  Future<void> removeSources(Set<String> sourceIds);
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
  Future<void> removeSources(Set<String> sourceIds) async =>
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
  Future<CalendarImportState> loadImportState() =>
      _loadImportState(requestPermission: false);

  @override
  Future<CalendarImportState> requestAccess() =>
      _loadImportState(requestPermission: true);

  Future<CalendarImportState> _loadImportState({
    required bool requestPermission,
  }) async {
    var permission = CalendarPermissionState.unsupported;
    var availableSources = const <CalendarSource>[];
    if (provider.isSupported) {
      try {
        permission = requestPermission
            ? await provider.requestPermission()
            : await provider.permissionStatus();
        if (permission == CalendarPermissionState.granted) {
          try {
            availableSources = await provider.listCalendars();
          } catch (_) {
            permission = CalendarPermissionState.unknown;
            await _setSelectedSourcesStale();
          }
        } else {
          await _setSelectedSourcesStale();
        }
      } catch (_) {
        permission = CalendarPermissionState.unknown;
        await _setSelectedSourcesStale();
      }
    }
    final importedSources = provider.isSupported
        ? await _selectedSources()
        : await _allSources();
    return CalendarImportState(
      permission: permission,
      availableSources: availableSources,
      importedSources: importedSources,
      hasPendingUpdates: await _hasPendingUpdates(),
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
    CalendarPermissionState permission;
    try {
      permission = await provider.permissionStatus();
    } catch (_) {
      await _setSelectedSourcesStale();
      throw StateError('日历权限状态暂不可用。');
    }
    if (permission != CalendarPermissionState.granted) {
      await _setSelectedSourcesStale();
      throw StateError('尚未获得读取日历权限。');
    }

    List<CalendarSource> available;
    try {
      available = await provider.listCalendars();
    } catch (_) {
      await _setSelectedSourcesStale();
      throw StateError('系统日历暂时无法读取。');
    }
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
        await _saveSource(
          source,
          isSelected: true,
          isDeleted: false,
          isStale: true,
          updatedAt: importAt,
        );
      }
    });
    await _publish();

    var synced = true;
    try {
      await sync();
    } catch (_) {
      synced = false;
    }
    final range = _readRange();
    final eventRows = await (database.select(
      database.localCalendarBlocks,
    )..where((event) => event.userId.equals(userId))).get();
    final importedCount = eventRows
        .map(_occurrenceFromRow)
        .where(
          (event) =>
              sourceIds.contains(event.sourceId) &&
              _overlaps(event, range.from, range.to),
        )
        .length;
    final currentSources = await _selectedSources();
    return CalendarImportResult(
      importedOccurrences: importedCount,
      synced: synced,
      isStale:
          !synced ||
          currentSources.any(
            (source) => sourceIds.contains(source.id) && source.isStale,
          ),
    );
  }

  @override
  Future<void> removeSources(Set<String> sourceIds) async {
    if (sourceIds.isEmpty) return;
    if (!provider.isSupported) {
      throw UnsupportedError('请在 Android 设备上管理系统日历来源。');
    }
    final selected = await _selectedSourceRows();
    final selectedIds = {
      for (final source in selected)
        if (sourceIds.contains(source.sourceId)) source.sourceId,
    };
    if (selectedIds.isEmpty) return;

    await database.transaction(() async {
      for (final sourceId in selectedIds) {
        await _markSourceDeleted(sourceId);
      }
    });
    await _publish();
    try {
      await remote.deleteSources(userId: userId, sourceIds: selectedIds);
      await _deleteLocalSourceRows(selectedIds);
      await _publish();
    } catch (_) {
      await _setSourcesStale(selectedIds);
      await _publish();
      rethrow;
    }
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
    final isStale = sourceRows.any(
      (source) => source.isStale || source.isDeleted,
    );
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
    return CalendarAgenda(blocks: blocks, from: from, to: to, isStale: isStale);
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
    final refreshedEvents = provider.isSupported
        ? await _refreshSelectedSources()
        : <String, List<CalendarEventOccurrence>>{};
    final failedSourceIds = provider.isSupported
        ? (await _selectedSources())
              .where((source) => source.isStale)
              .map((source) => source.id)
              .toSet()
        : <String>{};

    try {
      final before = await remote.pull(userId: userId);
      final localRows = await _localSourceRows();
      final removedSourceIds = {
        for (final row in localRows)
          if (row.isDeleted) row.sourceId,
      };
      if (removedSourceIds.isNotEmpty) {
        await remote.deleteSources(userId: userId, sourceIds: removedSourceIds);
      }

      if (provider.isSupported) {
        final activeSources = await _selectedSources();
        if (activeSources.isNotEmpty) {
          await remote.upsertSources(userId: userId, sources: activeSources);
        }
        final range = _readRange();
        for (final entry in refreshedEvents.entries) {
          final sourceId = entry.key;
          final current = entry.value;
          final currentIds = {
            for (final event in current)
              if (_overlaps(event, range.from, range.to)) event.occurrenceId,
          };
          final obsoleteIds = {
            for (final event in before.events)
              if (event.sourceId == sourceId &&
                  _overlaps(event, range.from, range.to) &&
                  !currentIds.contains(event.occurrenceId))
                event.occurrenceId,
          };
          if (obsoleteIds.isNotEmpty) {
            await remote.deleteEvents(
              userId: userId,
              sourceId: sourceId,
              occurrenceIds: obsoleteIds,
            );
          }
          final eventsToUpload = current
              .where((event) => _overlaps(event, range.from, range.to))
              .toList();
          if (eventsToUpload.isNotEmpty) {
            await remote.upsertEvents(userId: userId, events: eventsToUpload);
          }
        }
      }

      final snapshot = await remote.pull(userId: userId);
      await _applyRemoteSnapshot(
        snapshot,
        failedSourceIds: failedSourceIds,
        removedSourceIds: removedSourceIds,
      );
      if (removedSourceIds.isNotEmpty) {
        await _deleteLocalSourceRows(removedSourceIds);
      }
      await _publish();
    } catch (_) {
      await _setVisibleSourcesStale();
      await _publish();
      rethrow;
    }
  }

  Future<Map<String, List<CalendarEventOccurrence>>>
  _refreshSelectedSources() async {
    final selected = await _selectedSourceRows();
    if (selected.isEmpty) return {};

    CalendarPermissionState permission;
    try {
      permission = await provider.permissionStatus();
    } catch (_) {
      await _setSelectedSourcesStale();
      return {};
    }
    if (permission != CalendarPermissionState.granted) {
      await _setSelectedSourcesStale();
      return {};
    }

    List<CalendarSource> available;
    try {
      available = await provider.listCalendars();
    } catch (_) {
      await _setSelectedSourcesStale();
      return {};
    }
    final availableById = {for (final source in available) source.id: source};
    final range = _readRange();
    final refreshed = <String, List<CalendarEventOccurrence>>{};

    for (final localSource in selected) {
      final source = availableById[localSource.sourceId];
      if (source == null) {
        await database.transaction(
          () => _markSourceDeleted(localSource.sourceId),
        );
        continue;
      }
      try {
        final events = await provider.readEvents(
          sourceIds: {source.id},
          from: range.from,
          to: range.to,
        );
        for (final event in events) {
          if (event.sourceId != source.id) {
            throw StateError('系统日历返回了其他来源的活动。');
          }
          _validateOccurrence(event);
        }
        final inRange = events
            .where((event) => _overlaps(event, range.from, range.to))
            .toList();
        await database.transaction(() async {
          await _saveSource(
            source,
            isSelected: true,
            isStale: false,
            isDeleted: false,
            updatedAt: _now().toUtc(),
          );
          await _replaceLocalEventsInRange(
            source.id,
            inRange,
            from: range.from,
            to: range.to,
          );
        });
        refreshed[source.id] = inRange;
      } catch (_) {
        await _setSourcesStale({source.id});
      }
    }
    await _publish();
    return refreshed;
  }

  Future<void> _replaceLocalEventsInRange(
    String sourceId,
    List<CalendarEventOccurrence> events, {
    required DateTime from,
    required DateTime to,
  }) async {
    final existingRows =
        await (database.select(database.localCalendarBlocks)..where(
              (event) =>
                  event.userId.equals(userId) & event.sourceId.equals(sourceId),
            ))
            .get();
    final currentIds = {for (final event in events) event.occurrenceId};
    for (final row in existingRows) {
      final event = _occurrenceFromRow(row);
      if (_overlaps(event, from, to) &&
          !currentIds.contains(event.occurrenceId)) {
        await (database.delete(database.localCalendarBlocks)..where(
              (candidate) =>
                  candidate.userId.equals(userId) &
                  candidate.sourceId.equals(sourceId) &
                  candidate.occurrenceId.equals(event.occurrenceId),
            ))
            .go();
      }
    }
    for (final event in events) {
      await _saveEvent(event, updatedAt: _now().toUtc());
    }
  }

  Future<void> _applyRemoteSnapshot(
    CalendarRemoteSnapshot snapshot, {
    required Set<String> failedSourceIds,
    required Set<String> removedSourceIds,
  }) async {
    final remoteSources = [
      for (final source in snapshot.sources)
        if (!removedSourceIds.contains(source.id)) source,
    ];
    final remoteSourceIds = {for (final source in remoteSources) source.id};
    final existingRows = await _localSourceRows();
    final existingById = {
      for (final source in existingRows) source.sourceId: source,
    };

    await database.transaction(() async {
      for (final source in remoteSources) {
        final existing = existingById[source.id];
        await _saveSource(
          source,
          isSelected: existing?.isSelected ?? false,
          isStale: failedSourceIds.contains(source.id) || source.isStale,
          isDeleted: false,
          updatedAt: _now().toUtc(),
        );
      }

      for (final existing in existingRows) {
        if (existing.isDeleted ||
            removedSourceIds.contains(existing.sourceId)) {
          continue;
        }
        if (!remoteSourceIds.contains(existing.sourceId) &&
            !(existing.isSelected &&
                failedSourceIds.contains(existing.sourceId))) {
          await _deleteLocalSourceRows({existing.sourceId});
        }
      }

      for (final sourceId in remoteSourceIds) {
        if (failedSourceIds.contains(sourceId)) continue;
        final remoteEvents = snapshot.events
            .where((event) => event.sourceId == sourceId)
            .toList();
        final remoteOccurrenceIds = {
          for (final event in remoteEvents) event.occurrenceId,
        };
        final localEvents =
            await (database.select(database.localCalendarBlocks)..where(
                  (event) =>
                      event.userId.equals(userId) &
                      event.sourceId.equals(sourceId),
                ))
                .get();
        for (final localEvent in localEvents) {
          if (!remoteOccurrenceIds.contains(localEvent.occurrenceId)) {
            await (database.delete(database.localCalendarBlocks)..where(
                  (event) =>
                      event.userId.equals(userId) &
                      event.sourceId.equals(sourceId) &
                      event.occurrenceId.equals(localEvent.occurrenceId),
                ))
                .go();
          }
        }
        for (final event in remoteEvents) {
          _validateOccurrence(event);
          await _saveEvent(event, updatedAt: _now().toUtc());
        }
      }
    });
  }

  ({DateTime from, DateTime to}) _readRange() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    return (
      from: today.subtract(const Duration(days: 30)),
      to: today.add(const Duration(days: 91)),
    );
  }

  Future<List<CalendarSource>> _selectedSources() async {
    final rows = await _selectedSourceRows();
    return [for (final row in rows) _sourceFromRow(row)];
  }

  Future<List<CalendarSource>> _allSources() async {
    final rows =
        await (database.select(database.localCalendarSources)
              ..where((source) => source.userId.equals(userId))
              ..where((source) => source.isDeleted.equals(false))
              ..orderBy([
                (source) => OrderingTerm(expression: source.displayName),
              ]))
            .get();
    return [for (final row in rows) _sourceFromRow(row)];
  }

  Future<List<LocalCalendarSource>> _localSourceRows() => (database.select(
    database.localCalendarSources,
  )..where((source) => source.userId.equals(userId))).get();

  Future<List<LocalCalendarSource>> _selectedSourceRows() =>
      (database.select(database.localCalendarSources)
            ..where((source) => source.userId.equals(userId))
            ..where((source) => source.isSelected.equals(true))
            ..where((source) => source.isDeleted.equals(false))
            ..orderBy([
              (source) => OrderingTerm(expression: source.displayName),
            ]))
          .get();

  Future<bool> _hasPendingUpdates() async => (await _localSourceRows()).any(
    (source) => source.isStale || source.isDeleted,
  );

  Future<void> _setSelectedSourcesStale() async {
    final sources = await _selectedSourceRows();
    await _setSourcesStale({for (final source in sources) source.sourceId});
  }

  Future<void> _setVisibleSourcesStale() async {
    final sources = provider.isSupported
        ? await _selectedSourceRows()
        : (await _localSourceRows())
              .where((source) => !source.isDeleted)
              .toList();
    await _setSourcesStale({for (final source in sources) source.sourceId});
  }

  Future<void> _setSourcesStale(Set<String> sourceIds) async {
    if (sourceIds.isEmpty) return;
    await (database.update(database.localCalendarSources)..where(
          (source) =>
              source.userId.equals(userId) & source.sourceId.isIn(sourceIds),
        ))
        .write(
          LocalCalendarSourcesCompanion(
            isStale: const Value(true),
            updatedAt: Value(_now().toUtc()),
          ),
        );
  }

  Future<void> _markSourceDeleted(String sourceId) async {
    await (database.delete(database.localCalendarBlocks)..where(
          (event) =>
              event.userId.equals(userId) & event.sourceId.equals(sourceId),
        ))
        .go();
    await (database.update(database.localCalendarSources)..where(
          (source) =>
              source.userId.equals(userId) & source.sourceId.equals(sourceId),
        ))
        .write(
          LocalCalendarSourcesCompanion(
            isSelected: const Value(false),
            isStale: const Value(false),
            isDeleted: const Value(true),
            updatedAt: Value(_now().toUtc()),
          ),
        );
  }

  Future<void> _deleteLocalSourceRows(Set<String> sourceIds) async {
    if (sourceIds.isEmpty) return;
    await (database.delete(database.localCalendarBlocks)..where(
          (event) =>
              event.userId.equals(userId) & event.sourceId.isIn(sourceIds),
        ))
        .go();
    await (database.delete(database.localCalendarSources)..where(
          (source) =>
              source.userId.equals(userId) & source.sourceId.isIn(sourceIds),
        ))
        .go();
  }

  Future<void> _saveSource(
    CalendarSource source, {
    bool? isSelected,
    bool? isStale,
    bool? isDeleted,
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
            isStale: Value(isStale ?? source.isStale),
            isDeleted: Value(isDeleted ?? existing?.isDeleted ?? false),
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
    isStale: row.isStale,
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
            isStale: row['is_stale'] as bool? ?? false,
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
            'is_stale': source.isStale,
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

  @override
  Future<void> deleteSources({
    required String userId,
    required Set<String> sourceIds,
  }) async {
    if (sourceIds.isEmpty) return;
    await client
        .from('calendar_sources')
        .delete()
        .eq('user_id', userId)
        .inFilter('source_id', sourceIds.toList());
  }

  @override
  Future<void> deleteEvents({
    required String userId,
    required String sourceId,
    required Set<String> occurrenceIds,
  }) async {
    if (occurrenceIds.isEmpty) return;
    await client
        .from('calendar_blocks')
        .delete()
        .eq('user_id', userId)
        .eq('source_id', sourceId)
        .inFilter('occurrence_id', occurrenceIds.toList());
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
  bool available = true;

  void _ensureAvailable() {
    if (!available) throw StateError('Cloud calendar sync is offline.');
  }

  @override
  Future<CalendarRemoteSnapshot> pull({required String userId}) async {
    _ensureAvailable();
    return CalendarRemoteSnapshot(
      sources: (_sources[userId] ?? {}).values.toList(),
      events: (_events[userId] ?? {}).values.toList(),
    );
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<CalendarSource> sources,
  }) async {
    _ensureAvailable();
    final target = _sources.putIfAbsent(userId, () => {});
    for (final source in sources) {
      target[source.id] = CalendarSource(
        id: source.id,
        displayName: source.displayName,
        timeZoneId: source.timeZoneId,
        isStale: source.isStale,
      );
    }
  }

  @override
  Future<void> upsertEvents({
    required String userId,
    required List<CalendarEventOccurrence> events,
  }) async {
    _ensureAvailable();
    final target = _events.putIfAbsent(userId, () => {});
    for (final event in events) {
      target['${event.sourceId}:${event.occurrenceId}'] = event;
    }
  }

  @override
  Future<void> deleteSources({
    required String userId,
    required Set<String> sourceIds,
  }) async {
    _ensureAvailable();
    if (sourceIds.isEmpty) return;
    final sources = _sources[userId];
    final events = _events[userId];
    for (final sourceId in sourceIds) {
      sources?.remove(sourceId);
      events?.removeWhere((_, event) => event.sourceId == sourceId);
    }
  }

  @override
  Future<void> deleteEvents({
    required String userId,
    required String sourceId,
    required Set<String> occurrenceIds,
  }) async {
    _ensureAvailable();
    final events = _events[userId];
    events?.removeWhere(
      (_, event) =>
          event.sourceId == sourceId &&
          occurrenceIds.contains(event.occurrenceId),
    );
  }
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
