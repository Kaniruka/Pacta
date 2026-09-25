import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:uuid/uuid.dart';

import '../tasks/task_database.dart' as db;
import 'focus_models.dart';
import 'focus_time_zones.dart';

class FocusRemoteSnapshot {
  const FocusRemoteSnapshot({
    this.sessions = const [],
    this.appointments = const [],
    this.nodes = const [],
    this.records = const [],
    this.appointmentRecords = const [],
    this.precedentRules = const [],
    this.sources = const [],
  });

  final List<FocusSession> sessions;
  final List<AppointmentPreparation> appointments;
  final List<FocusNode> nodes;
  final List<FocusChainRecord> records;
  final List<AppointmentChainRecord> appointmentRecords;
  final List<PrecedentRule> precedentRules;
  final List<FocusSyncSource> sources;
}

abstract interface class FocusRemoteDataSource {
  Future<FocusRemoteSnapshot> pull({required String userId});

  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  });

  Future<void> upsertAppointments({
    required String userId,
    required List<AppointmentPreparation> appointments,
  });

  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  });

  Future<void> deleteNodes({
    required String userId,
    required List<String> sessionIds,
  });

  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  });

  Future<void> upsertAppointmentRecords({
    required String userId,
    required List<AppointmentChainRecord> records,
  });

  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  });

  Future<void> upsertSources({
    required String userId,
    required List<FocusSyncSource> sources,
  });
}

class UnavailableFocusRemoteDataSource implements FocusRemoteDataSource {
  const UnavailableFocusRemoteDataSource();

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertAppointments({
    required String userId,
    required List<AppointmentPreparation> appointments,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> deleteNodes({
    required String userId,
    required List<String> sessionIds,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertAppointmentRecords({
    required String userId,
    required List<AppointmentChainRecord> records,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<FocusSyncSource> sources,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }
}

abstract interface class FocusRepository {
  Stream<List<FocusSession>> watchSessions();
  Stream<List<FocusReconciliationCase>> watchFocusReconciliations();
  Future<List<FocusReconciliationCase>> getFocusReconciliations();
  Future<void> resolveFocusReconciliation({
    required String caseId,
    required Map<String, FocusSessionReconciliationSelection> sessionSelections,
    String? adoptedSessionId,
  });
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String deviceTimeZoneId,
  });
  Future<FocusDashboardMetrics> getDashboardMetrics({
    required String deviceTimeZoneId,
  });
  Future<void> setDisplayTimeZonePreference(String? timeZoneId);
  Future<List<FocusSession>> getSessions();
  Future<FocusSession?> getSession(String sessionId);
  Future<FocusSession?> getActiveSession();
  Future<List<AppointmentPreparation>> getAppointments();
  Future<AppointmentPreparation?> getAppointment(String appointmentId);
  Future<List<FocusAppointmentSourceOption>> getAppointmentConfigurationSources(
    String appointmentId,
  );
  Future<AppointmentPreparation> selectAppointmentConfigurationSource({
    required String appointmentId,
    required String sourceId,
  });
  Future<AppointmentPreparation?> getActiveAppointment();
  Future<AppointmentChainRecord> getAppointmentChainRecord();
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  });
  Future<AppointmentPreparation> startAppointment({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  });
  Future<AppointmentPreparation> updateAppointment({
    required String appointmentId,
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  });
  Future<FocusSession> enterAppointmentEarly(String appointmentId);
  Future<AppointmentPreparation> cancelAppointment({
    required String appointmentId,
    required String failureReason,
  });
  Future<void> settleDueAppointments();
  Future<void> settleDueSessions();
  Future<FocusSession> pauseSession(
    String sessionId, {
    required String ruleText,
  });
  Future<FocusSession> resumeSession(String sessionId);
  Future<FocusSession> completeEarlySession({
    required String sessionId,
    required String ruleText,
  });
  Future<FocusSession> abandonSession({
    required String sessionId,
    required String failureReason,
  });
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  });
  Future<void> updateNodeNote({required String nodeId, required String note});
  Future<List<FocusNode>> getNodes();
  Future<List<FocusChainRecord>> getChainRecords();
  Future<List<PrecedentRule>> getPrecedentRules();
  Future<PrecedentRule> createPrecedentRule({required String text});
  Future<PrecedentRule> updatePrecedentRule({
    required String ruleId,
    required String text,
  });
  Future<void> deletePrecedentRule(String ruleId);
  Future<FocusChainMode> getLastMode();
  Future<void> sync();
  Future<void> dispose();
}

class _PendingFocusConfigurationKeys {
  const _PendingFocusConfigurationKeys({
    required this.taskIds,
    required this.modes,
  });

  final Set<String> taskIds;
  final Set<String> modes;
}

class LocalFocusRepository implements FocusRepository {
  LocalFocusRepository({
    required this.database,
    required this.userId,
    required this.remote,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final db.PactaDatabase database;
  final String userId;
  final FocusRemoteDataSource remote;
  final DateTime Function() _now;
  final _changes = StreamController<List<FocusSession>>.broadcast();
  final _uuid = const Uuid();
  Future<void>? _appointmentSettlement;
  Future<void> _syncQueue = Future<void>.value();

  static const appointmentPreparationDuration = Duration(minutes: 15);

  @override
  Stream<List<FocusSession>> watchSessions() async* {
    yield await getSessions();
    yield* _changes.stream;
  }

  @override
  Stream<List<FocusReconciliationCase>> watchFocusReconciliations() async* {
    yield await getFocusReconciliations();
    yield* _changes.stream.asyncMap((_) => getFocusReconciliations());
  }

  @override
  Future<List<FocusSession>> getSessions() async {
    await _settleDueAppointments();
    await _settleDueSessions();
    final rows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)]))
            .get();
    return [for (final row in rows) _sessionFromRow(row)];
  }

  @override
  Future<List<FocusReconciliationCase>> getFocusReconciliations() async {
    final sessions = await _getSessionsWithoutSettling();
    if (sessions.isEmpty) return const [];
    final sources = await _getSyncSources();
    final sourceById = {for (final source in sources) source.sourceId: source};
    final headsBySession = _focusSourceHeadGroups(
      sources,
      entityType: 'focus_session',
    );
    final conflictingIds = _conflictingFocusEntityIds(
      sources,
      entityType: 'focus_session',
    );
    final comparisonSessions = <FocusSession>[];
    for (final session in sessions) {
      final variants = [
        for (final source in headsBySession[session.id] ?? const [])
          _focusSessionFromJson(
            jsonDecode(source.payload) as Map<String, dynamic>,
          ),
      ];
      comparisonSessions.add(
        variants.isEmpty
            ? session
            : _sessionWithUnionedIntervals(session, variants),
      );
    }

    final includedIds = <String>{};
    final cases = <FocusReconciliationCase>[];
    for (final overlapping in _overlappingFocusSessionGroups(
      comparisonSessions,
    )) {
      final groupIds = overlapping.map((session) => session.id).toSet();
      final needsReview = overlapping.any(
        (session) =>
            session.isPendingReview ||
            conflictingIds.contains(session.id) ||
            session.reviewDispositionUpdatedAt != null ||
            session.reviewDisposition == FocusRecordDisposition.duplicate,
      );
      if (!needsReview) continue;
      includedIds.addAll(groupIds);
      cases.add(
        _reconciliationCase(
          id: _reconciliationCaseId(groupIds),
          sessions: [
            for (final id in groupIds)
              comparisonSessions.singleWhere((session) => session.id == id),
          ],
          headsBySession: headsBySession,
          conflictingIds: conflictingIds,
          sourceById: sourceById,
        ),
      );
    }

    for (final session in sessions) {
      if (includedIds.contains(session.id)) continue;
      if (!session.isPendingReview &&
          !conflictingIds.contains(session.id) &&
          session.reviewDispositionUpdatedAt == null &&
          session.reviewDisposition != FocusRecordDisposition.duplicate) {
        continue;
      }
      cases.add(
        _reconciliationCase(
          id: _reconciliationCaseId({session.id}),
          sessions: [
            comparisonSessions.singleWhere(
              (candidate) => candidate.id == session.id,
            ),
          ],
          headsBySession: headsBySession,
          conflictingIds: conflictingIds,
          sourceById: sourceById,
        ),
      );
    }
    cases.sort((left, right) {
      if (left.isPendingReview != right.isPendingReview) {
        return left.isPendingReview ? -1 : 1;
      }
      final leftAt = left.sessions
          .map((entry) => entry.session.startedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final rightAt = right.sessions
          .map((entry) => entry.session.startedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      return rightAt.compareTo(leftAt);
    });
    return List.unmodifiable(cases);
  }

  FocusReconciliationCase _reconciliationCase({
    required String id,
    required List<FocusSession> sessions,
    required Map<String, List<FocusSyncSource>> headsBySession,
    required Set<String> conflictingIds,
    required Map<String, FocusSyncSource> sourceById,
  }) {
    final sessionEntries = <FocusReconciliationSession>[];
    for (final session in sessions) {
      final heads = headsBySession[session.id] ?? const <FocusSyncSource>[];
      final options = [
        for (final source in heads)
          FocusSessionSourceOption(
            sourceId: source.sourceId,
            deviceId: source.deviceId,
            occurredAt: source.occurredAt,
            session: _focusSessionFromJson(
              jsonDecode(source.payload) as Map<String, dynamic>,
            ),
          ),
      ]..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
      final variants = options.map((option) => option.session).toList();
      final displaySession = variants.isEmpty
          ? session
          : _sessionWithUnionedIntervals(session, variants);
      final configSignatures = variants
          .map(_focusConfigurationSignature)
          .toSet();
      final outcomeSignatures = variants.map(_focusOutcomeSignature).toSet();
      sessionEntries.add(
        FocusReconciliationSession(
          session: displaySession,
          availableSources: List.unmodifiable(options),
          selectedConfigurationSource:
              sourceById[session.configurationBasisSourceId ??
                      (options.length == 1 ? options.single.sourceId : '')] ==
                  null
              ? null
              : _sourceOption(
                  sourceById[session.configurationBasisSourceId ??
                      options.single.sourceId]!,
                ),
          selectedOutcomeSource:
              sourceById[session.outcomeBasisSourceId ??
                      (options.length == 1 ? options.single.sourceId : '')] ==
                  null
              ? null
              : _sourceOption(
                  sourceById[session.outcomeBasisSourceId ??
                      options.single.sourceId]!,
                ),
          requiresConfigurationChoice:
              conflictingIds.contains(session.id) &&
              configSignatures.length > 1,
          requiresOutcomeChoice:
              conflictingIds.contains(session.id) &&
              outcomeSignatures.length > 1,
        ),
      );
    }
    sessionEntries.sort((left, right) {
      final byStart = left.session.startedAt.compareTo(right.session.startedAt);
      return byStart == 0
          ? left.session.id.compareTo(right.session.id)
          : byStart;
    });
    return FocusReconciliationCase(id: id, sessions: sessionEntries);
  }

  FocusSessionSourceOption _sourceOption(FocusSyncSource source) =>
      FocusSessionSourceOption(
        sourceId: source.sourceId,
        deviceId: source.deviceId,
        occurredAt: source.occurredAt,
        session: _focusSessionFromJson(
          jsonDecode(source.payload) as Map<String, dynamic>,
        ),
      );

  @override
  Future<void> resolveFocusReconciliation({
    required String caseId,
    required Map<String, FocusSessionReconciliationSelection> sessionSelections,
    String? adoptedSessionId,
  }) async {
    final cases = await getFocusReconciliations();
    FocusReconciliationCase? reconciliation;
    for (final candidate in cases) {
      if (candidate.id == caseId) {
        reconciliation = candidate;
        break;
      }
    }
    if (reconciliation == null) throw StateError('这组专注记录已不存在。');
    if (!reconciliation.isPendingReview) return;

    final sessionIds = reconciliation.sessions
        .map((entry) => entry.session.id)
        .toSet();
    if (!sessionSelections.keys.toSet().containsAll(sessionIds)) {
      throw StateError('请为这组中的每条专注记录选择核对结果。');
    }
    if (reconciliation.hasOverlappingSessions &&
        (adoptedSessionId == null || !sessionIds.contains(adoptedSessionId))) {
      throw StateError('请先选择实际采用的专注记录。');
    }
    if (!reconciliation.hasOverlappingSessions && adoptedSessionId != null) {
      throw StateError('这组记录不需要选择重复记录。');
    }

    final sources = await _getSyncSources();
    final headsBySession = _focusSourceHeadGroups(
      sources,
      entityType: 'focus_session',
    );
    final now = _now().toUtc();
    final updates = <String, FocusSession>{};
    final sourceUpdates = <({FocusSession session, List<String> parents})>[];

    for (final entry in reconciliation.sessions) {
      final currentRow = await _sessionRow(entry.session.id);
      if (currentRow == null) throw StateError('专注记录已不存在。');
      final current = _sessionFromRow(currentRow);
      final options = entry.availableSources;
      if (options.isEmpty) {
        throw StateError('专注记录缺少可核对的原始来源。');
      }
      final selection = sessionSelections[entry.session.id]!;
      final optionIds = options.map((option) => option.sourceId).toSet();
      if (entry.requiresConfigurationChoice &&
          (selection.configurationSourceId == null ||
              !optionIds.contains(selection.configurationSourceId))) {
        throw StateError('请从本组来源中选择配置依据。');
      }
      if (entry.requiresOutcomeChoice &&
          (selection.outcomeSourceId == null ||
              !optionIds.contains(selection.outcomeSourceId))) {
        throw StateError('请从本组来源中选择结果依据。');
      }

      final configurationOption = _selectedSourceOption(
        options,
        requestedSourceId: selection.configurationSourceId,
        rememberedSourceId: current.configurationBasisSourceId,
        configurationSignature: _focusConfigurationSignature,
      );
      final outcomeOption = _selectedSourceOption(
        options,
        requestedSourceId: selection.outcomeSourceId,
        rememberedSourceId: current.outcomeBasisSourceId,
        configurationSignature: _focusOutcomeSignature,
      );
      final outcome = outcomeOption.session;
      if (outcome.status != FocusSessionStatus.completed &&
          outcome.status != FocusSessionStatus.failed) {
        throw StateError('未结束的专注仍由原流程接续，不能在此核对结果。');
      }
      final intervals = _unionFocusIntervals([
        for (final option in options) option.session,
      ]);
      final effectiveSeconds = intervals.isEmpty
          ? outcome.effectiveSeconds
          : intervals.fold<int>(
              0,
              (seconds, interval) => seconds + interval.durationSeconds,
            );
      final isAdopted =
          !reconciliation.hasOverlappingSessions ||
          entry.session.id == adoptedSessionId;
      final updated = FocusSession(
        id: current.id,
        appointmentId: outcome.appointmentId,
        taskId: configurationOption.session.taskId,
        mode: configurationOption.session.mode,
        durationSeconds: configurationOption.session.durationSeconds,
        startedAt: outcome.startedAt,
        endsAt: outcome.endsAt,
        status: outcome.status,
        completedAt: outcome.completedAt,
        effectiveSeconds: effectiveSeconds,
        completionType: outcome.completionType,
        completionRuleText: outcome.completionRuleText,
        pausedAt: outcome.pausedAt,
        pausedSeconds: outcome.pausedSeconds,
        pauseRuleText: outcome.pauseRuleText,
        failureReason: outcome.failureReason,
        effectiveIntervals: intervals,
        reviewDisposition: isAdopted
            ? FocusRecordDisposition.accepted
            : FocusRecordDisposition.duplicate,
        reviewDispositionUpdatedAt: now,
        configurationBasisSourceId:
            configurationOption.session.configurationBasisSourceId ??
            configurationOption.sourceId,
        outcomeBasisSourceId:
            outcomeOption.session.outcomeBasisSourceId ??
            outcomeOption.sourceId,
      );
      updates[updated.id] = updated;
      sourceUpdates.add((
        session: updated,
        parents: headsBySession[updated.id]!
            .map((source) => source.sourceId)
            .toList(),
      ));
    }

    await database.transaction(() async {
      for (final session in updates.values) {
        await _saveSession(session, queue: false);
      }
      for (final update in sourceUpdates) {
        await _recordSyncSource(
          entityType: 'focus_session',
          entityId: update.session.id,
          occurredAt: now,
          parentSourceIds: update.parents,
          payload: jsonEncode(_focusSessionToJson(update.session)),
        );
      }
    });
    await _reconcileFocusEffectsAfterDispositionChanges(updates: updates);
    await _reconcileTaskFocusProgressFromSessions();
    await _removeNodesForNonAcceptedSessionsAndRemote();
    await _publish();
  }

  FocusSessionSourceOption _selectedSourceOption(
    List<FocusSessionSourceOption> options, {
    required String? requestedSourceId,
    required String? rememberedSourceId,
    required String Function(FocusSession) configurationSignature,
  }) {
    final selectedId = requestedSourceId ?? rememberedSourceId;
    if (selectedId != null) {
      for (final option in options) {
        if (option.sourceId == selectedId) return option;
      }
    }
    final signatures = options
        .map((option) => configurationSignature(option.session))
        .toSet();
    if (signatures.length == 1) return options.first;
    throw StateError('请明确选择专注记录的来源。');
  }

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String deviceTimeZoneId,
  }) => watchSessions().asyncMap(
    (_) => getDashboardMetrics(deviceTimeZoneId: deviceTimeZoneId),
  );

  @override
  Future<FocusDashboardMetrics> getDashboardMetrics({
    required String deviceTimeZoneId,
  }) async {
    await _settleDueSessions();
    final preference = await (database.select(
      database.focusPreferences,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    final preferredZone = preference?.displayTimeZoneId;
    final usesPreference =
        preferredZone != null && FocusTimeZones.contains(preferredZone);
    final zoneId = usesPreference
        ? preferredZone
        : FocusTimeZones.contains(deviceTimeZoneId)
        ? deviceTimeZoneId
        : 'Etc/UTC';
    final location = FocusTimeZones.location(zoneId);
    final sessions = await _getSessionsWithoutSettling();
    final pendingReviewSessions = sessions
        .where(
          (session) =>
              session.reviewDisposition == FocusRecordDisposition.pendingReview,
        )
        .toList();
    final pendingReviewConfigurations =
        await _getPendingFocusConfigurationKeys();
    final focusProgressByTask = <String, int>{};
    final secondsByDay = <String, int>{};
    var totalSeconds = 0;

    for (final session in sessions) {
      if ((session.status != FocusSessionStatus.completed &&
              session.status != FocusSessionStatus.failed) ||
          !session.reviewDisposition.contributesToFocusProgress) {
        continue;
      }
      final intervals = _effectiveIntervalsForProjection(session);
      final sessionSeconds = intervals.fold<int>(
        0,
        (sum, interval) => sum + interval.durationSeconds,
      );
      if (sessionSeconds <= 0) continue;
      focusProgressByTask.update(
        session.taskId,
        (seconds) => seconds + sessionSeconds,
        ifAbsent: () => sessionSeconds,
      );
      totalSeconds += sessionSeconds;
      for (final interval in intervals) {
        _addIntervalByCalendarDay(interval, location, secondsByDay);
      }
    }

    final localNow = timezone.TZDateTime.from(_now().toUtc(), location);
    final today = timezone.TZDateTime(
      location,
      localNow.year,
      localNow.month,
      localNow.day,
    );
    const dayCount = 7;
    final recentActivity = [
      for (var daysAgo = dayCount - 1; daysAgo >= 0; daysAgo--)
        _activityDay(
          timezone.TZDateTime(
            location,
            today.year,
            today.month,
            today.day - daysAgo,
          ),
          secondsByDay,
        ),
    ];

    return FocusDashboardMetrics(
      focusProgressSecondsByTask: Map.unmodifiable(focusProgressByTask),
      recentActivity: List.unmodifiable(recentActivity),
      totalAcceptedFocusSeconds: totalSeconds,
      displayTimeZoneId: zoneId,
      followsDeviceTimeZone: !usesPreference,
      hasPendingReview: pendingReviewSessions.isNotEmpty,
      pendingReviewTaskIds: pendingReviewConfigurations.taskIds,
    );
  }

  @override
  Future<void> setDisplayTimeZonePreference(String? timeZoneId) async {
    if (timeZoneId != null && !FocusTimeZones.contains(timeZoneId)) {
      throw ArgumentError.value(timeZoneId, 'timeZoneId', '未知的时区标识。');
    }
    final row = await (database.select(
      database.focusPreferences,
    )..where((entry) => entry.userId.equals(userId))).getSingleOrNull();
    if (row == null) {
      await database
          .into(database.focusPreferences)
          .insert(
            db.FocusPreferencesCompanion.insert(
              userId: userId,
              lastMode: FocusChainMode.regular.storageValue,
              displayTimeZoneId: Value(timeZoneId),
            ),
          );
    } else {
      await (database.update(
        database.focusPreferences,
      )..where((entry) => entry.userId.equals(userId))).write(
        db.FocusPreferencesCompanion(displayTimeZoneId: Value(timeZoneId)),
      );
    }
    await _publish();
  }

  @override
  Future<FocusSession?> getActiveSession() async {
    await _settleDueAppointments();
    await _settleDueSessions();
    final row =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where((session) => session.status.isIn(['active', 'paused']))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  @override
  Future<FocusSession?> getSession(String sessionId) async {
    await _settleDueAppointments();
    await _settleDueSessions();
    final row =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where((session) => session.id.equals(sessionId)))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  @override
  Future<List<AppointmentPreparation>> getAppointments() async {
    await _settleDueAppointments();
    final rows =
        await (database.select(database.focusAppointments)
              ..where((appointment) => appointment.userId.equals(userId))
              ..orderBy([
                (appointment) => OrderingTerm.desc(appointment.startedAt),
              ]))
            .get();
    return [for (final row in rows) _appointmentFromRow(row)];
  }

  @override
  Future<AppointmentPreparation?> getAppointment(String appointmentId) async {
    await _settleDueAppointments();
    final row = await _appointmentRow(appointmentId);
    return row == null ? null : _appointmentFromRow(row);
  }

  @override
  Future<List<FocusAppointmentSourceOption>> getAppointmentConfigurationSources(
    String appointmentId,
  ) async {
    final sources = await _getSyncSources();
    final heads = _focusSourceHeadGroups(
      sources,
      entityType: 'focus_appointment',
    )[appointmentId];
    if (heads == null || heads.length < 2) return const [];
    final sourcesById = {for (final source in sources) source.sourceId: source};
    final optionsByConfiguration = <String, FocusAppointmentSourceOption>{};
    for (final head in heads) {
      final branch = _focusAppointmentFromJson(
        jsonDecode(head.payload) as Map<String, dynamic>,
      );
      final basisId = branch.configurationBasisSourceId;
      final basisSource = basisId == null ? null : sourcesById[basisId];
      final source = basisSource ?? head;
      final configuration = _focusAppointmentFromJson(
        jsonDecode(source.payload) as Map<String, dynamic>,
      );
      final signature = _appointmentConfigurationSignature(configuration);
      optionsByConfiguration.putIfAbsent(
        signature,
        () => FocusAppointmentSourceOption(
          sourceId: source.sourceId,
          deviceId: source.deviceId,
          occurredAt: source.occurredAt,
          taskId: configuration.taskId,
          mode: configuration.mode,
          durationSeconds: configuration.durationSeconds,
        ),
      );
    }
    final options = optionsByConfiguration.values.toList()
      ..sort((left, right) {
        final byTime = left.occurredAt.compareTo(right.occurredAt);
        return byTime == 0 ? left.sourceId.compareTo(right.sourceId) : byTime;
      });
    return options;
  }

  @override
  Future<AppointmentPreparation> selectAppointmentConfigurationSource({
    required String appointmentId,
    required String sourceId,
  }) async {
    final row = await _appointmentRow(appointmentId);
    if (row == null) throw StateError('预约准备不存在或已不属于当前用户。');
    final source =
        await (database.select(database.focusSyncSources)
              ..where((entry) => entry.userId.equals(userId))
              ..where((entry) => entry.entityType.equals('focus_appointment'))
              ..where((entry) => entry.entityId.equals(appointmentId))
              ..where((entry) => entry.sourceId.equals(sourceId)))
            .getSingleOrNull();
    if (source == null) throw StateError('所选预约来源不存在。');
    final configuration = _focusAppointmentFromJson(
      jsonDecode(source.payload) as Map<String, dynamic>,
    );
    final updatedAt = _now().toUtc();
    await (database.update(database.focusAppointments)
          ..where((entry) => entry.userId.equals(userId))
          ..where((entry) => entry.id.equals(appointmentId)))
        .write(
          db.FocusAppointmentsCompanion(
            taskId: Value(configuration.taskId),
            mode: Value(configuration.mode.storageValue),
            durationSeconds: Value(configuration.durationSeconds),
            configurationBasisSourceId: Value(sourceId),
            updatedAt: Value(updatedAt),
          ),
        );
    await _queue(
      'focus_appointment',
      appointmentId,
      updatedAt,
      parentSourceId: sourceId,
    );
    await _publish();
    return (await getAppointment(appointmentId))!;
  }

  @override
  Future<AppointmentPreparation?> getActiveAppointment() async {
    await _settleDueAppointments();
    final row = await _activeAppointmentRow();
    return row == null ? null : _appointmentFromRow(row);
  }

  @override
  Future<AppointmentChainRecord> getAppointmentChainRecord() async {
    final row = await (database.select(
      database.appointmentChainRecords,
    )..where((record) => record.userId.equals(userId))).getSingleOrNull();
    final hasPendingReview =
        (await (database.select(database.focusAppointments)
                  ..where((appointment) => appointment.userId.equals(userId))
                  ..where(
                    (appointment) => appointment.reviewDisposition.equals(
                      FocusRecordDisposition.pendingReview.storageValue,
                    ),
                  ))
                .get())
            .isNotEmpty;
    return row == null
        ? AppointmentChainRecord(
            currentConsecutive: 0,
            bestConsecutive: 0,
            updatedAt: _now().toUtc(),
            hasPendingReview: hasPendingReview,
          )
        : AppointmentChainRecord(
            currentConsecutive: row.currentConsecutive,
            bestConsecutive: row.bestConsecutive,
            updatedAt: row.updatedAt,
            hasPendingReview: hasPendingReview,
          );
  }

  @override
  Future<AppointmentPreparation> startAppointment({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) async {
    _validateDuration(duration);
    final task = await _taskForStart(taskId);
    if (task.isComplete) throw StateError('已完成任务不能开始新的预约。');

    await _settleDueAppointments();
    await _settleDueSessions();
    final existing = await _activeAppointmentRow();
    if (existing != null) return _appointmentFromRow(existing);
    final activeSession = await _activeSessionRow();
    if (activeSession != null) {
      throw StateError('已有进行中的专注，请先返回原流程或处理它的结束操作。');
    }

    final startedAt = _now().toUtc();
    final appointment = AppointmentPreparation(
      id: _uuid.v4(),
      taskId: taskId,
      mode: mode,
      durationSeconds: duration.inSeconds,
      startedAt: startedAt,
      endsAt: startedAt.add(appointmentPreparationDuration),
      status: AppointmentPreparationStatus.active,
      settledAt: null,
      updatedAt: startedAt,
    );
    await database.transaction(() async {
      await _saveAppointment(appointment, queue: false);
      await _queue('focus_appointment', appointment.id, startedAt);
    });
    await _publish();
    return appointment;
  }

  @override
  Future<AppointmentPreparation> updateAppointment({
    required String appointmentId,
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) async {
    _validateDuration(duration);
    await _settleDueAppointments();
    final row = await _appointmentRow(appointmentId);
    if (row == null) throw StateError('预约准备不存在或已不属于当前用户。');
    if (row.status != AppointmentPreparationStatus.active.storageValue) {
      throw StateError('预约准备已经结算，不能再修改配置。');
    }
    final task = await _taskForStart(
      taskId,
      allowDeleted: taskId == row.taskId,
    );
    if (task.isComplete) throw StateError('已完成任务不能用于预约。');
    final updatedAt = _now().toUtc();
    await database.transaction(() async {
      await (database.update(database.focusAppointments)
            ..where((appointment) => appointment.userId.equals(userId))
            ..where((appointment) => appointment.id.equals(appointmentId))
            ..where(
              (appointment) => appointment.reviewDisposition.equals(
                FocusRecordDisposition.accepted.storageValue,
              ),
            ))
          .write(
            db.FocusAppointmentsCompanion(
              taskId: Value(taskId),
              mode: Value(mode.storageValue),
              durationSeconds: Value(duration.inSeconds),
              configurationBasisSourceId: const Value(null),
              updatedAt: Value(updatedAt),
            ),
          );
      await _queue('focus_appointment', appointmentId, updatedAt);
    });
    await _publish();
    return (await getAppointment(appointmentId))!;
  }

  @override
  Future<FocusSession> enterAppointmentEarly(String appointmentId) async {
    await _settleDueAppointments();
    final row = await _appointmentRow(appointmentId);
    if (row == null) throw StateError('预约准备不存在或已不属于当前用户。');
    if (row.status == AppointmentPreparationStatus.failed.storageValue) {
      throw StateError('失败的预约不能进入专注。');
    }
    if (row.status == AppointmentPreparationStatus.succeeded.storageValue) {
      final existingSession = await _sessionRow(row.sessionId ?? appointmentId);
      if (existingSession == null) {
        throw StateError('预约已成功但对应的专注记录尚未恢复。');
      }
      return _sessionFromRow(existingSession);
    }

    final now = _now().toUtc();
    final session = FocusSession(
      id: row.sessionId ?? row.id,
      appointmentId: row.id,
      taskId: row.taskId,
      mode: FocusChainMode.fromStorage(row.mode),
      durationSeconds: row.durationSeconds,
      startedAt: now,
      endsAt: now.add(Duration(seconds: row.durationSeconds)),
      status: FocusSessionStatus.active,
      completedAt: null,
      effectiveSeconds: 0,
      effectiveIntervals: [FocusTimeInterval(startedAt: now, endedAt: null)],
      reviewDisposition: FocusRecordDisposition.fromStorage(
        row.reviewDisposition,
      ),
      reviewDispositionUpdatedAt: row.reviewDispositionUpdatedAt,
    );
    await database.transaction(() async {
      final current = await _appointmentRow(appointmentId);
      if (current == null ||
          current.status != AppointmentPreparationStatus.active.storageValue) {
        return;
      }
      await _saveSession(session);
      final succeeded = await _succeedAppointment(
        appointmentId,
        sessionId: session.id,
        settledAt: now,
        updatedAt: now,
        allowPendingReview: true,
      );
      if (succeeded &&
          current.reviewDisposition ==
              FocusRecordDisposition.accepted.storageValue) {
        await _incrementAppointmentRecord(now);
      }
    });
    await _publish();
    return (await getSession(session.id))!;
  }

  @override
  Future<AppointmentPreparation> cancelAppointment({
    required String appointmentId,
    required String failureReason,
  }) async {
    final reason = _requiredFailureReason(failureReason);
    await _settleDueAppointments();
    final row = await _appointmentRow(appointmentId);
    if (row == null) throw StateError('预约准备不存在或已不属于当前用户。');
    if (row.status == AppointmentPreparationStatus.succeeded.storageValue) {
      throw StateError('成功的预约不能取消。');
    }
    if (row.status == AppointmentPreparationStatus.failed.storageValue) {
      return _appointmentFromRow(row);
    }

    final now = _now().toUtc();
    await database.transaction(() async {
      final current = await _appointmentRow(appointmentId);
      if (current == null ||
          current.status != AppointmentPreparationStatus.active.storageValue) {
        return;
      }
      final changed =
          await (database.update(database.focusAppointments)
                ..where((appointment) => appointment.userId.equals(userId))
                ..where((appointment) => appointment.id.equals(appointmentId)))
              .write(
                db.FocusAppointmentsCompanion(
                  status: const Value('failed'),
                  settledAt: Value(now),
                  failureReason: Value(reason),
                  updatedAt: Value(now),
                ),
              );
      if (changed == 0) return;
      await _queue('focus_appointment', appointmentId, now);
      if (current.reviewDisposition ==
          FocusRecordDisposition.accepted.storageValue) {
        await _resetAppointmentRecord(now);
        await _queue('appointment_chain', userId, now);
      }
    });
    await _publish();
    return (await getAppointment(appointmentId))!;
  }

  @override
  Future<void> settleDueAppointments() => _settleDueAppointments();

  @override
  Future<List<PrecedentRule>> getPrecedentRules() async {
    final rows =
        await (database.select(database.focusPrecedentRules)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.deletedAt.isNull())
              ..orderBy([(rule) => OrderingTerm.desc(rule.updatedAt)]))
            .get();
    return [for (final row in rows) _precedentRuleFromRow(row)];
  }

  @override
  Future<PrecedentRule> createPrecedentRule({required String text}) async {
    final ruleText = _requiredRuleText(text);
    final now = _now().toUtc();
    final rule = PrecedentRule(
      id: _uuid.v4(),
      text: ruleText,
      createdAt: now,
      updatedAt: now,
    );
    await database
        .into(database.focusPrecedentRules)
        .insert(
          db.FocusPrecedentRulesCompanion.insert(
            userId: userId,
            id: rule.id,
            ruleText: rule.text,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt,
          ),
        );
    await _queue('focus_precedent_rule', rule.id, now);
    return rule;
  }

  @override
  Future<PrecedentRule> updatePrecedentRule({
    required String ruleId,
    required String text,
  }) async {
    final ruleText = _requiredRuleText(text);
    final row =
        await (database.select(database.focusPrecedentRules)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.id.equals(ruleId)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      throw StateError('下必为例不存在或已删除。');
    }
    final now = _now().toUtc();
    await (database.update(database.focusPrecedentRules)
          ..where((rule) => rule.userId.equals(userId))
          ..where((rule) => rule.id.equals(ruleId)))
        .write(
          db.FocusPrecedentRulesCompanion(
            ruleText: Value(ruleText),
            updatedAt: Value(now),
          ),
        );
    await _queue('focus_precedent_rule', ruleId, now);
    return PrecedentRule(
      id: row.id,
      text: ruleText,
      createdAt: row.createdAt,
      updatedAt: now,
    );
  }

  @override
  Future<void> deletePrecedentRule(String ruleId) async {
    final row =
        await (database.select(database.focusPrecedentRules)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.id.equals(ruleId)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) return;
    final now = _now().toUtc();
    await (database.update(database.focusPrecedentRules)
          ..where((rule) => rule.userId.equals(userId))
          ..where((rule) => rule.id.equals(ruleId)))
        .write(
          db.FocusPrecedentRulesCompanion(
            updatedAt: Value(now),
            deletedAt: Value(now),
          ),
        );
    await _queue('focus_precedent_rule', ruleId, now);
  }

  @override
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) async {
    _validateDuration(duration);
    final task = await _taskForStart(taskId);
    if (task.isComplete) throw StateError('已完成任务不能开始新的专注。');

    await _settleDueAppointments();
    await _settleDueSessions();
    final appointment = await _activeAppointmentRow();
    if (appointment != null) {
      throw StateError('已有预约准备，请先返回原流程或提前进入/取消预约。');
    }
    final existing = await getActiveSession();
    if (existing != null) return existing;

    final startedAt = _now().toUtc();
    final session = FocusSession(
      id: _uuid.v4(),
      taskId: taskId,
      mode: mode,
      durationSeconds: duration.inSeconds,
      startedAt: startedAt,
      endsAt: startedAt.add(duration),
      status: FocusSessionStatus.active,
      completedAt: null,
      effectiveSeconds: 0,
      effectiveIntervals: [
        FocusTimeInterval(startedAt: startedAt, endedAt: null),
      ],
    );
    await database.transaction(() async {
      await _saveSession(session);
      final preferences = await (database.select(
        database.focusPreferences,
      )..where((entry) => entry.userId.equals(userId))).getSingleOrNull();
      if (preferences == null) {
        await database
            .into(database.focusPreferences)
            .insert(
              db.FocusPreferencesCompanion.insert(
                userId: userId,
                lastMode: mode.storageValue,
              ),
            );
      } else {
        await (database.update(
          database.focusPreferences,
        )..where((entry) => entry.userId.equals(userId))).write(
          db.FocusPreferencesCompanion(lastMode: Value(mode.storageValue)),
        );
      }
    });
    await _publish();
    return session;
  }

  @override
  Future<void> settleDueSessions() async {
    await _settleDueAppointments();
    await _settleDueSessions();
  }

  @override
  Future<FocusSession> pauseSession(
    String sessionId, {
    required String ruleText,
  }) async {
    final normalizedRule = _requiredRuleText(ruleText);
    await _settleDueSessions();
    final now = _now().toUtc();
    await database.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
      if (row.status != 'active') {
        if (row.status == 'paused') return;
        throw StateError('当前专注会话已经结算。');
      }
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('paused'),
              pausedAt: Value(now),
              pauseRuleText: Value(normalizedRule),
              effectiveIntervals: Value(
                _encodeIntervals(_closeCurrentInterval(row, now)),
              ),
            ),
          );
      await _queue('focus_session', sessionId, now);
    });
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<FocusSession> resumeSession(String sessionId) async {
    final now = _now().toUtc();
    await database.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
      if (row.status == 'active') return;
      if (row.status != 'paused' || row.pausedAt == null) {
        throw StateError('当前专注会话不能继续。');
      }
      final pausedDuration = now.difference(row.pausedAt!);
      final pausedSeconds = pausedDuration.inSeconds;
      final adjustedEndsAt = row.endsAt.add(pausedDuration);
      final intervals = _closedIntervalsFor(row, row.pausedAt!)
        ..add(FocusTimeInterval(startedAt: now, endedAt: null));
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('active'),
              endsAt: Value(adjustedEndsAt),
              pausedAt: const Value(null),
              pausedSeconds: Value(row.pausedSeconds + pausedSeconds),
              effectiveIntervals: Value(_encodeIntervals(intervals)),
            ),
          );
      await _queue('focus_session', sessionId, now);
    });
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<FocusSession> completeEarlySession({
    required String sessionId,
    required String ruleText,
  }) async {
    final normalizedRule = _requiredRuleText(ruleText);
    await _settleDueSessions();
    final existing = await _sessionRow(sessionId);
    if (existing == null) {
      throw StateError('专注会话不存在或已不属于当前用户。');
    }
    if (existing.status == 'completed') {
      if (existing.completionType ==
          FocusSessionCompletionType.precedentRule.storageValue) {
        return (await getSession(sessionId))!;
      }
      throw StateError('正常完成的专注不能改为提前完成。');
    }
    if (existing.status == 'failed') {
      throw StateError('失败的专注不能改为提前完成。');
    }
    await _completeSession(
      sessionId,
      now: _now().toUtc(),
      completionType: FocusSessionCompletionType.precedentRule,
      completionRuleText: normalizedRule,
    );
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<FocusSession> abandonSession({
    required String sessionId,
    required String failureReason,
  }) async {
    final reason = _requiredFailureReason(failureReason);
    await _settleDueSessions();
    final now = _now().toUtc();
    await database.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
      if (row.status == 'failed') return;
      if (row.status == 'completed') throw StateError('正常完成的专注不能改为失败。');
      final effectiveSeconds = _effectiveSeconds(row, now);
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('failed'),
              completedAt: Value(now),
              pausedAt: const Value(null),
              effectiveSeconds: Value(effectiveSeconds),
              failureReason: Value(reason),
              effectiveIntervals: Value(
                _encodeIntervals(_closeCurrentInterval(row, now)),
              ),
            ),
          );
      if (row.reviewDisposition ==
          FocusRecordDisposition.accepted.storageValue) {
        await _addTaskProgress(row.taskId, effectiveSeconds, now);
        final record =
            await (database.select(database.focusChainRecords)
                  ..where((entry) => entry.userId.equals(userId))
                  ..where((entry) => entry.mode.equals(row.mode)))
                .getSingleOrNull();
        await database
            .into(database.focusChainRecords)
            .insertOnConflictUpdate(
              db.FocusChainRecordsCompanion.insert(
                userId: userId,
                mode: row.mode,
                currentConsecutive: const Value(0),
                bestConsecutive: Value(record?.bestConsecutive ?? 0),
                updatedAt: now,
              ),
            );
        await _queue('focus_chain', row.mode, now);
      }
      await _queue('focus_session', sessionId, now);
    });
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  }) async {
    final reason = _requiredFailureReason(failureReason);
    final row = await _sessionRow(sessionId);
    if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
    if (row.status != 'failed') throw StateError('只有失败的专注可以编辑失败原因。');
    await (database.update(database.focusSessions)
          ..where((session) => session.userId.equals(userId))
          ..where((session) => session.id.equals(sessionId)))
        .write(db.FocusSessionsCompanion(failureReason: Value(reason)));
    await _queue('focus_session', sessionId, _now().toUtc());
    await _publish();
  }

  @override
  Future<void> updateNodeNote({
    required String nodeId,
    required String note,
  }) async {
    final normalized = note.trim();
    if (normalized.length > 500) throw ArgumentError('节点备注不能超过 500 字。');
    final row =
        await (database.select(database.focusNodes)
              ..where((node) => node.userId.equals(userId))
              ..where((node) => node.id.equals(nodeId)))
            .getSingleOrNull();
    if (row == null) throw StateError('专注节点不存在或已不属于当前用户。');
    final now = _now().toUtc();
    await (database.update(database.focusNodes)
          ..where((node) => node.userId.equals(userId))
          ..where((node) => node.id.equals(nodeId)))
        .write(
          db.FocusNodesCompanion(
            note: Value(normalized.isEmpty ? null : normalized),
          ),
        );
    await _queue('focus_node', nodeId, now);
    await _publish();
  }

  Future<void> _settleDueSessions() async {
    final now = _now().toUtc();
    final rows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where((session) => session.status.equals('active'))
              ..where(
                (session) => session.reviewDisposition.equals(
                  FocusRecordDisposition.accepted.storageValue,
                ),
              )
              ..where((session) => session.endsAt.isSmallerOrEqualValue(now)))
            .get();
    for (final row in rows) {
      await _completeSession(row.id, now: now);
    }
    if (rows.isNotEmpty) await _publish();
  }

  Future<void> _settleDueAppointments() {
    final inFlight = _appointmentSettlement;
    if (inFlight != null) return inFlight;
    final future = _settleDueAppointmentsInternal();
    _appointmentSettlement = future;
    return future.whenComplete(() {
      if (identical(_appointmentSettlement, future)) {
        _appointmentSettlement = null;
      }
    });
  }

  Future<void> _settleDueAppointmentsInternal() async {
    final now = _now().toUtc();
    final rows =
        await (database.select(database.focusAppointments)
              ..where((appointment) => appointment.userId.equals(userId))
              ..where(
                (appointment) => appointment.status.equals(
                  AppointmentPreparationStatus.active.storageValue,
                ),
              )
              ..where(
                (appointment) => appointment.reviewDisposition.equals(
                  FocusRecordDisposition.accepted.storageValue,
                ),
              )
              ..where(
                (appointment) => appointment.endsAt.isSmallerOrEqualValue(now),
              ))
            .get();
    for (final row in rows) {
      await database.transaction(() async {
        final current = await _appointmentRow(row.id);
        if (current == null ||
            current.status !=
                AppointmentPreparationStatus.active.storageValue ||
            current.reviewDisposition !=
                FocusRecordDisposition.accepted.storageValue) {
          return;
        }
        final sessionId = current.sessionId ?? current.id;
        final existingSession = await _sessionRow(sessionId);
        if (existingSession == null) {
          final session = FocusSession(
            id: sessionId,
            appointmentId: current.id,
            taskId: current.taskId,
            mode: FocusChainMode.fromStorage(current.mode),
            durationSeconds: current.durationSeconds,
            startedAt: current.endsAt,
            endsAt: current.endsAt.add(
              Duration(seconds: current.durationSeconds),
            ),
            status: FocusSessionStatus.active,
            completedAt: null,
            effectiveSeconds: 0,
            effectiveIntervals: [
              FocusTimeInterval(startedAt: current.endsAt, endedAt: null),
            ],
          );
          await _saveSession(session);
        }
        final succeeded = await _succeedAppointment(
          current.id,
          sessionId: sessionId,
          settledAt: current.endsAt,
          updatedAt: now,
        );
        if (succeeded) {
          await _incrementAppointmentRecord(current.endsAt);
        }
      });
    }
    if (rows.isNotEmpty) await _publish();
  }

  Future<bool> _succeedAppointment(
    String appointmentId, {
    required String sessionId,
    required DateTime settledAt,
    required DateTime updatedAt,
    bool allowPendingReview = false,
  }) async {
    final update = database.update(database.focusAppointments)
      ..where((appointment) => appointment.userId.equals(userId))
      ..where((appointment) => appointment.id.equals(appointmentId))
      ..where(
        (appointment) => appointment.status.equals(
          AppointmentPreparationStatus.active.storageValue,
        ),
      );
    if (!allowPendingReview) {
      update.where(
        (appointment) => appointment.reviewDisposition.equals(
          FocusRecordDisposition.accepted.storageValue,
        ),
      );
    }
    final changed = await update.write(
      db.FocusAppointmentsCompanion(
        status: const Value('succeeded'),
        settledAt: Value(settledAt),
        sessionId: Value(sessionId),
        updatedAt: Value(updatedAt),
      ),
    );
    if (changed == 0) return false;
    await _queue('focus_appointment', appointmentId, updatedAt);
    return true;
  }

  Future<void> _incrementAppointmentRecord(DateTime updatedAt) async {
    final current = await (database.select(
      database.appointmentChainRecords,
    )..where((record) => record.userId.equals(userId))).getSingleOrNull();
    final consecutive = (current?.currentConsecutive ?? 0) + 1;
    final best = consecutive > (current?.bestConsecutive ?? 0)
        ? consecutive
        : (current?.bestConsecutive ?? 0);
    await database
        .into(database.appointmentChainRecords)
        .insertOnConflictUpdate(
          db.AppointmentChainRecordsCompanion.insert(
            userId: userId,
            currentConsecutive: Value(consecutive),
            bestConsecutive: Value(best),
            updatedAt: updatedAt,
          ),
        );
    await _queue('appointment_chain', userId, updatedAt);
  }

  Future<void> _resetAppointmentRecord(DateTime updatedAt) async {
    final current = await (database.select(
      database.appointmentChainRecords,
    )..where((record) => record.userId.equals(userId))).getSingleOrNull();
    await database
        .into(database.appointmentChainRecords)
        .insertOnConflictUpdate(
          db.AppointmentChainRecordsCompanion.insert(
            userId: userId,
            currentConsecutive: const Value(0),
            bestConsecutive: Value(current?.bestConsecutive ?? 0),
            updatedAt: updatedAt,
          ),
        );
  }

  Future<db.LocalTask> _taskForStart(
    String taskId, {
    bool allowDeleted = false,
  }) async {
    final task =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(taskId)))
            .getSingleOrNull();
    if (task == null || (!allowDeleted && task.deletedAt != null)) {
      throw StateError('任务不存在或已删除。');
    }
    return task;
  }

  void _validateDuration(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError('专注时长必须大于 0。');
    }
  }

  Future<void> _completeSession(
    String sessionId, {
    required DateTime now,
    FocusSessionCompletionType completionType =
        FocusSessionCompletionType.countdown,
    String? completionRuleText,
  }) async {
    await database.transaction(() async {
      final row =
          await (database.select(database.focusSessions)
                ..where((session) => session.userId.equals(userId))
                ..where((session) => session.id.equals(sessionId)))
              .getSingleOrNull();
      final isEarlyCompletion =
          completionType == FocusSessionCompletionType.precedentRule;
      if (row == null ||
          (!isEarlyCompletion &&
              (row.status != 'active' || row.endsAt.isAfter(now))) ||
          (isEarlyCompletion &&
              row.status != 'active' &&
              row.status != 'paused')) {
        return;
      }
      final seconds = isEarlyCompletion
          ? _effectiveSeconds(row, now)
          : row.durationSeconds;
      if (isEarlyCompletion && seconds <= 0) {
        throw StateError('至少需要有有效专注时间才能提前完成。');
      }
      final completedAt = isEarlyCompletion ? now : row.endsAt;
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('completed'),
              completedAt: Value(completedAt),
              effectiveSeconds: Value(seconds),
              completionType: Value(completionType.storageValue),
              completionRuleText: Value(completionRuleText),
              pausedAt: const Value(null),
              effectiveIntervals: Value(
                _encodeIntervals(_closeCurrentInterval(row, completedAt)),
              ),
            ),
          );

      if (row.reviewDisposition ==
          FocusRecordDisposition.accepted.storageValue) {
        // One node is generated per logical session. Reusing the session UUID
        // makes the completion idempotent both locally and in Supabase.
        final nodeId = sessionId;
        final existingNode =
            await (database.select(database.focusNodes)
                  ..where((node) => node.userId.equals(userId))
                  ..where((node) => node.id.equals(nodeId)))
                .getSingleOrNull();
        if (existingNode == null) {
          await database
              .into(database.focusNodes)
              .insert(
                db.FocusNodesCompanion.insert(
                  userId: userId,
                  id: nodeId,
                  sessionId: sessionId,
                  taskId: row.taskId,
                  mode: row.mode,
                  createdAt: completedAt,
                  effectiveSeconds: seconds,
                ),
              );

          await _addTaskProgress(row.taskId, seconds, completedAt);

          final mode = row.mode;
          final record =
              await (database.select(database.focusChainRecords)
                    ..where((entry) => entry.userId.equals(userId))
                    ..where((entry) => entry.mode.equals(mode)))
                  .getSingleOrNull();
          final current = (record?.currentConsecutive ?? 0) + 1;
          final best = current > (record?.bestConsecutive ?? 0)
              ? current
              : (record?.bestConsecutive ?? 0);
          await database
              .into(database.focusChainRecords)
              .insertOnConflictUpdate(
                db.FocusChainRecordsCompanion.insert(
                  userId: userId,
                  mode: mode,
                  currentConsecutive: Value(current),
                  bestConsecutive: Value(best),
                  updatedAt: completedAt,
                ),
              );
          await _queue('focus_node', nodeId, completedAt);
          await _queue('focus_chain', mode, completedAt);
        }
      }
      await _queue('focus_session', sessionId, completedAt);
    });
  }

  @override
  Future<List<FocusNode>> getNodes() async {
    final rows =
        await (database.select(database.focusNodes)
              ..where((node) => node.userId.equals(userId))
              ..orderBy([(node) => OrderingTerm.desc(node.createdAt)]))
            .get();
    return [for (final row in rows) _nodeFromRow(row)];
  }

  Future<_PendingFocusConfigurationKeys>
  _getPendingFocusConfigurationKeys() async {
    final pendingSessions =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where(
                (session) => session.reviewDisposition.equals(
                  FocusRecordDisposition.pendingReview.storageValue,
                ),
              ))
            .get();
    final pendingSessionIds = {
      for (final session in pendingSessions) session.id,
    };
    if (pendingSessionIds.isEmpty) {
      return const _PendingFocusConfigurationKeys(taskIds: {}, modes: {});
    }
    final linkedAppointmentIds = <String>{
      for (final session in pendingSessions)
        if (session.appointmentId != null) session.appointmentId!,
    };
    final taskIds = {for (final session in pendingSessions) session.taskId};
    final modes = {for (final session in pendingSessions) session.mode};
    final sources = await _getSyncSources();

    for (final source in sources) {
      if (source.entityType != 'focus_session' ||
          !pendingSessionIds.contains(source.entityId)) {
        continue;
      }
      final variant = _focusSessionFromJson(
        jsonDecode(source.payload) as Map<String, dynamic>,
      );
      taskIds.add(variant.taskId);
      modes.add(variant.mode.storageValue);
      if (variant.appointmentId != null) {
        linkedAppointmentIds.add(variant.appointmentId!);
      }
    }

    for (final source in sources) {
      if (source.entityType != 'focus_appointment' ||
          !linkedAppointmentIds.contains(source.entityId)) {
        continue;
      }
      final variant = _focusAppointmentFromJson(
        jsonDecode(source.payload) as Map<String, dynamic>,
      );
      taskIds.add(variant.taskId);
      modes.add(variant.mode.storageValue);
    }

    return _PendingFocusConfigurationKeys(
      taskIds: Set.unmodifiable(taskIds),
      modes: Set.unmodifiable(modes),
    );
  }

  @override
  Future<List<FocusChainRecord>> getChainRecords() async {
    final rows = await (database.select(
      database.focusChainRecords,
    )..where((record) => record.userId.equals(userId))).get();
    final pendingReviewConfigurations =
        await _getPendingFocusConfigurationKeys();
    final pendingModes = pendingReviewConfigurations.modes;
    final byMode = {for (final row in rows) row.mode: _recordFromRow(row)};
    final now = _now().toUtc();
    return [
      for (final mode in FocusChainMode.values)
        () {
          final record =
              byMode[mode.storageValue] ??
              FocusChainRecord(
                mode: mode,
                currentConsecutive: 0,
                bestConsecutive: 0,
                updatedAt: now,
              );
          return FocusChainRecord(
            mode: record.mode,
            currentConsecutive: record.currentConsecutive,
            bestConsecutive: record.bestConsecutive,
            updatedAt: record.updatedAt,
            hasPendingReview: pendingModes.contains(mode.storageValue),
          );
        }(),
    ];
  }

  @override
  Future<FocusChainMode> getLastMode() async {
    final row = await (database.select(
      database.focusPreferences,
    )..where((entry) => entry.userId.equals(userId))).getSingleOrNull();
    return row == null
        ? FocusChainMode.regular
        : FocusChainMode.fromStorage(row.lastMode);
  }

  @override
  Future<void> sync() {
    final nextSync = _syncQueue
        .catchError((Object _) {})
        .then((_) => _syncOnce());
    _syncQueue = nextSync;
    return nextSync;
  }

  Future<void> _syncOnce() async {
    await settleDueSessions();
    final snapshot = await remote.pull(userId: userId);
    final dispositionUpdates = <String, FocusSession>{};
    for (final source in snapshot.sources) {
      await database
          .into(database.focusSyncSources)
          .insert(
            db.FocusSyncSourcesCompanion.insert(
              userId: userId,
              sourceId: source.sourceId,
              deviceId: source.deviceId,
              entityType: source.entityType,
              entityId: source.entityId,
              parentSourceId: Value(source.parentSourceId),
              parentSourceIds: Value(jsonEncode(source.parentSourceIds)),
              occurredAt: source.occurredAt,
              payload: source.payload,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    final sources = await _getSyncSources();
    final sessionSourceHeads = _focusSourceHeads(
      sources,
      entityType: 'focus_session',
    );
    final appointmentSourceHeads = _focusSourceHeads(
      sources,
      entityType: 'focus_appointment',
    );
    final conflictingSessionIds = _conflictingFocusEntityIds(
      sources,
      entityType: 'focus_session',
    );
    final conflictingAppointmentIds = _conflictingFocusEntityIds(
      sources,
      entityType: 'focus_appointment',
    );
    final sourceSessions = {
      for (final entry in sessionSourceHeads.entries)
        entry.key: _focusSessionFromJson(
          jsonDecode(entry.value.payload) as Map<String, dynamic>,
        ),
    };
    final sourceAppointments = {
      for (final entry in appointmentSourceHeads.entries)
        entry.key: _focusAppointmentFromJson(
          jsonDecode(entry.value.payload) as Map<String, dynamic>,
        ),
    };
    final sourcesById = {for (final source in sources) source.sourceId: source};
    final appointmentSessionIds = <String>{};
    for (final source in sources) {
      if (source.entityType == 'focus_appointment' &&
          conflictingAppointmentIds.contains(source.entityId)) {
        final appointment = _focusAppointmentFromJson(
          jsonDecode(source.payload) as Map<String, dynamic>,
        );
        final sessionId = appointment.sessionId;
        if (sessionId != null) appointmentSessionIds.add(sessionId);
      } else if (source.entityType == 'focus_session') {
        final session = _focusSessionFromJson(
          jsonDecode(source.payload) as Map<String, dynamic>,
        );
        final appointmentId = session.appointmentId;
        if (appointmentId != null &&
            conflictingAppointmentIds.contains(appointmentId)) {
          appointmentSessionIds.add(session.id);
        }
      }
    }
    conflictingSessionIds.addAll(appointmentSessionIds);

    for (final sessionId in conflictingSessionIds) {
      final local = await _sessionRow(sessionId);
      FocusSession? candidate = local == null
          ? sourceSessions[sessionId]
          : _sessionFromRow(local);
      if (candidate == null) {
        for (final session in snapshot.sessions) {
          if (session.id == sessionId) {
            candidate = session;
            break;
          }
        }
      }
      if (candidate == null) continue;
      if (local == null) await _saveSession(candidate, queue: false);
      final pending = candidate.copyWithReviewDisposition(
        disposition: FocusRecordDisposition.pendingReview,
        reviewedAt: _now().toUtc(),
      );
      await (database.update(database.focusSessions)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              reviewDisposition: Value(
                FocusRecordDisposition.pendingReview.storageValue,
              ),
              reviewDispositionUpdatedAt: Value(
                pending.reviewDispositionUpdatedAt,
              ),
            ),
          );
      dispositionUpdates[sessionId] = pending;
    }

    for (final appointmentId in conflictingAppointmentIds) {
      final local = await _appointmentRow(appointmentId);
      AppointmentPreparation? candidate = local == null
          ? sourceAppointments[appointmentId]
          : _appointmentFromRow(local);
      if (candidate == null) {
        for (final appointment in snapshot.appointments) {
          if (appointment.id == appointmentId) {
            candidate = appointment;
            break;
          }
        }
      }
      if (candidate == null) continue;
      if (local == null) await _saveAppointment(candidate, queue: false);
      final heads = _focusSourceHeadGroups(
        sources,
        entityType: 'focus_appointment',
      )[appointmentId]!;
      final selectedBasisIds = heads
          .map(
            (source) => _focusAppointmentFromJson(
              jsonDecode(source.payload) as Map<String, dynamic>,
            ).configurationBasisSourceId,
          )
          .whereType<String>()
          .toSet();
      final proposedBasisId = selectedBasisIds.length == 1
          ? selectedBasisIds.single
          : null;
      final selectedSource = proposedBasisId == null
          ? null
          : sourcesById[proposedBasisId];
      final selectedBasisId = selectedSource == null ? null : proposedBasisId;
      if (selectedSource != null) {
        final selectedConfiguration = _focusAppointmentFromJson(
          jsonDecode(selectedSource.payload) as Map<String, dynamic>,
        );
        candidate = candidate.copyWithConfiguration(
          taskId: selectedConfiguration.taskId,
          mode: selectedConfiguration.mode,
          durationSeconds: selectedConfiguration.durationSeconds,
          sourceId: selectedBasisId,
          updatedAt: candidate.updatedAt,
        );
      } else {
        candidate = candidate.copyWithConfiguration(
          taskId: candidate.taskId,
          mode: candidate.mode,
          durationSeconds: candidate.durationSeconds,
          sourceId: selectedBasisId,
          updatedAt: candidate.updatedAt,
        );
      }
      final pending = candidate.copyWithReviewDisposition(
        disposition: FocusRecordDisposition.pendingReview,
        reviewedAt: _now().toUtc(),
      );
      await (database.update(database.focusAppointments)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.id.equals(appointmentId)))
          .write(
            db.FocusAppointmentsCompanion(
              taskId: Value(candidate.taskId),
              mode: Value(candidate.mode.storageValue),
              durationSeconds: Value(candidate.durationSeconds),
              configurationBasisSourceId: Value(selectedBasisId),
              reviewDisposition: Value(
                FocusRecordDisposition.pendingReview.storageValue,
              ),
              reviewDispositionUpdatedAt: Value(
                pending.reviewDispositionUpdatedAt,
              ),
            ),
          );
    }

    for (final appointment in snapshot.appointments) {
      if (conflictingAppointmentIds.contains(appointment.id)) continue;
      final sourceAppointment = sourceAppointments[appointment.id];
      final remoteAppointment = sourceAppointment == null
          ? appointment
          : _focusAppointmentWithRemoteReview(sourceAppointment, appointment);
      final local = await _appointmentRow(appointment.id);
      if (local == null ||
          remoteAppointment.updatedAt.isAfter(local.updatedAt) ||
          (remoteAppointment.updatedAt.isAtSameMomentAs(local.updatedAt) &&
              remoteAppointment.status != AppointmentPreparationStatus.active &&
              local.status ==
                  AppointmentPreparationStatus.active.storageValue) ||
          (sourceAppointment != null &&
              _sourceHeadDescendsFromLocal(
                _focusAppointmentToJson(_appointmentFromRow(local)),
                entityType: 'focus_appointment',
                entityId: appointment.id,
                sourceHead: appointmentSourceHeads[appointment.id]!,
                sources: sources,
              ))) {
        await _saveAppointment(remoteAppointment, queue: false);
      }
    }
    for (final session in snapshot.sessions) {
      if (conflictingSessionIds.contains(session.id)) continue;
      final sourceSession = sourceSessions[session.id];
      final remoteSession = sourceSession == null
          ? session
          : _focusSessionWithRemoteReview(sourceSession, session);
      final local =
          await (database.select(database.focusSessions)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.id.equals(session.id)))
              .getSingleOrNull();
      final remoteReviewAt = remoteSession.reviewDispositionUpdatedAt;
      if (local != null &&
          remoteReviewAt != null &&
          (local.reviewDispositionUpdatedAt == null ||
              remoteReviewAt.isAfter(local.reviewDispositionUpdatedAt!))) {
        if (local.reviewDisposition !=
            remoteSession.reviewDisposition.storageValue) {
          dispositionUpdates[session.id] = remoteSession;
        } else {
          await (database.update(database.focusSessions)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.id.equals(session.id)))
              .write(
                db.FocusSessionsCompanion(
                  reviewDispositionUpdatedAt: Value(remoteReviewAt),
                ),
              );
        }
      }
      final shouldApplyCompletedEffects =
          remoteSession.status == FocusSessionStatus.completed &&
          (local == null ||
              local.status == 'active' ||
              local.status == 'paused');
      if (local == null ||
          ((local.status == 'active' || local.status == 'paused') &&
              !remoteSession.status.isUnfinished) ||
          (sessionSourceHeads[session.id] != null &&
              _sourceHeadDescendsFromLocal(
                _focusSessionToJson(_sessionFromRow(local)),
                entityType: 'focus_session',
                entityId: session.id,
                sourceHead: sessionSourceHeads[session.id]!,
                sources: sources,
              ))) {
        await _saveSession(remoteSession, queue: false);
        if (remoteSession.isFailed) await _applyFailedEffects(remoteSession);
        if (shouldApplyCompletedEffects) {
          await _applyCompletedEffects(remoteSession);
        }
      }
    }
    await _markNewOverlappingSessionsPending(dispositionUpdates);
    final reviewDispositionBySession = {
      for (final session in await _getSessionsWithoutSettling())
        session.id: session.reviewDisposition,
    };
    for (final node in snapshot.nodes) {
      final disposition = reviewDispositionBySession[node.sessionId];
      if (disposition != null && !disposition.contributesToFocusProgress) {
        continue;
      }
      await database
          .into(database.focusNodes)
          .insertOnConflictUpdate(
            db.FocusNodesCompanion.insert(
              userId: userId,
              id: node.id,
              sessionId: node.sessionId,
              taskId: node.taskId,
              mode: node.mode.storageValue,
              createdAt: node.createdAt,
              effectiveSeconds: node.effectiveSeconds,
              note: Value(node.note),
            ),
          );
    }
    for (final record in snapshot.records) {
      final local =
          await (database.select(database.focusChainRecords)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.mode.equals(record.mode.storageValue)))
              .getSingleOrNull();
      if (local == null || record.updatedAt.isAfter(local.updatedAt)) {
        await database
            .into(database.focusChainRecords)
            .insertOnConflictUpdate(
              db.FocusChainRecordsCompanion.insert(
                userId: userId,
                mode: record.mode.storageValue,
                currentConsecutive: Value(record.currentConsecutive),
                bestConsecutive: Value(record.bestConsecutive),
                updatedAt: record.updatedAt,
              ),
            );
      }
    }
    for (final record in snapshot.appointmentRecords) {
      final local = await (database.select(
        database.appointmentChainRecords,
      )..where((row) => row.userId.equals(userId))).getSingleOrNull();
      if (local == null || record.updatedAt.isAfter(local.updatedAt)) {
        await database
            .into(database.appointmentChainRecords)
            .insertOnConflictUpdate(
              db.AppointmentChainRecordsCompanion.insert(
                userId: userId,
                currentConsecutive: Value(record.currentConsecutive),
                bestConsecutive: Value(record.bestConsecutive),
                updatedAt: record.updatedAt,
              ),
            );
      }
    }
    for (final rule in snapshot.precedentRules) {
      final local =
          await (database.select(database.focusPrecedentRules)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.id.equals(rule.id)))
              .getSingleOrNull();
      if (local == null ||
          rule.updatedAt.isAfter(local.updatedAt) ||
          (rule.updatedAt.isAtSameMomentAs(local.updatedAt) &&
              rule.deletedAt != null &&
              local.deletedAt == null)) {
        await database
            .into(database.focusPrecedentRules)
            .insertOnConflictUpdate(
              db.FocusPrecedentRulesCompanion.insert(
                userId: userId,
                id: rule.id,
                ruleText: rule.text,
                createdAt: rule.createdAt,
                updatedAt: rule.updatedAt,
                deletedAt: Value(rule.deletedAt),
              ),
            );
      }
    }
    if (dispositionUpdates.isNotEmpty) {
      await _reconcileFocusEffectsAfterDispositionChanges(
        updates: dispositionUpdates,
      );
    }
    if (conflictingAppointmentIds.isNotEmpty) {
      await _reconcileAppointmentChainAfterDispositionChanges();
    }
    await _reconcileTaskFocusProgressFromSessions();
    await _removeNodesForNonAcceptedSessionsAndRemote();
    final sessions = await getSessions();
    final appointments = await getAppointments();
    final nodes = await getNodes();
    final records = await getChainRecords();
    final appointmentRecord = await getAppointmentChainRecord();
    final precedentRules = await _getPrecedentRulesIncludingDeleted();
    if (appointments.isNotEmpty) {
      await remote.upsertAppointments(
        userId: userId,
        appointments: appointments,
      );
    }
    if (sessions.isNotEmpty) {
      await remote.upsertSessions(userId: userId, sessions: sessions);
    }
    if (nodes.isNotEmpty) {
      await remote.upsertNodes(userId: userId, nodes: nodes);
    }
    await remote.upsertRecords(userId: userId, records: records);
    await remote.upsertAppointmentRecords(
      userId: userId,
      records: [appointmentRecord],
    );
    await remote.upsertPrecedentRules(userId: userId, rules: precedentRules);
    final currentSources = await _getSyncSources();
    if (currentSources.isNotEmpty) {
      await remote.upsertSources(userId: userId, sources: currentSources);
    }
    await _publish();
  }

  Future<void> _markNewOverlappingSessionsPending(
    Map<String, FocusSession> dispositionUpdates,
  ) async {
    final sessions = await _getSessionsWithoutSettling();
    final sources = await _getSyncSources();
    final headsBySession = _focusSourceHeadGroups(
      sources,
      entityType: 'focus_session',
    );
    final sessionsById = {for (final session in sessions) session.id: session};
    final comparisonSessions = [
      for (final session in sessions)
        _sessionWithUnionedIntervals(session, [
          for (final source in headsBySession[session.id] ?? const [])
            _focusSessionFromJson(
              jsonDecode(source.payload) as Map<String, dynamic>,
            ),
        ]),
    ];
    for (final group in _overlappingFocusSessionGroups(comparisonSessions)) {
      final hasUnreviewedSession = group.any(
        (session) =>
            session.reviewDispositionUpdatedAt == null &&
            session.reviewDisposition != FocusRecordDisposition.duplicate,
      );
      if (!hasUnreviewedSession) continue;
      for (final comparedSession in group) {
        final session = sessionsById[comparedSession.id]!;
        if (session.reviewDisposition == FocusRecordDisposition.duplicate ||
            session.reviewDisposition == FocusRecordDisposition.pendingReview) {
          continue;
        }
        final reviewedAt = _now().toUtc();
        final pending = session.copyWithReviewDisposition(
          disposition: FocusRecordDisposition.pendingReview,
          reviewedAt: reviewedAt,
        );
        await (database.update(database.focusSessions)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.id.equals(session.id)))
            .write(
              db.FocusSessionsCompanion(
                reviewDisposition: Value(
                  FocusRecordDisposition.pendingReview.storageValue,
                ),
                reviewDispositionUpdatedAt: Value(reviewedAt),
              ),
            );
        dispositionUpdates[session.id] = pending;
      }
    }
  }

  @override
  Future<void> dispose() => _changes.close();

  Future<void> _saveSession(FocusSession session, {bool queue = true}) async {
    await database
        .into(database.focusSessions)
        .insertOnConflictUpdate(
          db.FocusSessionsCompanion.insert(
            userId: userId,
            id: session.id,
            appointmentId: Value(session.appointmentId),
            taskId: session.taskId,
            mode: session.mode.storageValue,
            durationSeconds: session.durationSeconds,
            startedAt: session.startedAt,
            endsAt: session.endsAt,
            status: session.status.storageValue,
            completedAt: Value(session.completedAt),
            effectiveSeconds: Value(session.effectiveSeconds),
            completionType: Value(session.completionType.storageValue),
            completionRuleText: Value(session.completionRuleText),
            pausedAt: Value(session.pausedAt),
            pausedSeconds: Value(session.pausedSeconds),
            pauseRuleText: Value(session.pauseRuleText),
            failureReason: Value(session.failureReason),
            effectiveIntervals: Value(
              _encodeIntervals(session.effectiveIntervals),
            ),
            reviewDisposition: Value(session.reviewDisposition.storageValue),
            reviewDispositionUpdatedAt: Value(
              session.reviewDispositionUpdatedAt,
            ),
            configurationBasisSourceId: Value(
              session.configurationBasisSourceId,
            ),
            outcomeBasisSourceId: Value(session.outcomeBasisSourceId),
          ),
        );
    if (queue) await _queue('focus_session', session.id, session.startedAt);
  }

  Future<void> _saveAppointment(
    AppointmentPreparation appointment, {
    bool queue = true,
  }) async {
    await database
        .into(database.focusAppointments)
        .insertOnConflictUpdate(
          db.FocusAppointmentsCompanion.insert(
            userId: userId,
            id: appointment.id,
            taskId: appointment.taskId,
            mode: appointment.mode.storageValue,
            durationSeconds: appointment.durationSeconds,
            startedAt: appointment.startedAt,
            endsAt: appointment.endsAt,
            status: appointment.status.storageValue,
            settledAt: Value(appointment.settledAt),
            sessionId: Value(appointment.sessionId),
            failureReason: Value(appointment.failureReason),
            updatedAt: appointment.updatedAt,
            reviewDisposition: Value(
              appointment.reviewDisposition.storageValue,
            ),
            reviewDispositionUpdatedAt: Value(
              appointment.reviewDispositionUpdatedAt,
            ),
            configurationBasisSourceId: Value(
              appointment.configurationBasisSourceId,
            ),
          ),
        );
    if (queue) {
      await _queue('focus_appointment', appointment.id, appointment.updatedAt);
    }
  }

  Future<void> _queue(
    String type,
    String id,
    DateTime updatedAt, {
    String? parentSourceId,
  }) async {
    if (type == 'focus_session') {
      final row = await _sessionRow(id);
      if (row != null) {
        await _recordSyncSource(
          entityType: type,
          entityId: id,
          occurredAt: updatedAt,
          parentSourceId: parentSourceId,
          payload: jsonEncode(_focusSessionToJson(_sessionFromRow(row))),
        );
      }
    } else if (type == 'focus_appointment') {
      final row = await _appointmentRow(id);
      if (row != null) {
        await _recordSyncSource(
          entityType: type,
          entityId: id,
          occurredAt: updatedAt,
          parentSourceId: parentSourceId,
          payload: jsonEncode(
            _focusAppointmentToJson(_appointmentFromRow(row)),
          ),
        );
      }
    }
    await database
        .into(database.taskSyncEntries)
        .insertOnConflictUpdate(
          db.TaskSyncEntriesCompanion.insert(
            userId: userId,
            entityType: type,
            entityId: id,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> _recordSyncSource({
    required String entityType,
    required String entityId,
    required DateTime occurredAt,
    required String payload,
    String? parentSourceId,
    List<String>? parentSourceIds,
  }) async {
    final deviceId = await _getDeviceId();
    final parents = parentSourceIds == null
        ? parentSourceId == null
              ? await (database.select(database.focusSyncSources)
                      ..where((source) => source.userId.equals(userId))
                      ..where((source) => source.entityType.equals(entityType))
                      ..where((source) => source.entityId.equals(entityId))
                      ..orderBy([
                        (source) => OrderingTerm.desc(source.occurredAt),
                        (source) => OrderingTerm.desc(source.sourceId),
                      ])
                      ..limit(1))
                    .getSingleOrNull()
              : await (database.select(database.focusSyncSources)
                      ..where((source) => source.userId.equals(userId))
                      ..where(
                        (source) => source.sourceId.equals(parentSourceId),
                      ))
                    .getSingleOrNull()
        : null;
    final resolvedParentIds = parentSourceIds != null
        ? parentSourceIds.toSet().toList()
        : parentSourceId != null
        ? [parentSourceId]
        : parents == null
        ? <String>[]
        : [parents.sourceId];
    await database
        .into(database.focusSyncSources)
        .insert(
          db.FocusSyncSourcesCompanion.insert(
            userId: userId,
            sourceId: _uuid.v4(),
            deviceId: deviceId,
            entityType: entityType,
            entityId: entityId,
            parentSourceId: Value(
              resolvedParentIds.isEmpty ? null : resolvedParentIds.first,
            ),
            parentSourceIds: Value(jsonEncode(resolvedParentIds)),
            occurredAt: occurredAt.toUtc(),
            payload: payload,
          ),
        );
  }

  Future<String> _getDeviceId() async {
    final existing = await (database.select(
      database.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (existing != null) return existing.deviceId;
    final deviceId = _uuid.v4();
    await database
        .into(database.focusSourceDevices)
        .insertOnConflictUpdate(
          db.FocusSourceDevicesCompanion.insert(
            userId: userId,
            deviceId: deviceId,
          ),
        );
    return deviceId;
  }

  Future<List<FocusSyncSource>> _getSyncSources() async {
    final rows = await (database.select(
      database.focusSyncSources,
    )..where((source) => source.userId.equals(userId))).get();
    return [
      for (final row in rows)
        FocusSyncSource(
          sourceId: row.sourceId,
          deviceId: row.deviceId,
          entityType: row.entityType,
          entityId: row.entityId,
          parentSourceId: row.parentSourceId,
          parentSourceIds: _decodeParentSourceIds(
            row.parentSourceId,
            row.parentSourceIds,
          ),
          occurredAt: row.occurredAt,
          payload: row.payload,
        ),
    ];
  }

  Future<void> _publish() async {
    if (_changes.hasListener) _changes.add(await _getSessionsWithoutSettling());
  }

  Future<List<FocusSession>> _getSessionsWithoutSettling() async {
    final rows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)]))
            .get();
    return [for (final row in rows) _sessionFromRow(row)];
  }

  Future<List<PrecedentRule>> _getPrecedentRulesIncludingDeleted() async {
    final rows = await (database.select(
      database.focusPrecedentRules,
    )..where((rule) => rule.userId.equals(userId))).get();
    return [for (final row in rows) _precedentRuleFromRow(row)];
  }

  Future<db.FocusSession?> _sessionRow(String sessionId) {
    return (database.select(database.focusSessions)
          ..where((session) => session.userId.equals(userId))
          ..where((session) => session.id.equals(sessionId)))
        .getSingleOrNull();
  }

  Future<db.FocusAppointment?> _appointmentRow(String appointmentId) {
    return (database.select(database.focusAppointments)
          ..where((appointment) => appointment.userId.equals(userId))
          ..where((appointment) => appointment.id.equals(appointmentId)))
        .getSingleOrNull();
  }

  Future<db.FocusAppointment?> _activeAppointmentRow() {
    return (database.select(database.focusAppointments)
          ..where((appointment) => appointment.userId.equals(userId))
          ..where(
            (appointment) => appointment.status.equals(
              AppointmentPreparationStatus.active.storageValue,
            ),
          )
          ..orderBy([(appointment) => OrderingTerm.desc(appointment.startedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<db.FocusSession?> _activeSessionRow() {
    return (database.select(database.focusSessions)
          ..where((session) => session.userId.equals(userId))
          ..where((session) => session.status.isIn(['active', 'paused']))
          ..orderBy([(session) => OrderingTerm.desc(session.startedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  int _effectiveSeconds(db.FocusSession row, DateTime now) {
    final end = row.status == 'paused' && row.pausedAt != null
        ? row.pausedAt!
        : (now.isBefore(row.endsAt) ? now : row.endsAt);
    final elapsed = end.difference(row.startedAt).inSeconds;
    return (elapsed - row.pausedSeconds).clamp(0, row.durationSeconds);
  }

  Future<void> _addTaskProgress(
    String taskId,
    int seconds,
    DateTime updatedAt,
  ) async {
    if (seconds <= 0) return;
    final task =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(taskId)))
            .getSingleOrNull();
    if (task == null) return;
    await (database.update(database.localTasks)
          ..where((task) => task.userId.equals(userId))
          ..where((task) => task.id.equals(taskId)))
        .write(
          db.LocalTasksCompanion(
            focusProgressSeconds: Value(task.focusProgressSeconds + seconds),
          ),
        );
    await _queue('task', taskId, updatedAt);
  }

  Future<void> _reconcileFocusEffectsAfterDispositionChanges({
    required Map<String, FocusSession> updates,
  }) async {
    await database.transaction(() async {
      for (final session in updates.values) {
        await (database.update(database.focusSessions)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.id.equals(session.id)))
            .write(
              db.FocusSessionsCompanion(
                reviewDisposition: Value(
                  session.reviewDisposition.storageValue,
                ),
                reviewDispositionUpdatedAt: Value(
                  session.reviewDispositionUpdatedAt,
                ),
              ),
            );
      }
      final changedRows =
          await (database.select(database.focusSessions)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.id.isIn(updates.keys)))
              .get();
      final modes = FocusChainMode.values
          .map((mode) => mode.storageValue)
          .toSet();
      final dispositionChangedAtBySession = {
        for (final row in changedRows)
          if (row.reviewDispositionUpdatedAt != null)
            row.id: row.reviewDispositionUpdatedAt!,
      };
      for (final row in changedRows) {
        final nodes =
            await (database.select(database.focusNodes)
                  ..where((node) => node.userId.equals(userId))
                  ..where((node) => node.sessionId.equals(row.id)))
                .get();
        final shouldHaveNode =
            row.status == FocusSessionStatus.completed.storageValue &&
            FocusRecordDisposition.fromStorage(row.reviewDisposition)
                .contributesToFocusProgress;
        if (shouldHaveNode) {
          final note = nodes.isEmpty ? null : nodes.first.note;
          await database
              .into(database.focusNodes)
              .insertOnConflictUpdate(
                db.FocusNodesCompanion.insert(
                  userId: userId,
                  id: row.id,
                  sessionId: row.id,
                  taskId: row.taskId,
                  mode: row.mode,
                  createdAt: row.completedAt ?? row.endsAt,
                  effectiveSeconds: row.effectiveSeconds,
                  note: Value(note),
                ),
              );
          await _queue(
            'focus_node',
            row.id,
            dispositionChangedAtBySession[row.id] ?? _now().toUtc(),
          );
        } else if (!shouldHaveNode) {
          for (final node in nodes) {
            await (database.delete(database.focusNodes)
                  ..where((candidate) => candidate.userId.equals(userId))
                  ..where((candidate) => candidate.id.equals(node.id)))
                .go();
          }
        }
      }

      for (final mode in modes) {
        final rows =
            await (database.select(database.focusSessions)
                  ..where((row) => row.userId.equals(userId))
                  ..where((row) => row.mode.equals(mode))
                  ..where(
                    (row) => row.status.isIn([
                      FocusSessionStatus.completed.storageValue,
                      FocusSessionStatus.failed.storageValue,
                    ]),
                  ))
                .get();
        rows.sort((left, right) {
          final leftAt = (left.completedAt ?? left.endsAt).toUtc();
          final rightAt = (right.completedAt ?? right.endsAt).toUtc();
          final byTime = leftAt.compareTo(rightAt);
          return byTime == 0 ? left.id.compareTo(right.id) : byTime;
        });
        var current = 0;
        var best = 0;
        for (final row in rows) {
          if (!FocusRecordDisposition.fromStorage(row.reviewDisposition)
              .contributesToFocusProgress) {
            continue;
          }
          if (row.status == FocusSessionStatus.completed.storageValue) {
            current++;
            if (current > best) best = current;
          } else {
            current = 0;
          }
        }
        final existing =
            await (database.select(database.focusChainRecords)
                  ..where((record) => record.userId.equals(userId))
                  ..where((record) => record.mode.equals(mode)))
                .getSingleOrNull();
        var updatedAt = _now().toUtc();
        if (existing != null && existing.updatedAt.isAfter(updatedAt)) {
          updatedAt = existing.updatedAt;
        }
        for (final timestamp in dispositionChangedAtBySession.values) {
          if (timestamp.isAfter(updatedAt)) updatedAt = timestamp;
        }
        await database
            .into(database.focusChainRecords)
            .insertOnConflictUpdate(
              db.FocusChainRecordsCompanion.insert(
                userId: userId,
                mode: mode,
                currentConsecutive: Value(current),
                bestConsecutive: Value(best),
                updatedAt: updatedAt,
              ),
            );
        await _queue('focus_chain', mode, updatedAt);
      }
    });
  }

  Future<void> _removeNodesForNonAcceptedSessionsAndRemote() async {
    final sessions = await (database.select(
      database.focusSessions,
    )..where((row) => row.userId.equals(userId))).get();
    final excludedSessionIds = [
      for (final session in sessions)
        if (!FocusRecordDisposition.fromStorage(session.reviewDisposition)
            .contributesToFocusProgress)
          session.id,
    ];
    if (excludedSessionIds.isEmpty) return;

    final localNodes =
        await (database.select(database.focusNodes)
              ..where((node) => node.userId.equals(userId))
              ..where((node) => node.sessionId.isIn(excludedSessionIds)))
            .get();
    if (localNodes.isNotEmpty) {
      await database.transaction(() async {
        for (final node in localNodes) {
          await (database.delete(database.focusNodes)
                ..where((candidate) => candidate.userId.equals(userId))
                ..where((candidate) => candidate.id.equals(node.id)))
              .go();
        }
      });
    }
    await remote.deleteNodes(userId: userId, sessionIds: excludedSessionIds);
  }

  Future<void> _reconcileTaskFocusProgressFromSessions() async {
    final settledRows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where(
                (session) => session.status.isIn(['completed', 'failed']),
              ))
            .get();
    final secondsByTask = <String, int>{};
    for (final row in settledRows) {
      final session = _sessionFromRow(row);
      if (!session.reviewDisposition.contributesToFocusProgress) continue;
      final effectiveSeconds = _focusSecondsForProjection(session);
      if (effectiveSeconds <= 0) continue;
      secondsByTask.update(
        session.taskId,
        (seconds) => seconds + effectiveSeconds,
        ifAbsent: () => effectiveSeconds,
      );
    }
    final taskRows = await (database.select(
      database.localTasks,
    )..where((task) => task.userId.equals(userId))).get();
    for (final task in taskRows) {
      final reconciled = secondsByTask[task.id] ?? 0;
      if (task.focusProgressSeconds == reconciled) continue;
      await (database.update(database.localTasks)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.id.equals(task.id)))
          .write(
            db.LocalTasksCompanion(focusProgressSeconds: Value(reconciled)),
          );
      await _queue('task', task.id, _now().toUtc());
    }
  }

  Future<void> _reconcileAppointmentChainAfterDispositionChanges() async {
    final appointments =
        await (database.select(database.focusAppointments)
              ..where((appointment) => appointment.userId.equals(userId))
              ..orderBy([
                (appointment) => OrderingTerm.asc(appointment.startedAt),
              ]))
            .get();
    var currentConsecutive = 0;
    var bestConsecutive = 0;
    for (final appointment in appointments) {
      if (appointment.reviewDisposition !=
          FocusRecordDisposition.accepted.storageValue) {
        continue;
      }
      if (appointment.status ==
          AppointmentPreparationStatus.succeeded.storageValue) {
        currentConsecutive++;
        if (currentConsecutive > bestConsecutive) {
          bestConsecutive = currentConsecutive;
        }
      } else if (appointment.status ==
          AppointmentPreparationStatus.failed.storageValue) {
        currentConsecutive = 0;
      }
    }

    final existing = await (database.select(
      database.appointmentChainRecords,
    )..where((record) => record.userId.equals(userId))).getSingleOrNull();
    if (existing == null ||
        (existing.currentConsecutive == currentConsecutive &&
            existing.bestConsecutive == bestConsecutive)) {
      return;
    }
    var updatedAt = _now().toUtc();
    if (!updatedAt.isAfter(existing.updatedAt)) {
      updatedAt = existing.updatedAt.add(const Duration(microseconds: 1));
    }
    await database
        .into(database.appointmentChainRecords)
        .insertOnConflictUpdate(
          db.AppointmentChainRecordsCompanion.insert(
            userId: userId,
            currentConsecutive: Value(currentConsecutive),
            bestConsecutive: Value(bestConsecutive),
            updatedAt: updatedAt,
          ),
        );
    await _queue('appointment_chain', userId, updatedAt);
  }

  Future<void> _applyFailedEffects(FocusSession session) async {
    if (!session.reviewDisposition.contributesToFocusProgress) return;
    final settledAt = session.completedAt ?? session.endsAt;
    await _addTaskProgress(session.taskId, session.effectiveSeconds, settledAt);
    final record =
        await (database.select(database.focusChainRecords)
              ..where((entry) => entry.userId.equals(userId))
              ..where((entry) => entry.mode.equals(session.mode.storageValue)))
            .getSingleOrNull();
    await database
        .into(database.focusChainRecords)
        .insertOnConflictUpdate(
          db.FocusChainRecordsCompanion.insert(
            userId: userId,
            mode: session.mode.storageValue,
            currentConsecutive: const Value(0),
            bestConsecutive: Value(record?.bestConsecutive ?? 0),
            updatedAt: settledAt,
          ),
        );
    await _queue('focus_chain', session.mode.storageValue, settledAt);
  }

  Future<void> _applyCompletedEffects(FocusSession session) async {
    if (!session.reviewDisposition.contributesToFocusProgress) return;
    final settledAt = session.completedAt ?? session.endsAt;
    await database.transaction(() async {
      final existingNode =
          await (database.select(database.focusNodes)
                ..where((node) => node.userId.equals(userId))
                ..where((node) => node.id.equals(session.id)))
              .getSingleOrNull();
      if (existingNode == null) {
        await database
            .into(database.focusNodes)
            .insert(
              db.FocusNodesCompanion.insert(
                userId: userId,
                id: session.id,
                sessionId: session.id,
                taskId: session.taskId,
                mode: session.mode.storageValue,
                createdAt: settledAt,
                effectiveSeconds: session.effectiveSeconds,
              ),
            );
      }
      await _addTaskProgress(
        session.taskId,
        session.effectiveSeconds,
        settledAt,
      );
      final record =
          await (database.select(database.focusChainRecords)
                ..where((entry) => entry.userId.equals(userId))
                ..where(
                  (entry) => entry.mode.equals(session.mode.storageValue),
                ))
              .getSingleOrNull();
      final current = (record?.currentConsecutive ?? 0) + 1;
      final best = current > (record?.bestConsecutive ?? 0)
          ? current
          : (record?.bestConsecutive ?? 0);
      await database
          .into(database.focusChainRecords)
          .insertOnConflictUpdate(
            db.FocusChainRecordsCompanion.insert(
              userId: userId,
              mode: session.mode.storageValue,
              currentConsecutive: Value(current),
              bestConsecutive: Value(best),
              updatedAt: settledAt,
            ),
          );
      await _queue('focus_node', session.id, settledAt);
      await _queue('focus_chain', session.mode.storageValue, settledAt);
    });
  }

  String _requiredFailureReason(String reason) {
    final normalized = reason.trim();
    if (normalized.isEmpty) throw ArgumentError('失败原因不能为空。');
    if (normalized.length > 200) throw ArgumentError('失败原因不能超过 200 字。');
    return normalized;
  }

  String _requiredRuleText(String ruleText) {
    final normalized = ruleText.trim();
    if (normalized.isEmpty) throw ArgumentError('下必为例内容不能为空。');
    if (normalized.length > 500) throw ArgumentError('下必为例内容不能超过 500 字。');
    return normalized;
  }

  List<FocusTimeInterval> _closeCurrentInterval(
    db.FocusSession row,
    DateTime endedAt,
  ) => _closedIntervalsFor(row, endedAt);

  List<FocusTimeInterval> _closedIntervalsFor(
    db.FocusSession row,
    DateTime endedAt,
  ) {
    final intervals = _decodeIntervals(row.effectiveIntervals);
    final openIndex = intervals.lastIndexWhere(
      (interval) => interval.endedAt == null,
    );
    if (openIndex >= 0) {
      final open = intervals[openIndex];
      final activeEnd = row.status == 'paused' && row.pausedAt != null
          ? row.pausedAt!
          : endedAt;
      if (!activeEnd.isAfter(open.startedAt)) {
        intervals.removeAt(openIndex);
      } else {
        intervals[openIndex] = FocusTimeInterval(
          startedAt: open.startedAt,
          endedAt: activeEnd,
        );
      }
      return intervals;
    }
    if (intervals.isNotEmpty) return intervals;

    // Older sessions did not retain pause boundaries. Preserve their active
    // duration by placing the known paused time at the end of the interval.
    final activeEnd = row.status == 'paused' && row.pausedAt != null
        ? row.pausedAt!
        : endedAt;
    final estimatedEnd = activeEnd.subtract(
      Duration(seconds: row.pausedSeconds),
    );
    if (!estimatedEnd.isAfter(row.startedAt)) return [];
    return [FocusTimeInterval(startedAt: row.startedAt, endedAt: estimatedEnd)];
  }

  FocusSession _sessionFromRow(db.FocusSession row) => FocusSession(
    id: row.id,
    appointmentId: row.appointmentId,
    taskId: row.taskId,
    mode: FocusChainMode.fromStorage(row.mode),
    durationSeconds: row.durationSeconds,
    startedAt: row.startedAt,
    endsAt: row.endsAt,
    status: switch (row.status) {
      'active' => FocusSessionStatus.active,
      'paused' => FocusSessionStatus.paused,
      'failed' => FocusSessionStatus.failed,
      _ => FocusSessionStatus.completed,
    },
    completedAt: row.completedAt,
    effectiveSeconds: row.effectiveSeconds,
    completionType: FocusSessionCompletionType.fromStorage(row.completionType),
    completionRuleText: row.completionRuleText,
    pausedAt: row.pausedAt,
    pausedSeconds: row.pausedSeconds,
    pauseRuleText: row.pauseRuleText,
    failureReason: row.failureReason,
    effectiveIntervals: _decodeIntervals(row.effectiveIntervals),
    reviewDisposition: FocusRecordDisposition.fromStorage(
      row.reviewDisposition,
    ),
    reviewDispositionUpdatedAt: row.reviewDispositionUpdatedAt,
    configurationBasisSourceId: row.configurationBasisSourceId,
    outcomeBasisSourceId: row.outcomeBasisSourceId,
  );

  AppointmentPreparation _appointmentFromRow(db.FocusAppointment row) =>
      AppointmentPreparation(
        id: row.id,
        taskId: row.taskId,
        mode: FocusChainMode.fromStorage(row.mode),
        durationSeconds: row.durationSeconds,
        startedAt: row.startedAt,
        endsAt: row.endsAt,
        status: AppointmentPreparationStatus.fromStorage(row.status),
        settledAt: row.settledAt,
        updatedAt: row.updatedAt,
        sessionId: row.sessionId,
        failureReason: row.failureReason,
        reviewDisposition: FocusRecordDisposition.fromStorage(
          row.reviewDisposition,
        ),
        reviewDispositionUpdatedAt: row.reviewDispositionUpdatedAt,
        configurationBasisSourceId: row.configurationBasisSourceId,
      );

  FocusNode _nodeFromRow(db.FocusNode row) => FocusNode(
    id: row.id,
    sessionId: row.sessionId,
    taskId: row.taskId,
    mode: FocusChainMode.fromStorage(row.mode),
    createdAt: row.createdAt,
    effectiveSeconds: row.effectiveSeconds,
    note: row.note,
  );

  FocusChainRecord _recordFromRow(db.FocusChainRecord row) => FocusChainRecord(
    mode: FocusChainMode.fromStorage(row.mode),
    currentConsecutive: row.currentConsecutive,
    bestConsecutive: row.bestConsecutive,
    updatedAt: row.updatedAt,
  );

  PrecedentRule _precedentRuleFromRow(db.FocusPrecedentRule row) =>
      PrecedentRule(
        id: row.id,
        text: row.ruleText,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );
}

List<FocusTimeInterval> _effectiveIntervalsForProjection(FocusSession session) {
  final closedIntervals = session.effectiveIntervals
      .where(
        (interval) => interval.endedAt != null && interval.durationSeconds > 0,
      )
      .toList();
  if (closedIntervals.isNotEmpty) return closedIntervals;
  if (session.effectiveSeconds <= 0) return const [];
  return [
    FocusTimeInterval(
      startedAt: session.startedAt,
      endedAt: session.startedAt.add(
        Duration(seconds: session.effectiveSeconds),
      ),
    ),
  ];
}

int _focusSecondsForProjection(FocusSession session) =>
    _effectiveIntervalsForProjection(
      session,
    ).fold<int>(0, (seconds, interval) => seconds + interval.durationSeconds);

void _addIntervalByCalendarDay(
  FocusTimeInterval interval,
  timezone.Location location,
  Map<String, int> secondsByDay,
) {
  final end = interval.endedAt?.toUtc();
  if (end == null) return;
  var cursor = interval.startedAt.toUtc();
  if (!end.isAfter(cursor)) return;
  while (cursor.isBefore(end)) {
    final localCursor = timezone.TZDateTime.from(cursor, location);
    final nextDay = timezone.TZDateTime(
      location,
      localCursor.year,
      localCursor.month,
      localCursor.day + 1,
    ).toUtc();
    final boundary = nextDay.isAfter(cursor)
        ? nextDay
        : cursor.add(const Duration(days: 1));
    final segmentEnd = end.isBefore(boundary) ? end : boundary;
    final segmentSeconds = segmentEnd.difference(cursor).inSeconds;
    if (segmentSeconds > 0) {
      final key = _calendarDateKey(
        localCursor.year,
        localCursor.month,
        localCursor.day,
      );
      secondsByDay.update(
        key,
        (seconds) => seconds + segmentSeconds,
        ifAbsent: () => segmentSeconds,
      );
    }
    cursor = segmentEnd;
  }
}

FocusActivityDay _activityDay(
  timezone.TZDateTime date,
  Map<String, int> secondsByDay,
) {
  final dateOnly = DateTime.utc(date.year, date.month, date.day);
  return FocusActivityDay(
    date: dateOnly,
    activeSeconds:
        secondsByDay[_calendarDateKey(date.year, date.month, date.day)] ?? 0,
  );
}

String _calendarDateKey(int year, int month, int day) =>
    '${year.toString().padLeft(4, '0')}-'
    '${month.toString().padLeft(2, '0')}-'
    '${day.toString().padLeft(2, '0')}';

String _encodeIntervals(List<FocusTimeInterval> intervals) => jsonEncode([
  for (final interval in intervals)
    {
      'started_at': _utcIso8601(interval.startedAt),
      'ended_at': interval.endedAt == null
          ? null
          : _utcIso8601(interval.endedAt!),
    },
]);

List<FocusTimeInterval> _decodeIntervals(String encoded) {
  try {
    return _intervalsFromJsonValue(jsonDecode(encoded));
  } on FormatException {
    return const [];
  }
}

List<FocusTimeInterval> _intervalsFromJsonValue(Object? value) {
  if (value is! List) return const [];
  final intervals = <FocusTimeInterval>[];
  for (final raw in value) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final startedAt = item['started_at'];
    if (startedAt is! String) continue;
    final endedAt = item['ended_at'];
    intervals.add(
      FocusTimeInterval(
        startedAt: DateTime.parse(startedAt).toUtc(),
        endedAt: endedAt is String ? DateTime.parse(endedAt).toUtc() : null,
      ),
    );
  }
  return intervals;
}

List<Map<String, Object?>> _intervalsToJson(
  List<FocusTimeInterval> intervals,
) => [
  for (final interval in intervals)
    {
      'started_at': _utcIso8601(interval.startedAt),
      'ended_at': interval.endedAt == null
          ? null
          : _utcIso8601(interval.endedAt!),
    },
];

String _focusConfigurationSignature(FocusSession session) => _canonicalJson({
  'task_id': session.taskId,
  'mode': session.mode.storageValue,
  'duration_seconds': session.durationSeconds,
});

String _focusOutcomeSignature(FocusSession session) => _canonicalJson({
  'status': session.status.storageValue,
  'completed_at': session.completedAt == null
      ? null
      : _utcIso8601(session.completedAt!),
  'completion_type': session.completionType.storageValue,
  'completion_rule_text': session.completionRuleText,
  'failure_reason': session.failureReason,
});

List<FocusTimeInterval> _unionFocusIntervals(Iterable<FocusSession> sessions) {
  final intervals = <FocusTimeInterval>[];
  for (final session in sessions) {
    for (final interval in session.effectiveIntervals) {
      final end = interval.endedAt ?? session.completedAt ?? session.endsAt;
      if (!end.isAfter(interval.startedAt)) continue;
      intervals.add(
        FocusTimeInterval(startedAt: interval.startedAt, endedAt: end),
      );
    }
  }
  intervals.sort((left, right) {
    final byStart = left.startedAt.compareTo(right.startedAt);
    if (byStart != 0) return byStart;
    return left.endedAt!.compareTo(right.endedAt!);
  });
  final merged = <FocusTimeInterval>[];
  for (final interval in intervals) {
    if (merged.isEmpty) {
      merged.add(interval);
      continue;
    }
    final previous = merged.last;
    if (!interval.startedAt.isAfter(previous.endedAt!)) {
      if (interval.endedAt!.isAfter(previous.endedAt!)) {
        merged[merged.length - 1] = FocusTimeInterval(
          startedAt: previous.startedAt,
          endedAt: interval.endedAt,
        );
      }
    } else {
      merged.add(interval);
    }
  }
  return List.unmodifiable(merged);
}

FocusSession _sessionWithUnionedIntervals(
  FocusSession base,
  Iterable<FocusSession> variants,
) {
  final intervals = _unionFocusIntervals(variants);
  if (intervals.isEmpty) return base;
  final seconds = intervals.fold<int>(
    0,
    (total, interval) => total + interval.durationSeconds,
  );
  return FocusSession(
    id: base.id,
    appointmentId: base.appointmentId,
    taskId: base.taskId,
    mode: base.mode,
    durationSeconds: base.durationSeconds,
    startedAt: base.startedAt,
    endsAt: base.endsAt,
    status: base.status,
    completedAt: base.completedAt,
    effectiveSeconds: seconds,
    completionType: base.completionType,
    completionRuleText: base.completionRuleText,
    pausedAt: base.pausedAt,
    pausedSeconds: base.pausedSeconds,
    pauseRuleText: base.pauseRuleText,
    failureReason: base.failureReason,
    effectiveIntervals: intervals,
    reviewDisposition: base.reviewDisposition,
    reviewDispositionUpdatedAt: base.reviewDispositionUpdatedAt,
    configurationBasisSourceId: base.configurationBasisSourceId,
    outcomeBasisSourceId: base.outcomeBasisSourceId,
  );
}

List<List<FocusSession>> _overlappingFocusSessionGroups(
  Iterable<FocusSession> sessions,
) {
  final settled = sessions
      .where(
        (session) =>
            session.status == FocusSessionStatus.completed ||
            session.status == FocusSessionStatus.failed,
      )
      .toList();
  final intervalsById = {
    for (final session in settled) session.id: _unionFocusIntervals([session]),
  };
  final adjacentIds = <String, Set<String>>{
    for (final session in settled) session.id: <String>{},
  };
  for (var leftIndex = 0; leftIndex < settled.length; leftIndex++) {
    final left = settled[leftIndex];
    for (
      var rightIndex = leftIndex + 1;
      rightIndex < settled.length;
      rightIndex++
    ) {
      final right = settled[rightIndex];
      if (_intervalsOverlap(
        intervalsById[left.id]!,
        intervalsById[right.id]!,
      )) {
        adjacentIds[left.id]!.add(right.id);
        adjacentIds[right.id]!.add(left.id);
      }
    }
  }

  final sessionsById = {for (final session in settled) session.id: session};
  final visited = <String>{};
  final groups = <List<FocusSession>>[];
  for (final session in settled) {
    if (!visited.add(session.id) || adjacentIds[session.id]!.isEmpty) continue;
    final pending = <String>[session.id];
    final ids = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!ids.add(id)) continue;
      for (final neighbor in adjacentIds[id]!) {
        if (!ids.contains(neighbor)) pending.add(neighbor);
      }
    }
    final group = [for (final id in ids) sessionsById[id]!]
      ..sort((left, right) {
        final byTime = left.startedAt.compareTo(right.startedAt);
        return byTime == 0 ? left.id.compareTo(right.id) : byTime;
      });
    visited.addAll(ids);
    groups.add(group);
  }
  groups.sort(
    (left, right) => left.first.startedAt.compareTo(right.first.startedAt),
  );
  return groups;
}

bool _intervalsOverlap(
  List<FocusTimeInterval> left,
  List<FocusTimeInterval> right,
) {
  for (final first in left) {
    for (final second in right) {
      if (first.startedAt.isBefore(second.endedAt!) &&
          second.startedAt.isBefore(first.endedAt!)) {
        return true;
      }
    }
  }
  return false;
}

String _reconciliationCaseId(Set<String> sessionIds) =>
    (sessionIds.toList()..sort()).join('|');

Map<String, dynamic> _focusSessionToJson(FocusSession session) => {
  'id': session.id,
  'appointment_id': session.appointmentId,
  'task_id': session.taskId,
  'mode': session.mode.storageValue,
  'duration_seconds': session.durationSeconds,
  'started_at': _utcIso8601(session.startedAt),
  'ends_at': _utcIso8601(session.endsAt),
  'status': session.status.storageValue,
  'completed_at': session.completedAt == null
      ? null
      : _utcIso8601(session.completedAt!),
  'effective_seconds': session.effectiveSeconds,
  'completion_type': session.completionType.storageValue,
  'completion_rule_text': session.completionRuleText,
  'paused_at': session.pausedAt == null ? null : _utcIso8601(session.pausedAt!),
  'paused_seconds': session.pausedSeconds,
  'pause_rule_text': session.pauseRuleText,
  'failure_reason': session.failureReason,
  'effective_intervals': _intervalsToJson(session.effectiveIntervals),
  'review_disposition': session.reviewDisposition.storageValue,
  'review_disposition_updated_at': session.reviewDispositionUpdatedAt == null
      ? null
      : _utcIso8601(session.reviewDispositionUpdatedAt!),
  'configuration_basis_source_id': session.configurationBasisSourceId,
  'outcome_basis_source_id': session.outcomeBasisSourceId,
};

FocusSession _focusSessionFromJson(Map<String, dynamic> json) => FocusSession(
  id: json['id'] as String,
  appointmentId: json['appointment_id'] as String?,
  taskId: json['task_id'] as String,
  mode: FocusChainMode.fromStorage(json['mode'] as String),
  durationSeconds: json['duration_seconds'] as int,
  startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
  endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
  status: switch (json['status'] as String) {
    'active' => FocusSessionStatus.active,
    'paused' => FocusSessionStatus.paused,
    'failed' => FocusSessionStatus.failed,
    _ => FocusSessionStatus.completed,
  },
  completedAt: (json['completed_at'] as String?) == null
      ? null
      : DateTime.parse(json['completed_at'] as String).toUtc(),
  effectiveSeconds: json['effective_seconds'] as int,
  completionType: FocusSessionCompletionType.fromStorage(
    json['completion_type'] as String?,
  ),
  completionRuleText: json['completion_rule_text'] as String?,
  pausedAt: (json['paused_at'] as String?) == null
      ? null
      : DateTime.parse(json['paused_at'] as String).toUtc(),
  pausedSeconds: (json['paused_seconds'] as int?) ?? 0,
  pauseRuleText: json['pause_rule_text'] as String?,
  failureReason: json['failure_reason'] as String?,
  effectiveIntervals: _intervalsFromJsonValue(json['effective_intervals']),
  reviewDisposition: FocusRecordDisposition.fromStorage(
    json['review_disposition'] as String?,
  ),
  reviewDispositionUpdatedAt:
      (json['review_disposition_updated_at'] as String?) == null
      ? null
      : DateTime.parse(json['review_disposition_updated_at'] as String).toUtc(),
  configurationBasisSourceId: json['configuration_basis_source_id'] as String?,
  outcomeBasisSourceId: json['outcome_basis_source_id'] as String?,
);

Map<String, dynamic> _focusAppointmentToJson(
  AppointmentPreparation appointment,
) => {
  'id': appointment.id,
  'task_id': appointment.taskId,
  'mode': appointment.mode.storageValue,
  'duration_seconds': appointment.durationSeconds,
  'started_at': _utcIso8601(appointment.startedAt),
  'ends_at': _utcIso8601(appointment.endsAt),
  'status': appointment.status.storageValue,
  'settled_at': appointment.settledAt == null
      ? null
      : _utcIso8601(appointment.settledAt!),
  'session_id': appointment.sessionId,
  'failure_reason': appointment.failureReason,
  'updated_at': _utcIso8601(appointment.updatedAt),
  'review_disposition': appointment.reviewDisposition.storageValue,
  'review_disposition_updated_at':
      appointment.reviewDispositionUpdatedAt == null
      ? null
      : _utcIso8601(appointment.reviewDispositionUpdatedAt!),
  'configuration_basis_source_id': appointment.configurationBasisSourceId,
};

AppointmentPreparation _focusAppointmentFromJson(
  Map<String, dynamic> json,
) => AppointmentPreparation(
  id: json['id'] as String,
  taskId: json['task_id'] as String,
  mode: FocusChainMode.fromStorage(json['mode'] as String),
  durationSeconds: json['duration_seconds'] as int,
  startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
  endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
  status: AppointmentPreparationStatus.fromStorage(json['status'] as String),
  settledAt: (json['settled_at'] as String?) == null
      ? null
      : DateTime.parse(json['settled_at'] as String).toUtc(),
  updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
  sessionId: json['session_id'] as String?,
  failureReason: json['failure_reason'] as String?,
  reviewDisposition: FocusRecordDisposition.fromStorage(
    json['review_disposition'] as String?,
  ),
  reviewDispositionUpdatedAt:
      (json['review_disposition_updated_at'] as String?) == null
      ? null
      : DateTime.parse(json['review_disposition_updated_at'] as String).toUtc(),
  configurationBasisSourceId: json['configuration_basis_source_id'] as String?,
);

AppointmentPreparation _focusAppointmentWithRemoteReview(
  AppointmentPreparation appointment,
  AppointmentPreparation remoteRow,
) {
  final remoteAt = remoteRow.reviewDispositionUpdatedAt;
  final localAt = appointment.reviewDispositionUpdatedAt;
  if (remoteAt != null && (localAt == null || remoteAt.isAfter(localAt))) {
    return appointment.copyWithReviewDisposition(
      disposition: remoteRow.reviewDisposition,
      reviewedAt: remoteAt,
    );
  }
  return appointment;
}

Map<String, dynamic> _focusSourceRowToJson(
  FocusSyncSource source, {
  required String userId,
}) => {
  'source_id': source.sourceId,
  'user_id': userId,
  'device_id': source.deviceId,
  'entity_type': source.entityType,
  'entity_id': source.entityId,
  'parent_source_id': source.parentSourceId,
  'parent_source_ids': source.parentSourceIds,
  'occurred_at': _utcIso8601(source.occurredAt),
  'payload': jsonDecode(source.payload),
};

FocusSyncSource _focusSourceFromJson(Map<String, dynamic> json) =>
    FocusSyncSource(
      sourceId: json['source_id'] as String,
      deviceId: json['device_id'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      parentSourceId: json['parent_source_id'] as String?,
      parentSourceIds: _parentSourceIdsFromJson(
        json['parent_source_id'] as String?,
        json['parent_source_ids'],
      ),
      occurredAt: DateTime.parse(json['occurred_at'] as String).toUtc(),
      payload: jsonEncode(json['payload']),
    );

String _focusSourceSignature(FocusSyncSource source) {
  return _focusPayloadSignature(
    Map<String, dynamic>.from(jsonDecode(source.payload) as Map),
    includeReviewDisposition: source.entityType == 'focus_session',
  );
}

String _focusPayloadSignature(
  Map<String, dynamic> payload, {
  bool includeReviewDisposition = false,
}) {
  final state = Map<String, dynamic>.from(payload)
    ..removeWhere(
      (key, _) =>
          (!includeReviewDisposition && key == 'review_disposition') ||
          key == 'review_disposition_updated_at' ||
          key == 'updated_at',
    );
  return _canonicalJson(state);
}

List<String> _sourceParents(FocusSyncSource source) => {
  if (source.parentSourceId != null) source.parentSourceId!,
  ...source.parentSourceIds,
}.toList();

List<String> _decodeParentSourceIds(String? primaryId, String encodedIds) {
  final decoded = jsonDecode(encodedIds);
  final ids = decoded is List
      ? decoded.whereType<String>().toList()
      : <String>[];
  if (primaryId != null && !ids.contains(primaryId)) ids.insert(0, primaryId);
  return ids.toSet().toList();
}

List<String> _parentSourceIdsFromJson(String? primaryId, Object? values) {
  final ids = <String>[];
  if (values is List) {
    ids.addAll(values.whereType<String>());
  } else if (values is String) {
    try {
      final decoded = jsonDecode(values);
      if (decoded is List) ids.addAll(decoded.whereType<String>());
    } on FormatException {
      // Older remotes may not expose the new parent list as JSON.
    }
  }
  if (primaryId != null) ids.insert(0, primaryId);
  return ids.toSet().toList();
}

String _appointmentConfigurationSignature(AppointmentPreparation appointment) =>
    '${appointment.taskId}|${appointment.mode.storageValue}|${appointment.durationSeconds}';

Object? _canonicalizeJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalizeJson(value[key])};
  }
  if (value is List) return [for (final item in value) _canonicalizeJson(item)];
  return value;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalizeJson(value));

Map<String, List<FocusSyncSource>> _focusSourceHeadGroups(
  List<FocusSyncSource> sources, {
  required String entityType,
}) {
  final entitySources = sources
      .where((source) => source.entityType == entityType)
      .toList();
  final sourcesById = {
    for (final source in entitySources) source.sourceId: source,
  };
  final childrenBySourceId = <String, int>{};
  for (final source in entitySources) {
    for (final parentId in _sourceParents(source)) {
      if (!sourcesById.containsKey(parentId)) continue;
      childrenBySourceId.update(
        parentId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  final candidatesByEntity = <String, List<FocusSyncSource>>{};
  for (final source in entitySources) {
    if (!childrenBySourceId.containsKey(source.sourceId)) {
      candidatesByEntity.putIfAbsent(source.entityId, () => []).add(source);
    }
  }
  final leafSources = <String, List<FocusSyncSource>>{};
  for (final entry in candidatesByEntity.entries) {
    for (final source in entry.value) {
      final signature = _focusSourceSignature(source);
      var supersededByEquivalentAncestor = false;
      for (final descendant in entry.value) {
        if (descendant.sourceId == source.sourceId) continue;
        final pendingParentIds = _sourceParents(descendant);
        final visited = <String>{};
        while (pendingParentIds.isNotEmpty) {
          final parentId = pendingParentIds.removeLast();
          if (!visited.add(parentId)) continue;
          final parent = sourcesById[parentId];
          if (parent == null) continue;
          if (_focusSourceSignature(parent) == signature) {
            supersededByEquivalentAncestor = true;
            break;
          }
          pendingParentIds.addAll(_sourceParents(parent));
        }
        if (supersededByEquivalentAncestor) break;
      }
      if (!supersededByEquivalentAncestor) {
        leafSources.putIfAbsent(entry.key, () => []).add(source);
      }
    }
  }
  return leafSources;
}

Map<String, FocusSyncSource> _focusSourceHeads(
  List<FocusSyncSource> sources, {
  required String entityType,
}) {
  final headsByEntity = _focusSourceHeadGroups(sources, entityType: entityType);
  final selected = <String, FocusSyncSource>{};
  for (final entry in headsByEntity.entries) {
    final heads = entry.value;
    final settledHeads = heads.where((source) {
      final status =
          (jsonDecode(source.payload) as Map<String, dynamic>)['status'];
      return status == 'completed' ||
          status == 'succeeded' ||
          status == 'failed';
    }).toList();
    if (settledHeads.isNotEmpty) {
      settledHeads.sort(
        (left, right) => left.sourceId.compareTo(right.sourceId),
      );
      selected[entry.key] = settledHeads.first;
      continue;
    }
    heads.sort((left, right) {
      final byTime = left.occurredAt.compareTo(right.occurredAt);
      return byTime == 0 ? left.sourceId.compareTo(right.sourceId) : byTime;
    });
    selected[entry.key] = heads.last;
  }
  return selected;
}

Set<String> _conflictingFocusEntityIds(
  List<FocusSyncSource> sources, {
  required String entityType,
}) {
  final headsByEntity = _focusSourceHeadGroups(sources, entityType: entityType);
  return {
    for (final entry in headsByEntity.entries)
      if (entry.value.map(_focusSourceSignature).toSet().length > 1) entry.key,
  };
}

bool _sourceHeadDescendsFromLocal(
  Map<String, dynamic> localPayload, {
  required String entityType,
  required String entityId,
  required FocusSyncSource sourceHead,
  required List<FocusSyncSource> sources,
}) {
  final localSignatureWithDisposition = _focusPayloadSignature(
    localPayload,
    includeReviewDisposition: entityType == 'focus_session',
  );
  final localSourceIds = sources
      .where(
        (source) =>
            source.entityType == entityType &&
            source.entityId == entityId &&
            _focusSourceSignature(source) == localSignatureWithDisposition,
      )
      .map((source) => source.sourceId)
      .toSet();
  if (localSourceIds.contains(sourceHead.sourceId)) return true;

  final sourceById = {for (final source in sources) source.sourceId: source};
  final pendingParentIds = _sourceParents(sourceHead);
  final visited = <String>{};
  while (pendingParentIds.isNotEmpty) {
    final parentId = pendingParentIds.removeLast();
    if (!visited.add(parentId)) continue;
    if (localSourceIds.contains(parentId)) return true;
    final parent = sourceById[parentId];
    if (parent == null) continue;
    if (_focusSourceSignature(parent) == localSignatureWithDisposition) {
      return true;
    }
    pendingParentIds.addAll(_sourceParents(parent));
  }
  return false;
}

FocusSession _focusSessionWithRemoteReview(
  FocusSession session,
  FocusSession remoteRow,
) {
  final remoteAt = remoteRow.reviewDispositionUpdatedAt;
  final sessionAt = session.reviewDispositionUpdatedAt;
  if (remoteAt != null && (sessionAt == null || remoteAt.isAfter(sessionAt))) {
    return remoteRow;
  }
  return session;
}

class SupabaseFocusRemoteDataSource implements FocusRemoteDataSource {
  SupabaseFocusRemoteDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    final sessions = await client.from('focus_sessions').select();
    final appointments = await client.from('focus_appointments').select();
    final nodes = await client.from('focus_nodes').select();
    final records = await client.from('focus_chain_records').select();
    final appointmentRecords = await client
        .from('appointment_chain_records')
        .select();
    final precedentRules = await client.from('focus_precedent_rules').select();
    final sources = await client.from('focus_sync_sources').select();
    return FocusRemoteSnapshot(
      sessions: [for (final row in sessions) _focusSessionFromJson(row)],
      appointments: [
        for (final row in appointments) _focusAppointmentFromJson(row),
      ],
      nodes: [for (final row in nodes) _nodeFromJson(row)],
      records: [for (final row in records) _recordFromJson(row)],
      appointmentRecords: [
        for (final row in appointmentRecords) _appointmentRecordFromJson(row),
      ],
      precedentRules: [
        for (final row in precedentRules) _precedentRuleFromJson(row),
      ],
      sources: [for (final row in sources) _focusSourceFromJson(row)],
    );
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  }) async {
    await client.from('focus_sessions').upsert([
      for (final session in sessions)
        {'user_id': userId, ..._focusSessionToJson(session)},
    ], onConflict: 'id');
  }

  @override
  Future<void> upsertAppointments({
    required String userId,
    required List<AppointmentPreparation> appointments,
  }) async {
    await client.from('focus_appointments').upsert([
      for (final appointment in appointments)
        {'user_id': userId, ..._focusAppointmentToJson(appointment)},
    ], onConflict: 'id');
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  }) async {
    await client.from('focus_nodes').upsert([
      for (final node in nodes)
        {
          'id': node.id,
          'user_id': userId,
          'session_id': node.sessionId,
          'task_id': node.taskId,
          'mode': node.mode.storageValue,
          'created_at': _utcIso8601(node.createdAt),
          'effective_seconds': node.effectiveSeconds,
          'note': node.note,
        },
    ], onConflict: 'id');
  }

  @override
  Future<void> deleteNodes({
    required String userId,
    required List<String> sessionIds,
  }) async {
    if (sessionIds.isEmpty) return;
    await client
        .from('focus_nodes')
        .delete()
        .eq('user_id', userId)
        .inFilter('session_id', sessionIds);
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  }) async {
    await client.from('focus_chain_records').upsert([
      for (final record in records)
        {
          'user_id': userId,
          'mode': record.mode.storageValue,
          'current_consecutive': record.currentConsecutive,
          'best_consecutive': record.bestConsecutive,
          'updated_at': _utcIso8601(record.updatedAt),
        },
    ], onConflict: 'user_id,mode');
  }

  @override
  Future<void> upsertAppointmentRecords({
    required String userId,
    required List<AppointmentChainRecord> records,
  }) async {
    await client.from('appointment_chain_records').upsert([
      for (final record in records)
        {
          'user_id': userId,
          'current_consecutive': record.currentConsecutive,
          'best_consecutive': record.bestConsecutive,
          'updated_at': _utcIso8601(record.updatedAt),
        },
    ], onConflict: 'user_id');
  }

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  }) async {
    if (rules.isEmpty) return;
    await client.from('focus_precedent_rules').upsert([
      for (final rule in rules)
        {
          'id': rule.id,
          'user_id': userId,
          'rule_text': rule.text,
          'created_at': _utcIso8601(rule.createdAt),
          'updated_at': _utcIso8601(rule.updatedAt),
          'deleted_at': rule.deletedAt == null
              ? null
              : _utcIso8601(rule.deletedAt!),
        },
    ], onConflict: 'id');
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<FocusSyncSource> sources,
  }) async {
    if (sources.isEmpty) return;
    await client
        .from('focus_sync_sources')
        .upsert(
          [
            for (final source in sources)
              _focusSourceRowToJson(source, userId: userId),
          ],
          onConflict: 'source_id',
          ignoreDuplicates: true,
        );
  }

  FocusNode _nodeFromJson(Map<String, dynamic> json) => FocusNode(
    id: json['id'] as String,
    sessionId: json['session_id'] as String,
    taskId: json['task_id'] as String,
    mode: FocusChainMode.fromStorage(json['mode'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    effectiveSeconds: json['effective_seconds'] as int,
    note: json['note'] as String?,
  );

  FocusChainRecord _recordFromJson(Map<String, dynamic> json) =>
      FocusChainRecord(
        mode: FocusChainMode.fromStorage(json['mode'] as String),
        currentConsecutive: json['current_consecutive'] as int,
        bestConsecutive: json['best_consecutive'] as int,
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      );

  AppointmentChainRecord _appointmentRecordFromJson(
    Map<String, dynamic> json,
  ) => AppointmentChainRecord(
    currentConsecutive: json['current_consecutive'] as int,
    bestConsecutive: json['best_consecutive'] as int,
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
  );

  PrecedentRule _precedentRuleFromJson(Map<String, dynamic> json) =>
      PrecedentRule(
        id: json['id'] as String,
        text: json['rule_text'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
        deletedAt: (json['deleted_at'] as String?) == null
            ? null
            : DateTime.parse(json['deleted_at'] as String).toUtc(),
      );
}

String _utcIso8601(DateTime value) => value.toUtc().toIso8601String();

class InMemoryFocusRemote implements FocusRemoteDataSource {
  final _sessions = <String, Map<String, FocusSession>>{};
  final _appointments = <String, Map<String, AppointmentPreparation>>{};
  final _nodes = <String, Map<String, FocusNode>>{};
  final _records = <String, Map<String, FocusChainRecord>>{};
  final _appointmentRecords = <String, AppointmentChainRecord>{};
  final _precedentRules = <String, Map<String, PrecedentRule>>{};
  final _sources = <String, Map<String, FocusSyncSource>>{};

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    final appointmentRecord = _appointmentRecords[userId];
    return FocusRemoteSnapshot(
      sessions: (_sessions[userId] ?? {}).values.toList(),
      appointments: (_appointments[userId] ?? {}).values.toList(),
      nodes: (_nodes[userId] ?? {}).values.toList(),
      records: (_records[userId] ?? {}).values.toList(),
      appointmentRecords: appointmentRecord == null
          ? const []
          : [appointmentRecord],
      precedentRules: (_precedentRules[userId] ?? {}).values.toList(),
      sources: (_sources[userId] ?? {}).values.toList(),
    );
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  }) async {
    final target = _sessions.putIfAbsent(userId, () => {});
    for (final session in sessions) {
      target[session.id] = session;
    }
  }

  @override
  Future<void> upsertAppointments({
    required String userId,
    required List<AppointmentPreparation> appointments,
  }) async {
    final target = _appointments.putIfAbsent(userId, () => {});
    for (final appointment in appointments) {
      target[appointment.id] = appointment;
    }
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  }) async {
    final target = _nodes.putIfAbsent(userId, () => {});
    for (final node in nodes) {
      target[node.id] = node;
    }
  }

  @override
  Future<void> deleteNodes({
    required String userId,
    required List<String> sessionIds,
  }) async {
    final target = _nodes[userId];
    if (target == null || sessionIds.isEmpty) return;
    target.removeWhere((_, node) => sessionIds.contains(node.sessionId));
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  }) async {
    final target = _records.putIfAbsent(userId, () => {});
    for (final record in records) {
      target[record.mode.storageValue] = record;
    }
  }

  @override
  Future<void> upsertAppointmentRecords({
    required String userId,
    required List<AppointmentChainRecord> records,
  }) async {
    if (records.isNotEmpty) _appointmentRecords[userId] = records.last;
  }

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  }) async {
    final target = _precedentRules.putIfAbsent(userId, () => {});
    for (final rule in rules) {
      target[rule.id] = rule;
    }
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<FocusSyncSource> sources,
  }) async {
    final target = _sources.putIfAbsent(userId, () => {});
    for (final source in sources) {
      target.putIfAbsent(source.sourceId, () => source);
    }
  }
}

FocusDashboardMetrics _emptyDashboardMetrics(String deviceTimeZoneId) =>
    FocusDashboardMetrics(
      focusProgressSecondsByTask: const {},
      recentActivity: const [],
      totalAcceptedFocusSeconds: 0,
      displayTimeZoneId: deviceTimeZoneId,
      followsDeviceTimeZone: true,
    );

class UnavailableFocusRepository implements FocusRepository {
  const UnavailableFocusRepository();

  @override
  Stream<List<FocusSession>> watchSessions() => Stream.value(const []);

  @override
  Stream<List<FocusReconciliationCase>> watchFocusReconciliations() =>
      Stream.value(const []);

  @override
  Future<List<FocusReconciliationCase>> getFocusReconciliations() async =>
      const [];

  @override
  Future<void> resolveFocusReconciliation({
    required String caseId,
    required Map<String, FocusSessionReconciliationSelection> sessionSelections,
    String? adoptedSessionId,
  }) => _unavailable();

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String deviceTimeZoneId,
  }) => Stream.value(_emptyDashboardMetrics(deviceTimeZoneId));

  @override
  Future<FocusDashboardMetrics> getDashboardMetrics({
    required String deviceTimeZoneId,
  }) async => _emptyDashboardMetrics(deviceTimeZoneId);

  @override
  Future<void> setDisplayTimeZonePreference(String? timeZoneId) async {}

  @override
  Future<List<FocusSession>> getSessions() async => const [];

  @override
  Future<FocusSession?> getSession(String sessionId) async => null;

  @override
  Future<FocusSession?> getActiveSession() async => null;

  @override
  Future<List<AppointmentPreparation>> getAppointments() async => const [];

  @override
  Future<AppointmentPreparation?> getAppointment(String appointmentId) async =>
      null;

  @override
  Future<List<FocusAppointmentSourceOption>> getAppointmentConfigurationSources(
    String appointmentId,
  ) async => const [];

  @override
  Future<AppointmentPreparation> selectAppointmentConfigurationSource({
    required String appointmentId,
    required String sourceId,
  }) => _unavailable();

  @override
  Future<AppointmentPreparation?> getActiveAppointment() async => null;

  @override
  Future<AppointmentChainRecord> getAppointmentChainRecord() async =>
      AppointmentChainRecord(
        currentConsecutive: 0,
        bestConsecutive: 0,
        updatedAt: DateTime.now().toUtc(),
      );

  @override
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) => _unavailable();

  @override
  Future<AppointmentPreparation> startAppointment({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) => _unavailable();

  @override
  Future<AppointmentPreparation> updateAppointment({
    required String appointmentId,
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) => _unavailable();

  @override
  Future<FocusSession> enterAppointmentEarly(String appointmentId) =>
      _unavailable();

  @override
  Future<AppointmentPreparation> cancelAppointment({
    required String appointmentId,
    required String failureReason,
  }) => _unavailable();

  @override
  Future<void> settleDueAppointments() async {}

  @override
  Future<void> settleDueSessions() async {}

  @override
  Future<FocusSession> pauseSession(
    String sessionId, {
    required String ruleText,
  }) => _unavailable();

  @override
  Future<FocusSession> resumeSession(String sessionId) => _unavailable();

  @override
  Future<FocusSession> completeEarlySession({
    required String sessionId,
    required String ruleText,
  }) => _unavailable();

  @override
  Future<FocusSession> abandonSession({
    required String sessionId,
    required String failureReason,
  }) => _unavailable();

  @override
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  }) => _unavailable();

  @override
  Future<void> updateNodeNote({required String nodeId, required String note}) =>
      _unavailable();

  @override
  Future<List<FocusNode>> getNodes() async => const [];

  @override
  Future<List<FocusChainRecord>> getChainRecords() async => const [];

  @override
  Future<List<PrecedentRule>> getPrecedentRules() async => const [];

  @override
  Future<PrecedentRule> createPrecedentRule({required String text}) =>
      _unavailable();

  @override
  Future<PrecedentRule> updatePrecedentRule({
    required String ruleId,
    required String text,
  }) => _unavailable();

  @override
  Future<void> deletePrecedentRule(String ruleId) => _unavailable();

  @override
  Future<FocusChainMode> getLastMode() async => FocusChainMode.regular;

  @override
  Future<void> sync() async {}

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的专注存储尚未配置。');
  }
}
