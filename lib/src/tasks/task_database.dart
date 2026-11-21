import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../auth/user_lifecycle_models.dart';
import '../schedules/schedule_migration.dart';

part 'task_database.g.dart';

class LocalGoals extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get classification => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// 35：账号级置顶标记与手动排序位（仅业务快照携带，旧逐实体同步不写）。
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalTasks extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get classification => text()();
  IntColumn get estimatedMinutes => integer().nullable()();
  DateTimeColumn get deadline => dateTime().nullable()();
  BoolColumn get isComplete => boolean().withDefault(const Constant(false))();
  IntColumn get focusProgressSeconds =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalNationalFocusCards extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get triggerCondition => text()();
  TextColumn get action => text()();
  TextColumn get scope => text().nullable()();
  TextColumn get exceptionNotes => text().nullable()();
  BoolColumn get isInTree => boolean().withDefault(const Constant(false))();
  TextColumn get parentId => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('extinguished'))();
  IntColumn get successfulDays => integer().withDefault(const Constant(0))();
  IntColumn get currentConsecutiveDays =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestConsecutiveDays =>
      integer().withDefault(const Constant(0))();
  BoolColumn get maintenanceCycleStarted =>
      boolean().withDefault(const Constant(false))();
  TextColumn get failureReason => text().nullable()();
  TextColumn get cascadeSourceCardId => text().nullable()();
  TextColumn get cascadePriorState => text().nullable()();
  TextColumn get reviewDisposition =>
      text().withDefault(const Constant('accepted'))();
  IntColumn get activeStrengtheningLevel => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalNationalFocusStrengtheningLevels extends Table {
  TextColumn get userId => text()();
  TextColumn get cardId => text()();
  IntColumn get levelNumber => integer()();
  TextColumn get triggerConditionOverride => text().nullable()();
  TextColumn get actionOverride => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, cardId, levelNumber};
}

class LocalNationalFocusRequirementVersions extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get cardId => text()();
  IntColumn get versionNumber => integer()();
  IntColumn get strengtheningLevelNumber => integer().nullable()();
  TextColumn get effectiveTriggerCondition => text()();
  TextColumn get effectiveAction => text()();
  TextColumn get scope => text().nullable()();
  TextColumn get exceptionNotes => text().nullable()();
  DateTimeColumn get effectiveFrom => dateTime()();
  DateTimeColumn get effectiveUntil => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalNationalFocusMaintenance extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get lastSettledCheckpointAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class LocalNationalFocusFailures extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get batchId => text()();
  TextColumn get cardId => text()();
  DateTimeColumn get checkpointAt => dateTime()();
  TextColumn get cause => text()();
  TextColumn get failureReason => text().nullable()();
  TextColumn get sharedExplanation => text().nullable()();
  TextColumn get treeSnapshot => text()();
  TextColumn get reviewDisposition =>
      text().withDefault(const Constant('accepted'))();

  /// 回顾标记（ticket 11）。非空即已回顾；与 reviewDisposition 的
  /// 裁定语义分开存储，任何一侧变化都不改写另一侧。
  DateTimeColumn get reviewedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusSessions extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get appointmentId => text().nullable()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  IntColumn get durationSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get effectiveSeconds => integer().withDefault(const Constant(0))();
  TextColumn get completionType =>
      text().withDefault(const Constant('countdown'))();
  TextColumn get completionRuleText => text().nullable()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
  IntColumn get pausedSeconds => integer().withDefault(const Constant(0))();
  TextColumn get pauseRuleText => text().nullable()();
  TextColumn get failureReason => text().nullable()();
  TextColumn get effectiveIntervals =>
      text().withDefault(const Constant('[]'))();
  TextColumn get reviewDisposition =>
      text().withDefault(const Constant('accepted'))();
  DateTimeColumn get reviewDispositionUpdatedAt => dateTime().nullable()();
  TextColumn get configurationBasisSourceId => text().nullable()();
  TextColumn get outcomeBasisSourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusAppointments extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  IntColumn get durationSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get settledAt => dateTime().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get reviewDisposition =>
      text().withDefault(const Constant('accepted'))();
  DateTimeColumn get reviewDispositionUpdatedAt => dateTime().nullable()();
  TextColumn get configurationBasisSourceId => text().nullable()();

  /// 本场显式存储的预约准备时长（秒）。旧记录为 `null`，读取时沿用
  /// 已存的 start/end 边界，不重算也不延后正在进行的预约。
  IntColumn get preparationSeconds => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusSourceDevices extends Table {
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusSyncSources extends Table {
  TextColumn get userId => text()();
  TextColumn get sourceId => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get parentSourceId => text().nullable()();
  TextColumn get parentSourceIds => text().withDefault(const Constant('[]'))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, sourceId};
}

class AppointmentChainRecords extends Table {
  TextColumn get userId => text()();
  IntColumn get currentConsecutive =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestConsecutive => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusNodes extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get effectiveSeconds => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusChainRecords extends Table {
  TextColumn get userId => text()();
  TextColumn get mode => text()();
  IntColumn get currentConsecutive =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestConsecutive => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, mode};
}

class ChainSignals extends Table {
  TextColumn get userId => text()();
  TextColumn get appointmentTriggerSignal =>
      text().withDefault(const Constant(''))();
  TextColumn get eliteFocusMarker => text().withDefault(const Constant(''))();
  TextColumn get regularFocusMarker => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusPreferences extends Table {
  TextColumn get userId => text()();
  TextColumn get lastMode => text()();
  TextColumn get displayTimeZoneId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusPrecedentRules extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get ruleText => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class TaskSyncEntries extends Table {
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, entityType, entityId};
}

class LocalCalendarSources extends Table {
  TextColumn get userId => text()();
  TextColumn get sourceId => text()();
  TextColumn get displayName => text()();
  TextColumn get timeZoneId => text()();
  TextColumn get localCalendarId => text().nullable()();
  BoolColumn get isSelected => boolean().withDefault(const Constant(false))();
  BoolColumn get isStale => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, sourceId};
}

class LocalCalendarBlocks extends Table {
  TextColumn get userId => text()();
  TextColumn get sourceId => text()();
  TextColumn get sourceEventId => text()();
  TextColumn get occurrenceId => text()();
  TextColumn get eventIdentity => text()();
  TextColumn get title => text()();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get allDayStartDate => text().nullable()();
  TextColumn get allDayEndDateExclusive => text().nullable()();
  TextColumn get availability => text()();
  TextColumn get timeZoneId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, sourceId, occurrenceId};
}

/// Pacta 自有日程。与导入副本（local_calendar_blocks）分开：日程归应用拥有，
/// 系统日历来源只作为来源标记保留，用于后续导入去重。
class LocalSchedules extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get allDayStartDate => text().nullable()();
  TextColumn get allDayEndDateExclusive => text().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get taskId => text().nullable()();

  /// 可选提醒偏移（开始前多少分钟）；投递不在本表，未设置即不提醒。
  IntColumn get reminderMinutesBefore => integer().nullable()();
  TextColumn get origin => text().withDefault(const Constant('owned'))();
  TextColumn get sourceIds => text().withDefault(const Constant('[]'))();
  TextColumn get sourceNames => text().withDefault(const Constant('[]'))();
  TextColumn get sourceEventId => text().nullable()();
  TextColumn get occurrenceId => text().nullable()();
  TextColumn get eventIdentity => text().nullable()();

  /// 重复规则的当前归属；null 表示独立日程。
  TextColumn get recurrenceId => text().nullable()();

  /// 稳定系列身份：“本次及以后”截断后仍保留原值，实例身份不漂移。
  TextColumn get recurrenceSeriesId => text().nullable()();

  /// 该实例原始的本地开始日期（规则时区），展开与去重的稳定依据。
  TextColumn get recurrenceDate => text().nullable()();

  /// 生成该实例时使用的 IANA 时区，随实例保存以防后续重算漂移。
  TextColumn get recurrenceTimeZoneId => text().nullable()();

  /// 生成该实例时的本地开始分钟，配合时区与日期锁定原来的挂钟时刻。
  IntColumn get recurrenceStartMinutes => integer().nullable()();

  /// 已确认的“仅本次”改写：实例被单独改写过，规则不再覆盖它。
  BoolColumn get isRecurrenceException =>
      boolean().withDefault(const Constant(false))();

  /// 单实例删除的墓碑：行保留以免再次展开时复活，读取时过滤。
  BoolColumn get isRecurrenceCancelled =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

/// 重复日程规则（每天 / 每周指定星期 / 结束日期）。
///
/// 规则自带 IANA 时区与窗口模板：展开时按该时区的挂钟日历计算，不读取设备
/// 或当前显示时区，因此切换显示时区不会移动已生成的实例。模板属于规则的
/// 内部表示，用户界面只配置频率、星期与结束日期。
class LocalScheduleRecurrences extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get frequency => text()();
  TextColumn get weekdays => text().withDefault(const Constant('[]'))();
  TextColumn get firstDate => text()();
  TextColumn get endDate => text().nullable()();
  TextColumn get timeZoneId => text()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  IntColumn get startMinutesOfDay => integer().withDefault(const Constant(0))();
  IntColumn get durationMinutes => integer().withDefault(const Constant(60))();
  IntColumn get daySpan => integer().withDefault(const Constant(1))();

  /// 可见日期相对原始发生日期的日历位移（天）；0 表示未改期。
  ///
  /// 实例的 `recurrence_date` 是原始发生身份，"本次及以后"改期只改变这里的
  /// 位移，因此取消过的某一期不会因为挪动日期而复活或抵消别的实例。
  IntColumn get shiftDays => integer().withDefault(const Constant(0))();

  /// 规则自己的内容模板：之后按范围补齐的实例都从这里取内容，而不是从系列里
  /// 任意一条实例推断。"仅本次"例外不改写它。
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get taskId => text().nullable()();

  /// 规则模板自带的提醒偏移（分钟）。旧规则为 null，表示"不提醒"；
  /// 懒展开的新实例继承它，历史实例上的显式配置不被迁移改写。
  IntColumn get reminderMinutesBefore => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

/// 旧日历块一次性提升为自有日程的台账：是否已提升、提升数量与可回滚副本。
///
/// 不进入整份业务快照：这是本机的迁移证据，不是用户业务数据。
class LocalScheduleMigrations extends Table {
  TextColumn get userId => text()();
  TextColumn get migrationId => text()();
  TextColumn get status => text()();
  IntColumn get sourceBlockCount => integer()();
  IntColumn get promotedCount => integer()();
  TextColumn get promotedScheduleIds =>
      text().withDefault(const Constant('[]'))();
  TextColumn get backupPayload => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime()();
  DateTimeColumn get rolledBackAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class LocalUserLifecycleStates extends Table {
  TextColumn get userId => text()();
  BoolColumn get isSuspended => boolean().withDefault(const Constant(false))();
  DateTimeColumn get suspendedAt => dateTime().nullable()();
  DateTimeColumn get purgeEligibleAt => dateTime().nullable()();
  BoolColumn get isEligibleForPurge =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get checkedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// Cached account profile: display name and a bounded avatar binary.
///
/// Kept outside the business snapshot so restoring one never rolls the
/// account identity back, and so an offline device can still show it.
class LocalProfileAccounts extends Table {
  TextColumn get userId => text()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get avatarMimeType => text().nullable()();
  BlobColumn get avatarBytes => blob().nullable()();
  BoolColumn get pendingSave => boolean().withDefault(const Constant(false))();
  TextColumn get syncError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Increments on every payload change so a late network response can only
  /// commit when no newer local edit happened meanwhile.
  IntColumn get editSequence => integer().withDefault(const Constant(0))();

  /// The account display time zone (IANA identifier), shared by every device.
  ///
  /// Null means the account has not recorded one yet: display then uses a fixed
  /// fallback instead of the device zone. `focus_preferences.display_time_zone_id`
  /// is the superseded device-level field and is only read to seed this value.
  TextColumn get timeZoneId => text().nullable()();

  /// Server-owned revision of [timeZoneId] that this device last observed.
  ///
  /// Cached so an explicit edit can name the exact account value it is based
  /// on. It is not a local counter: only the account store advances it, which
  /// is what keeps two devices from ordering their edits by wall clocks.
  IntColumn get timeZoneRevision => integer().withDefault(const Constant(0))();

  /// Set only by an edit that changed the display time zone on this device and
  /// has not been accepted by the account store yet.
  ///
  /// A nickname or avatar upload must not re-send a cached time zone it did not
  /// choose: another device may already have a newer account value, and an
  /// account value always wins over a stale device copy. The flag survives a
  /// restart so an offline time-zone edit is still delivered exactly once.
  BoolColumn get pendingTimeZoneUpload =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// 账号清除代次：账号清除后仍保留的持久标记。
///
/// 资料行删除之后，一个开始于清除之前的读取或上传应答仍可能晚到。它必须
/// 在同一个事务里证明代次没有前进才允许写回，否则已清除账号的昵称与头像
/// 会被重新插入。代次只前进不删除：清除本身不会被后续写入“忘记”。
class LocalProfileClearMarks extends Table {
  TextColumn get userId => text()();
  IntColumn get generation => integer().withDefault(const Constant(0))();
  DateTimeColumn get clearedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// 恢复前保存的本机业务快照。刻意不属于可上传的业务表清单：恢复准备动作
/// 因此不会覆盖云端数据，且按用户隔离并参与账号清除。
class LocalCloudRecoveryPoints extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get reason => text()();
  TextColumn get sourceDeviceName => text().nullable()();
  DateTimeColumn get dataUpdatedAt => dateTime()();
  IntColumn get rowCount => integer()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    LocalGoals,
    LocalTasks,
    LocalNationalFocusCards,
    LocalNationalFocusStrengtheningLevels,
    LocalNationalFocusRequirementVersions,
    LocalNationalFocusMaintenance,
    LocalNationalFocusFailures,
    TaskSyncEntries,
    FocusSessions,
    FocusNodes,
    FocusChainRecords,
    FocusPreferences,
    ChainSignals,
    FocusPrecedentRules,
    FocusAppointments,
    AppointmentChainRecords,
    FocusSourceDevices,
    FocusSyncSources,
    LocalCalendarSources,
    LocalCalendarBlocks,
    LocalSchedules,
    LocalScheduleRecurrences,
    LocalScheduleMigrations,
    LocalUserLifecycleStates,
    LocalProfileAccounts,
    LocalProfileClearMarks,
    LocalCloudRecoveryPoints,
  ],
)
class PactaDatabase extends _$PactaDatabase {
  PactaDatabase(super.e);

  factory PactaDatabase.open() => PactaDatabase(driftDatabase(name: 'pacta'));

  Future<Set<String>> localUserIdsWithData() async {
    final rows = await customSelect('''
      SELECT user_id FROM local_calendar_blocks
      UNION SELECT user_id FROM local_calendar_sources
      UNION SELECT user_id FROM local_schedules
      UNION SELECT user_id FROM local_schedule_migrations
      UNION SELECT user_id FROM task_sync_entries
      UNION SELECT user_id FROM focus_sync_sources
      UNION SELECT user_id FROM focus_nodes
      UNION SELECT user_id FROM focus_sessions
      UNION SELECT user_id FROM focus_appointments
      UNION SELECT user_id FROM focus_chain_records
      UNION SELECT user_id FROM appointment_chain_records
      UNION SELECT user_id FROM focus_source_devices
      UNION SELECT user_id FROM chain_signals
      UNION SELECT user_id FROM focus_preferences
      UNION SELECT user_id FROM focus_precedent_rules
      UNION SELECT user_id FROM local_national_focus_failures
      UNION SELECT user_id FROM local_national_focus_requirement_versions
      UNION SELECT user_id FROM local_national_focus_strengthening_levels
      UNION SELECT user_id FROM local_national_focus_maintenance
      UNION SELECT user_id FROM local_national_focus_cards
      UNION SELECT user_id FROM local_tasks
      UNION SELECT user_id FROM local_goals
      UNION SELECT user_id FROM local_user_lifecycle_states
      UNION SELECT user_id FROM local_profile_accounts
      UNION SELECT user_id FROM local_cloud_recovery_points
    ''').get();
    return rows.map((row) => row.read<String>('user_id')).toSet();
  }

  Future<bool> purgeUserDataForReceipt({
    required String userId,
    required UserPurgeReceipt receipt,
  }) async {
    if (userId.isEmpty || !receipt.confirmsPurgedUser(userId)) return false;

    await transaction(() async {
      await (delete(
        localCalendarBlocks,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localCalendarSources,
      )..where((row) => row.userId.equals(userId))).go();
      // 日程与其迁移回滚副本同属该账号的业务数据，清除后不得残留。
      await (delete(
        localSchedules,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localScheduleMigrations,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        taskSyncEntries,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusSyncSources,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusNodes,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusSessions,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusAppointments,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusChainRecords,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        appointmentChainRecords,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusSourceDevices,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        chainSignals,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusPreferences,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        focusPrecedentRules,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localNationalFocusFailures,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localNationalFocusRequirementVersions,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localNationalFocusStrengtheningLevels,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localNationalFocusMaintenance,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localNationalFocusCards,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localTasks,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localGoals,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localCloudRecoveryPoints,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localUserLifecycleStates,
      )..where((row) => row.userId.equals(userId))).go();
      await (delete(
        localProfileAccounts,
      )..where((row) => row.userId.equals(userId))).go();
      // 与删除同一个事务：留下只前进的清除代次，让清除之前开始的在途读取
      // 或上传应答无法再写回这些资料。
      final previousMark = await (select(
        localProfileClearMarks,
      )..where((row) => row.userId.equals(userId))).getSingleOrNull();
      await into(localProfileClearMarks).insertOnConflictUpdate(
        LocalProfileClearMarksCompanion.insert(
          userId: userId,
          generation: Value((previousMark?.generation ?? 0) + 1),
          clearedAt: DateTime.now().toUtc(),
        ),
      );
    });

    return true;
  }

  /// Local schema 32.
  ///
  /// 31 merges the schedules table and the appointment-preparation column from
  /// the core integration branch, and 34 adds the failure-review state. 35 adds
  /// the account display time zone and the one-shot upload intent on top of
  /// them; it keeps the next free number rather than reusing 32, because the
  /// integration branch moved past that number while this ticket was isolated.
  /// Both time-zone columns are added
  /// defensively (see the migration below), because provisional 30 fixtures can
  /// already carry `time_zone_id` while a plain 30 database does not.
  ///
  /// 36 adds the cached server revision of that account value. It is a separate
  /// step because a development database already upgraded to this ticket's 35
  /// must still receive the new column. 35 is also claimed by the goal-pin
  /// ticket, so the final integrating schema has to reconcile both bodies above
  /// 36; this step stays structurally guarded instead of encoding a number.
  @override
  int get schemaVersion => 39;

  /// 仍然携带 `review_disposition` 的本地表。旧多端核对流程已废除，
  /// 这些列只保留给历史数据库的结构兼容，业务上一律按 `accepted` 读取。
  static const reviewDispositionTables = <String>[
    'focus_sessions',
    'focus_appointments',
    'local_national_focus_cards',
    'local_national_focus_failures',
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(localTasks, localTasks.focusProgressSeconds);
        await m.createTable(focusSessions);
        await m.createTable(focusNodes);
        await m.createTable(focusChainRecords);
        await m.createTable(focusPreferences);
      }
      if (from < 3) {
        await m.addColumn(focusSessions, focusSessions.pausedAt);
        await m.addColumn(focusSessions, focusSessions.pausedSeconds);
        await m.addColumn(focusSessions, focusSessions.failureReason);
        await m.addColumn(focusNodes, focusNodes.note);
      }
      if (from < 4) {
        await m.addColumn(focusSessions, focusSessions.pauseRuleText);
      }
      if (from < 5) {
        await m.addColumn(focusSessions, focusSessions.completionType);
        await m.addColumn(focusSessions, focusSessions.completionRuleText);
        await m.createTable(focusPrecedentRules);
      }
      if (from < 6) {
        await m.addColumn(focusSessions, focusSessions.appointmentId);
        await m.createTable(focusAppointments);
        await m.createTable(appointmentChainRecords);
      }
      if (from < 7) {
        await m.addColumn(focusSessions, focusSessions.effectiveIntervals);
        await m.addColumn(focusSessions, focusSessions.reviewDisposition);
        await m.addColumn(
          focusSessions,
          focusSessions.reviewDispositionUpdatedAt,
        );
        await m.addColumn(focusPreferences, focusPreferences.displayTimeZoneId);
      }
      if (from < 8) {
        await m.addColumn(localGoals, localGoals.deletedAt);
        await m.addColumn(localTasks, localTasks.deletedAt);
      }
      if (from < 9) {
        await m.createTable(focusSourceDevices);
        await m.createTable(focusSyncSources);
      }
      if (from < 10) {
        await m.addColumn(
          focusAppointments,
          focusAppointments.reviewDisposition,
        );
        await m.addColumn(
          focusAppointments,
          focusAppointments.reviewDispositionUpdatedAt,
        );
      }
      if (from < 11) {
        await m.addColumn(
          focusAppointments,
          focusAppointments.configurationBasisSourceId,
        );
      }
      if (from < 12) {
        await m.addColumn(
          focusSessions,
          focusSessions.configurationBasisSourceId,
        );
        await m.addColumn(focusSessions, focusSessions.outcomeBasisSourceId);
        await m.addColumn(focusSyncSources, focusSyncSources.parentSourceIds);
      }
      if (from < 13) {
        await m.createTable(localNationalFocusCards);
      }
      if (from < 14) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.successfulDays,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.currentConsecutiveDays,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.bestConsecutiveDays,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.maintenanceCycleStarted,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.failureReason,
        );
        await m.createTable(localNationalFocusMaintenance);
        await m.createTable(localNationalFocusFailures);
      }
      if (from < 15) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.cascadeSourceCardId,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.cascadePriorState,
        );
      }
      if (from < 16) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.deletedAt,
        );
      }
      if (from < 17) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.activeStrengtheningLevel,
        );
        await m.createTable(localNationalFocusStrengtheningLevels);
        await m.createTable(localNationalFocusRequirementVersions);
      }
      if (from >= 13 && from < 18) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.reviewDisposition,
        );
      }
      if (from >= 14 && from < 19) {
        await m.addColumn(
          localNationalFocusFailures,
          localNationalFocusFailures.reviewDisposition,
        );
      }
      if (from < 20) {
        await m.createTable(localCalendarSources);
        await m.createTable(localCalendarBlocks);
      }
      if (from >= 20 && from < 21) {
        await m.addColumn(localCalendarSources, localCalendarSources.isStale);
        await m.addColumn(localCalendarSources, localCalendarSources.isDeleted);
      }
      if (from < 22) {
        await m.createTable(localUserLifecycleStates);
      }
      if (from >= 13 && from < 23) {
        final legacyCards = await customSelect(
          'SELECT COUNT(*) AS card_count FROM local_national_focus_cards',
        ).getSingle();
        if (legacyCards.read<int>('card_count') != 0) {
          throw StateError('旧国策卡缺少必填名称，请重置开发数据库后升级。');
        }
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.name,
        );
      }
      if (from < 24) {
        await m.createTable(chainSignals);
      }
      if (from < 25) {
        await m.addColumn(localGoals, localGoals.description);
        await m.addColumn(localTasks, localTasks.description);
      }
      if (from < 26) {
        await m.createTable(localCloudRecoveryPoints);
      }
      if (from < 27) {
        await m.createTable(localProfileAccounts);
      }
      if (from >= 27 && from < 28) {
        await m.addColumn(
          localProfileAccounts,
          localProfileAccounts.editSequence,
        );
      }
      if (from < 29) {
        await m.createTable(localProfileClearMarks);
      }
      // 31：日程表与预约准备时长合并为同一次本地升级。
      //
      // 31 是核心合并的版本号（35 是本 profile 票据）。合并前两个票据各自
      // 独立发布过一个残缺的 30：03 只有 local_schedules，08 只有
      // preparation_seconds 列。这里按 SQLite 的实际结构只补缺少的那一半，
      // 不重建、不清空、不重算已存记录：
      //   * < 30 的老库：建表 + 补列 + 提升旧日历块。
      //   * 03 的 30：只补 preparation_seconds 列。
      //   * 08 的 30：只建表并提升旧日历块。
      // 用存在性检查而不是版本号区间，重复升级或回拨 user_version 都安全。
      if (from < 31) {
        await ensureMergedSchedulesSchema(this, m);
      }
      // 33：重复日程（05）。按实际结构补缺，不依赖版本号区间：并行票据的
      // 中间版本可能已带上部分重复结构，已存在的表/列永远不重建、不清空。
      //
      // 集成顺序：34 回顾（11）→ 35/36 账号时区（02）→ 37 规则模板/改期位移
      // （05 r3）→ 38 为本次合并的完整对账版本（纯版本推进，无新增结构）。
      // 从任何更旧的版本升级都要走一遍重复结构补齐。
      if (from < 38) {
        await ensureRecurrenceSchema(this, m);
      }
      if (from < 35) {
        // Account-level display time zone and the one-shot upload intent.
        // Existing rows keep the zone null, which the profile repository seeds
        // once from the superseded device value. Structural probes keep this
        // migration safe for provisional schema-30 databases (zone column
        // present), for partially restored databases that never had the profile
        // table, and for fixtures written before either column existed.
        final profileTable = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'local_profile_accounts'",
        ).get();
        if (profileTable.isEmpty) {
          await m.createTable(localProfileAccounts);
        } else {
          final columns = await customSelect(
            'PRAGMA table_info(local_profile_accounts)',
          ).get();
          final names = columns.map((row) => row.read<String>('name')).toSet();
          if (!names.contains('time_zone_id')) {
            await m.addColumn(
              localProfileAccounts,
              localProfileAccounts.timeZoneId,
            );
          }
          if (!names.contains('pending_time_zone_upload')) {
            await m.addColumn(
              localProfileAccounts,
              localProfileAccounts.pendingTimeZoneUpload,
            );
          }
        }
      }
      // 36: the cached account revision the local value is based on. Guarded by
      // the actual column list, so databases created by 35, by a provisional
      // schema-30 fixture, or by the guarded 35 block above all upgrade once.
      if (from < 36) {
        final revisionColumns = await customSelect(
          'PRAGMA table_info(local_profile_accounts)',
        ).get();
        final revisionNames = revisionColumns
            .map((row) => row.read<String>('name'))
            .toSet();
        if (revisionNames.isNotEmpty &&
            !revisionNames.contains('time_zone_revision')) {
          await m.addColumn(
            localProfileAccounts,
            localProfileAccounts.timeZoneRevision,
          );
        }
      }
      // 34：失败记录的回顾状态（ticket 11）。旧记录没有回顾概念，补列后
      // 保持 null（未回顾），由看板提示用户逐组回顾；不改写失败结果、
      // 结算统计与冻结要求。
      //
      // 迁移守卫：只在旧库确实已有失败表且缺这一列时补列。合成/局部旧库
      // 可能没有失败表（由后续 createTable 或历史版本负责），重复升级或
      // 回拨 user_version 的库也不会重复加列。
      if (from >= 14 && from < 34) {
        final failureColumns = await customSelect(
          'PRAGMA table_info(local_national_focus_failures)',
        ).get();
        final hasReviewedAt = failureColumns.any(
          (row) => row.read<String>('name') == 'reviewed_at',
        );
        if (failureColumns.isNotEmpty && !hasReviewedAt) {
          await m.addColumn(
            localNationalFocusFailures,
            localNationalFocusFailures.reviewedAt,
          );
        }
      }
      // 35：目标置顶与手动排序位。
      //
      // 32–36 由并行票据预留（账号时区、重复日程、失败回顾），本票不假定
      // 中间版本包含它们；这里用列存在性检查只补本票列，已存目标保持
      // "未置顶 + 无排序位"，顺序沿用既有规则。守卫写成 < 37，使已经升到
      // 02 的 36 的库也能拿到置顶列；37 是本分支对 35+36 的合并版本号。
      if (from < 37) {
        await ensureGoalPinSchema(this, m);
      }
      // 39：最终完整并集。按结构（而不是版本号区间）补齐所有并行票据的
      // 表/列：核心日程与准备时长、重复规则与模板（含提醒偏移）、目标置顶、
      // 失败回顾、账号显示时区与 revision。任何更旧的库（29/30/31/33/34/
      // 35/36/37/38）都会走一遍；已存在的结构一律不动、已存值不清空。
      if (from < 39) {
        await ensureMergedSchedulesSchema(this, m);
        await ensureRecurrenceSchema(this, m);
        await ensureGoalPinSchema(this, m);
        await ensureFailureReviewSchema(this, m);
        await ensureProfileZoneSchema(this, m);
      }
      if (from < 15) {
        await _cascadeLegacyActiveDescendants(this);
      }
    },
    // 每次打开既有库都把测试期残留的旧核对状态直接掰正：待核对 / 重复
    // 记录一律变成正常记录。不新增 DB migration，也不改 schemaVersion。
    beforeOpen: (details) async {
      if (details.wasCreated) return;
      final existing = await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ).get();
      final tableNames = {for (final row in existing) row.read<String>('name')};
      for (final table in reviewDispositionTables) {
        if (!tableNames.contains(table)) continue;
        final columns = await customSelect('PRAGMA table_info("$table")').get();
        if (!columns.any(
          (column) => column.read<String>('name') == 'review_disposition',
        )) {
          continue;
        }
        await customStatement(
          'UPDATE "$table" SET review_disposition = ? '
          'WHERE review_disposition IS NOT NULL AND review_disposition != ?',
          ['accepted', 'accepted'],
        );
      }
    },
  );
}

/// v31 结构：自有日程表与预约准备时长必须同时存在。
///
/// 合并前两个票据各自发布过一个残缺的 schema 30，因此这里按实际结构补缺，
/// 不依赖版本号区间：已存在的表/列永远不重建，已存数据永远不清空。
Future<void> ensureMergedSchedulesSchema(
  PactaDatabase database,
  Migrator migrator,
) async {
  final tableNames = await _sqliteTableNames(database);
  final needsSchedules = !tableNames.contains('local_schedules');
  if (needsSchedules) {
    await migrator.createTable(database.localSchedules);
  }
  if (!tableNames.contains('local_schedule_migrations')) {
    await migrator.createTable(database.localScheduleMigrations);
  }
  await _addPreparationSecondsIfMissing(database, migrator);
  if (needsSchedules) {
    // 旧日历块一次性提升为自有日程副本；失败则整个升级事务回滚，
    // 不会留下半份日程或半份回滚副本。
    await promoteLegacyCalendarBlocksInTransaction(
      database,
      migratedAt: DateTime.now().toUtc(),
    );
  }
}

/// 重复结构：规则表（含 r3 的规则内容模板与改期位移）+ 实例上的重复列。
///
/// 存在性检查而不是版本号区间：中间版本可能已带部分结构，重复升级或回拨
/// user_version 都安全，已存日程、规则与实例一律保留。
Future<void> ensureRecurrenceSchema(
  PactaDatabase database,
  Migrator migrator,
) async {
  final tableNames = await _sqliteTableNames(database);
  if (!tableNames.contains('local_schedule_recurrences')) {
    await migrator.createTable(database.localScheduleRecurrences);
  } else {
    final ruleColumns = await database
        .customSelect('PRAGMA table_info(local_schedule_recurrences)')
        .get();
    final existingRules = {
      for (final row in ruleColumns) row.read<String>('name'),
    };
    Future<void> addRuleColumn(
      String name,
      GeneratedColumn<Object> column,
    ) async {
      if (existingRules.contains(name)) return;
      await migrator.addColumn(database.localScheduleRecurrences, column);
    }

    await addRuleColumn(
      'shift_days',
      database.localScheduleRecurrences.shiftDays,
    );
    await addRuleColumn('title', database.localScheduleRecurrences.title);
    await addRuleColumn('notes', database.localScheduleRecurrences.notes);
    await addRuleColumn('task_id', database.localScheduleRecurrences.taskId);
    await addRuleColumn(
      'reminder_minutes_before',
      database.localScheduleRecurrences.reminderMinutesBefore,
    );
  }
  if (!tableNames.contains('local_schedules')) return;
  final columns = await database
      .customSelect('PRAGMA table_info(local_schedules)')
      .get();
  final existing = {for (final row in columns) row.read<String>('name')};
  Future<void> addColumn(String name, GeneratedColumn<Object> column) async {
    if (existing.contains(name)) return;
    await migrator.addColumn(database.localSchedules, column);
  }

  await addColumn('recurrence_id', database.localSchedules.recurrenceId);
  await addColumn(
    'recurrence_series_id',
    database.localSchedules.recurrenceSeriesId,
  );
  await addColumn('recurrence_date', database.localSchedules.recurrenceDate);
  await addColumn(
    'recurrence_time_zone_id',
    database.localSchedules.recurrenceTimeZoneId,
  );
  await addColumn(
    'recurrence_start_minutes',
    database.localSchedules.recurrenceStartMinutes,
  );
  await addColumn(
    'is_recurrence_exception',
    database.localSchedules.isRecurrenceException,
  );
  await addColumn(
    'is_recurrence_cancelled',
    database.localSchedules.isRecurrenceCancelled,
  );
  // 升级到 r3 之前的规则没有自己的内容模板：用该规则最早的一条非例外实例
  // 回填，避免升级后按范围补齐出空标题实例。
  await _backfillRuleTemplates(database);
}

Future<void> _backfillRuleTemplates(PactaDatabase database) async {
  // 候选实例必须是这一条规则里仍然可见的那一期："仅本次"例外有自己的改写内容，
  // 单期删除的墓碑只剩占位行，两者都不能变成整条规则的默认内容，否则升级后新生
  // 成的实例会带上一期的改写或已删除标题。最早的非例外实例是规则内容的唯一来
  // 源；只有整条规则只剩例外时，才退回到任意一期，并且优先取未取消的那一期。
  await database.customStatement('''
    UPDATE local_schedule_recurrences
    SET title = coalesce(
          nullif(title, ''),
          (
            SELECT instance.title FROM local_schedules AS instance
            WHERE instance.user_id = local_schedule_recurrences.user_id
              AND instance.recurrence_id = local_schedule_recurrences.id
              AND instance.is_recurrence_exception = 0
              AND instance.is_recurrence_cancelled = 0
            ORDER BY instance.starts_at, instance.id
            LIMIT 1
          ),
          (
            SELECT instance.title FROM local_schedules AS instance
            WHERE instance.user_id = local_schedule_recurrences.user_id
              AND instance.recurrence_id = local_schedule_recurrences.id
            ORDER BY instance.is_recurrence_cancelled, instance.starts_at, instance.id
            LIMIT 1
          ),
          title
        ),
        notes = coalesce(
          nullif(notes, ''),
          (
            SELECT instance.notes FROM local_schedules AS instance
            WHERE instance.user_id = local_schedule_recurrences.user_id
              AND instance.recurrence_id = local_schedule_recurrences.id
              AND instance.is_recurrence_exception = 0
              AND instance.is_recurrence_cancelled = 0
            ORDER BY instance.starts_at, instance.id
            LIMIT 1
          ),
          notes
        ),
        task_id = coalesce(
          nullif(task_id, ''),
          (
            SELECT instance.task_id FROM local_schedules AS instance
            WHERE instance.user_id = local_schedule_recurrences.user_id
              AND instance.recurrence_id = local_schedule_recurrences.id
              AND instance.is_recurrence_exception = 0
              AND instance.is_recurrence_cancelled = 0
            ORDER BY instance.starts_at, instance.id
            LIMIT 1
          ),
          task_id
        )
    WHERE title = ''
    ''');
}

/// v35 结构：目标表补置顶标记与手动排序位。
///
/// 只在列缺失时补列，重复升级或回拨 user_version 都安全；不重建目标表，
/// 也不改写已存标题、描述、分类或删除标记。
Future<void> ensureGoalPinSchema(
  PactaDatabase database,
  Migrator migrator,
) async {
  final columns = await database
      .customSelect('PRAGMA table_info(local_goals)')
      .get();
  if (columns.isEmpty) return;
  final names = {for (final row in columns) row.read<String>('name')};
  if (!names.contains('is_pinned')) {
    await migrator.addColumn(database.localGoals, database.localGoals.isPinned);
  }
  if (!names.contains('sort_order')) {
    await migrator.addColumn(
      database.localGoals,
      database.localGoals.sortOrder,
    );
  }
}

/// 11 的回顾标记：只在缺列时补，已存 reviewed_at（含非空值）原样保留。
Future<void> ensureFailureReviewSchema(
  PactaDatabase database,
  Migrator migrator,
) async {
  final columns = await database
      .customSelect('PRAGMA table_info(local_national_focus_failures)')
      .get();
  if (columns.isEmpty) return;
  final names = {for (final row in columns) row.read<String>('name')};
  if (names.contains('reviewed_at')) return;
  await migrator.addColumn(
    database.localNationalFocusFailures,
    database.localNationalFocusFailures.reviewedAt,
  );
}

/// 02 的账号显示时区三列：缺表则建空表，缺列才补；不重置已选时区、
/// 待上传意图或缓存的 revision。
Future<void> ensureProfileZoneSchema(
  PactaDatabase database,
  Migrator migrator,
) async {
  final table = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'local_profile_accounts'",
      )
      .get();
  if (table.isEmpty) {
    await migrator.createTable(database.localProfileAccounts);
    return;
  }
  final columns = await database
      .customSelect('PRAGMA table_info(local_profile_accounts)')
      .get();
  final names = {for (final row in columns) row.read<String>('name')};
  if (!names.contains('time_zone_id')) {
    await migrator.addColumn(
      database.localProfileAccounts,
      database.localProfileAccounts.timeZoneId,
    );
  }
  if (!names.contains('pending_time_zone_upload')) {
    await migrator.addColumn(
      database.localProfileAccounts,
      database.localProfileAccounts.pendingTimeZoneUpload,
    );
  }
  if (!names.contains('time_zone_revision')) {
    await migrator.addColumn(
      database.localProfileAccounts,
      database.localProfileAccounts.timeZoneRevision,
    );
  }
}

Future<Set<String>> _sqliteTableNames(PactaDatabase database) async {
  final rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

/// 只在 focus_appointments 已存在且缺 preparation_seconds 时补列。
///
/// 版本 6 之前由 createTable 直接建成当前形状；重复升级旧副本或回拨
/// user_version 的库不会重复加列，也不会改写已存记录。
Future<void> _addPreparationSecondsIfMissing(
  PactaDatabase database,
  Migrator migrator,
) async {
  final columns = await database
      .customSelect('PRAGMA table_info(focus_appointments)')
      .get();
  if (columns.isEmpty) return;
  final hasPreparationSeconds = columns.any(
    (row) => row.read<String>('name') == 'preparation_seconds',
  );
  if (hasPreparationSeconds) return;
  await migrator.addColumn(
    database.focusAppointments,
    database.focusAppointments.preparationSeconds,
  );
}

Future<void> _cascadeLegacyActiveDescendants(PactaDatabase database) async {
  final cards = await (database.select(
    database.localNationalFocusCards,
  )..where((card) => card.isInTree.equals(true))).get();
  final failures = await database
      .select(database.localNationalFocusFailures)
      .get();
  final latestFailureByCard = <String, Map<String, DateTime>>{};
  for (final failure in failures) {
    final userFailures = latestFailureByCard.putIfAbsent(
      failure.userId,
      () => {},
    );
    final previous = userFailures[failure.cardId];
    if (previous == null || failure.checkpointAt.isAfter(previous)) {
      userFailures[failure.cardId] = failure.checkpointAt;
    }
  }
  final cardsByUser = <String, Map<String, LocalNationalFocusCard>>{};
  for (final card in cards) {
    cardsByUser.putIfAbsent(card.userId, () => {})[card.id] = card;
  }

  for (final card in cards) {
    if (card.state != 'lit' && card.state != 'pending_today_confirmation') {
      continue;
    }

    final userCards = cardsByUser[card.userId]!;
    final visited = <String>{card.id};
    var ancestorId = card.parentId;
    String? sourceCardId;
    LocalNationalFocusCard? sourceCard;
    while (ancestorId != null && visited.add(ancestorId)) {
      final ancestor = userCards[ancestorId];
      if (ancestor == null) break;
      if (ancestor.state == 'extinguished') {
        sourceCardId = ancestor.id;
        sourceCard = ancestor;
        break;
      }
      ancestorId = ancestor.parentId;
    }
    if (sourceCardId == null) continue;

    final sourceFailureAt = latestFailureByCard[card.userId]?[sourceCardId];
    final sourceFailureWasSettled =
        sourceFailureAt != null && !sourceCard!.maintenanceCycleStarted;

    await (database.update(database.localNationalFocusCards)
          ..where((candidate) => candidate.userId.equals(card.userId))
          ..where((candidate) => candidate.id.equals(card.id)))
        .write(
          LocalNationalFocusCardsCompanion(
            state: const Value('extinguished'),
            currentConsecutiveDays: Value(
              sourceFailureWasSettled ? 0 : card.currentConsecutiveDays,
            ),
            maintenanceCycleStarted: Value(
              sourceFailureWasSettled ? false : card.maintenanceCycleStarted,
            ),
            failureReason: const Value(null),
            cascadeSourceCardId: Value(sourceCardId),
            cascadePriorState: Value(
              sourceFailureWasSettled ? 'lit' : card.state,
            ),
          ),
        );
  }
}
