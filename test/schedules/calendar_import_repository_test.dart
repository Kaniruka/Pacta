import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalScheduleRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  CalendarEventOccurrence timed({
    String sourceId = 'source-a',
    String sourceEventId = 'evt-1@example.com',
    String? occurrenceId,
    String? deviceOccurrenceId,
    bool isRecurring = false,
    String title = '周会',
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    final start = startsAt ?? DateTime.utc(2026, 11, 16, 9);
    return CalendarEventOccurrence(
      sourceId: sourceId,
      sourceEventId: sourceEventId,
      occurrenceId:
          occurrenceId ?? '$sourceEventId@${start.millisecondsSinceEpoch}',
      eventIdentity:
          occurrenceId ?? '$sourceEventId@${start.millisecondsSinceEpoch}',
      title: title,
      startsAt: start,
      endsAt: endsAt ?? start.add(const Duration(hours: 1)),
      allDay: false,
      availability: CalendarAvailability.busy,
      timeZoneId: 'Asia/Shanghai',
      deviceOccurrenceId: deviceOccurrenceId,
      isRecurring: isRecurring,
    );
  }

  Future<void> seedInstallation(String installId) => database
      .into(database.focusSourceDevices)
      .insert(
        FocusSourceDevicesCompanion.insert(
          userId: 'user-a',
          deviceId: installId,
        ),
      );

  Future<void> seedImportedCopy({
    required String scheduleId,
    required String identity,
  }) => database
      .into(database.localSchedules)
      .insert(
        LocalSchedulesCompanion.insert(
          userId: 'user-a',
          id: scheduleId,
          title: '旧安装身份日程',
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
          createdAt: DateTime.utc(2026, 11, 1),
          updatedAt: DateTime.utc(2026, 11, 1),
          origin: Value(ScheduleOrigin.calendarImport.storageValue),
          eventIdentity: Value(identity),
          sourceEventId: const Value('local:42'),
          occurrenceId: const Value('local:42@1'),
        ),
      );

  List<String> aliasEncodings(
    String? identity, {
    String install = 'install-test',
  }) => [
    for (final alias in decodeCalendarImportIdentityAliases(
      identity,
      deviceProvenance: install,
    ))
      alias.encode(),
  ];

  CalendarImportRequest request(List<CalendarEventOccurrence> occurrences) =>
      CalendarImportRequest(
        sources: const [
          CalendarImportSource(
            id: 'source-a',
            displayName: '工作',
            localCalendarId: '7',
          ),
        ],
        occurrences: occurrences,
        from: DateTime.utc(2026, 11, 16),
        to: DateTime.utc(2026, 11, 23),
      );

  test('preview counts copies to import and writes nothing', () async {
    final preview = await repository.previewCalendarImport(
      request([timed(), timed(sourceEventId: 'evt-2@example.com')]),
    );

    expect(preview.pending, hasLength(2));
    expect(preview.duplicateCount, 0);
    expect(preview.totalCount, 2);
    final pendingAliases = decodeCalendarImportIdentityAliases(
      preview.pending.first.identityKey,
    );
    expect(pendingAliases.single.kind, calendarImportAliasSync);
    expect(pendingAliases.single.sourceEventId, 'evt-1@example.com');
    expect(pendingAliases.single.occurrenceId, isNull);
    expect(await repository.getSchedules(), isEmpty);
  });

  test(
    'confirm creates owned copies and skips them on a repeat import',
    () async {
      final first = await repository.previewCalendarImport(
        request([timed(), timed(sourceEventId: 'evt-2@example.com')]),
      );
      final outcome = await repository.confirmCalendarImport(first);

      expect(outcome.createdCount, 2);
      expect(outcome.skippedDuplicates, 0);
      final copies = await repository.getSchedules();
      expect(copies, hasLength(2));
      final copy = copies.firstWhere(
        (item) => item.sourceEventId == 'evt-1@example.com',
      );
      expect(copy.origin, ScheduleOrigin.calendarImport);
      expect(copy.sourceIds, ['source-a']);
      expect(copy.sourceNames, ['工作']);
      expect(copy.sourceEventId, 'evt-1@example.com');
      final storedAliases = decodeCalendarImportIdentityAliases(
        copy.eventIdentity,
      );
      expect(storedAliases.single.kind, calendarImportAliasSync);
      expect(storedAliases.single.occurrenceId, isNull);
      expect(copy.isCompleted, isFalse);

      final again = await repository.previewCalendarImport(
        request([timed(), timed(sourceEventId: 'evt-2@example.com')]),
      );
      expect(again.pending, isEmpty);
      expect(again.duplicateCount, 2);
      final second = await repository.confirmCalendarImport(again);
      expect(second.createdCount, 0);
      expect(second.skippedDuplicates, 0);
      expect(await repository.getSchedules(), hasLength(2));
    },
  );

  test('a user-edited copy is neither overwritten nor duplicated', () async {
    final preview = await repository.previewCalendarImport(request([timed()]));
    final created = (await repository.confirmCalendarImport(preview))
        .created
        .single;
    final edited = await repository.updateSchedule(
      created.id,
      ScheduleDraft(
        title: '改到下午的周会',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 15),
          endsAt: DateTime.utc(2026, 11, 16, 16),
        ),
      ),
    );
    expect(edited.eventIdentity, created.eventIdentity);

    final again = await repository.previewCalendarImport(request([timed()]));
    expect(again.pending, isEmpty);
    expect(again.duplicateCount, 1);
    await repository.confirmCalendarImport(again);

    final stored = (await repository.getSchedules()).single;
    expect(stored.title, '改到下午的周会');
    expect(stored.startsAt, DateTime.utc(2026, 11, 16, 15));
    expect(stored.eventIdentity, created.eventIdentity);
  });

  test('raw source ids from different calendars never collapse', () async {
    final twoSources = CalendarImportRequest(
      sources: const [
        CalendarImportSource(
          id: 'source-a',
          displayName: '工作',
          localCalendarId: '7',
        ),
        CalendarImportSource(
          id: 'source-b',
          displayName: '个人',
          localCalendarId: '8',
        ),
      ],
      occurrences: [
        timed(),
        timed(sourceId: 'source-b'),
      ],
      from: DateTime.utc(2026, 11, 16),
      to: DateTime.utc(2026, 11, 23),
    );
    final preview = await repository.previewCalendarImport(twoSources);
    expect(preview.pending, hasLength(2));
    expect(preview.duplicateCount, 0);
    final outcome = await repository.confirmCalendarImport(preview);
    expect(outcome.createdCount, 2);
    expect(
      (await repository.getSchedules())
          .map((item) => item.sourceIds.single)
          .toSet(),
      {'source-a', 'source-b'},
    );
  });

  test(
    'device-local fallback ids are scoped by installation and calendar',
    () async {
      await seedInstallation('install-test');
      final localA = timed(
        sourceId: 'source-a',
        sourceEventId: 'local:42',
        occurrenceId: 'local:42@1',
        title: '本机私事',
      );
      final localB = timed(
        sourceId: 'source-b',
        sourceEventId: 'local:42',
        occurrenceId: 'local:42@1',
        title: '本机私事',
      );
      final twoDevices = CalendarImportRequest(
        sources: const [
          CalendarImportSource(
            id: 'source-a',
            displayName: '本机 7',
            localCalendarId: '7',
          ),
          CalendarImportSource(
            id: 'source-b',
            displayName: '本机 8',
            localCalendarId: '8',
          ),
        ],
        occurrences: [localA, localB],
        from: DateTime.utc(2026, 11, 16),
        to: DateTime.utc(2026, 11, 23),
      );

      final preview = await repository.previewCalendarImport(twoDevices);
      expect(preview.pending, hasLength(2));
      expect(
        preview.pending.map((item) => item.identityKey).toSet(),
        hasLength(2),
      );
      final firstAlias = decodeCalendarImportIdentityAliases(
        preview.pending.first.identityKey,
      ).single;
      final lastAlias = decodeCalendarImportIdentityAliases(
        preview.pending.last.identityKey,
      ).single;
      expect(firstAlias.kind, calendarImportAliasDevice);
      expect(firstAlias.installId, 'install-test');
      expect(firstAlias.calendarId, '7');
      expect(firstAlias.deviceRowId, 'local:42');
      expect(lastAlias.calendarId, '8');
    },
  );

  test('recurring occurrences of one series stay independent', () async {
    await seedInstallation('install-test');
    final series = [
      timed(
        sourceEventId: 'evt-9@example.com',
        occurrenceId: 'evt-9@example.com@1',
        deviceOccurrenceId: 'local:9@1',
        isRecurring: true,
        startsAt: DateTime.utc(2026, 11, 16, 9),
      ),
      timed(
        sourceEventId: 'evt-9@example.com',
        occurrenceId: 'evt-9@example.com@2',
        deviceOccurrenceId: 'local:9@2',
        isRecurring: true,
        startsAt: DateTime.utc(2026, 11, 17, 9),
      ),
    ];
    final preview = await repository.previewCalendarImport(request(series));
    expect(preview.pending, hasLength(2));
    expect(preview.duplicateCount, 0);

    final outcome = await repository.confirmCalendarImport(preview);
    expect(outcome.createdCount, 2);
    final repeated = await repository.previewCalendarImport(request(series));
    expect(repeated.pending, isEmpty);
    expect(repeated.duplicateCount, 2);
  });

  test('out-of-range and untitled occurrences never become copies', () async {
    final outside = timed(startsAt: DateTime.utc(2026, 12, 1, 9));
    final untitled = timed(sourceEventId: 'evt-3@example.com', title: '  ');
    final preview = await repository.previewCalendarImport(
      request([outside, untitled]),
    );
    expect(preview.pending, isEmpty);
    expect(preview.ignoredCount, 1);
    expect(preview.totalCount, 1);
  });

  test(
    'legacy promoted copies still match on the same source origin',
    () async {
      await database
          .into(database.localCalendarSources)
          .insert(
            LocalCalendarSourcesCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              displayName: '工作',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );
      const rawIdentity = 'evt-1@example.com@1763283600000';
      await database
          .into(database.localCalendarBlocks)
          .insert(
            LocalCalendarBlocksCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              sourceEventId: 'evt-1@example.com',
              occurrenceId: rawIdentity,
              eventIdentity: rawIdentity,
              title: '周会',
              startsAt: DateTime.utc(2026, 11, 16, 9),
              endsAt: DateTime.utc(2026, 11, 16, 10),
              availability: 'busy',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );
      await repository.promoteLegacyCalendarBlocks();
      final promoted = (await repository.getSchedules()).single;
      expect(promoted.origin, ScheduleOrigin.legacyCalendarBlock);

      final sameOrigin = await repository.previewCalendarImport(
        request([
          timed(sourceEventId: 'evt-1@example.com', occurrenceId: rawIdentity),
        ]),
      );
      expect(sameOrigin.pending, isEmpty);
      expect(sameOrigin.duplicateCount, 1);

      final otherOrigin = await repository.previewCalendarImport(
        CalendarImportRequest(
          sources: const [
            CalendarImportSource(id: 'source-b', displayName: '个人'),
          ],
          occurrences: [
            timed(
              sourceId: 'source-b',
              sourceEventId: 'evt-1@example.com',
              occurrenceId: rawIdentity,
            ),
          ],
          from: DateTime.utc(2026, 11, 16),
          to: DateTime.utc(2026, 11, 23),
        ),
      );
      expect(otherOrigin.pending, hasLength(1));
      expect(otherOrigin.duplicateCount, 0);
    },
  );

  test(
    'the same installation keeps skipping its device-local import',
    () async {
      await seedInstallation('install-test');
      final occurrence = timed(
        sourceEventId: 'local:42',
        occurrenceId: 'local:42@1',
        deviceOccurrenceId: 'local:42',
      );
      final first = await repository.previewCalendarImport(
        request([occurrence]),
      );
      final created = await repository.confirmCalendarImport(first);
      expect(created.createdCount, 1);
      expect(aliasEncodings(created.created.single.eventIdentity), [
        const CalendarImportAlias.device(
          installId: 'install-test',
          calendarId: '7',
          deviceRowId: 'local:42',
        ).encode(),
      ]);

      final again = await repository.previewCalendarImport(
        request([occurrence]),
      );
      expect(again.pending, isEmpty);
      expect(again.duplicateCount, 1);
      expect(await repository.getSchedules(), hasLength(1));
    },
  );

  test(
    'a source that gains a provider identity keeps the local copy',
    () async {
      await seedInstallation('install-test');
      final localPreview = await repository.previewCalendarImport(
        request([
          timed(
            sourceEventId: 'local:42',
            occurrenceId: 'local:42@1',
            deviceOccurrenceId: 'local:42',
          ),
        ]),
      );
      final localCopy = (await repository.confirmCalendarImport(localPreview))
          .created
          .single;

      final syncedPreview = await repository.previewCalendarImport(
        request([
          timed(
            sourceEventId: 'evt-42@example.com',
            occurrenceId: 'evt-42@example.com@1',
          ),
        ]),
      );
      expect(syncedPreview.duplicateCount, 0);
      expect(syncedPreview.pending, hasLength(1));
      final syncedCopy = (await repository.confirmCalendarImport(syncedPreview))
          .created
          .single;
      final syncedAlias = decodeCalendarImportIdentityAliases(
        syncedCopy.eventIdentity,
      ).single;
      expect(syncedAlias.kind, calendarImportAliasSync);
      expect(syncedAlias.occurrenceId, isNull);

      final stored = await repository.getSchedules();
      expect(stored, hasLength(2));
      final untouched = stored.firstWhere((item) => item.id == localCopy.id);
      expect(untouched.eventIdentity, localCopy.eventIdentity);
      expect(untouched.title, localCopy.title);
      expect(untouched.startsAt, localCopy.startsAt);
    },
  );

  test('a provider id appearing on the same device row keeps skipping the edited copy', () async {
    await seedInstallation('install-test');
    final localPreview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'local:42',
          occurrenceId: 'local:42@1',
          deviceOccurrenceId: 'local:42',
        ),
      ]),
    );
    final copy = (await repository.confirmCalendarImport(localPreview))
        .created
        .single;
    await repository.updateSchedule(
      copy.id,
      ScheduleDraft(
        title: '我改过的本机日程',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 15),
          endsAt: DateTime.utc(2026, 11, 16, 16),
        ),
      ),
    );

    // The platform later exposes a provider id for the very same device row.
    final providerPreview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'evt-42@example.com',
          occurrenceId: 'evt-42@example.com@1',
          deviceOccurrenceId: 'local:42',
        ),
      ]),
    );
    expect(providerPreview.pending, isEmpty);
    expect(providerPreview.duplicateCount, 1);

    final repeated = await repository.confirmCalendarImport(providerPreview);
    expect(repeated.createdCount, 0);
    final stored = (await repository.getSchedules()).single;
    expect(stored.title, '我改过的本机日程');
    expect(stored.startsAt, DateTime.utc(2026, 11, 16, 15));
    expect(aliasEncodings(stored.eventIdentity).toSet(), {
      const CalendarImportAlias.device(
        installId: 'install-test',
        calendarId: '7',
        deviceRowId: 'local:42',
      ).encode(),
      const CalendarImportAlias.sync(
        sourceId: 'source-a',
        sourceEventId: 'evt-42@example.com',
      ).encode(),
    });
  });

  test('moving a non-recurring source event keeps the same copy', () async {
    await seedInstallation('install-test');
    final firstPreview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'evt-9@example.com',
          occurrenceId: 'evt-9@example.com@1',
          deviceOccurrenceId: 'local:9',
        ),
      ]),
    );
    final copy = (await repository.confirmCalendarImport(firstPreview))
        .created
        .single;

    // The source event is moved on the platform: same event row and provider id.
    final movedPreview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'evt-9@example.com',
          occurrenceId: 'evt-9@example.com@2',
          deviceOccurrenceId: 'local:9',
          startsAt: DateTime.utc(2026, 11, 16, 15),
          endsAt: DateTime.utc(2026, 11, 16, 16),
        ),
      ]),
    );
    expect(movedPreview.pending, isEmpty);
    expect(movedPreview.duplicateCount, 1);

    await repository.confirmCalendarImport(movedPreview);
    final stored = (await repository.getSchedules()).single;
    expect(stored.startsAt, DateTime.utc(2026, 11, 16, 9));
    expect(stored.title, copy.title);
    expect(stored.eventIdentity, copy.eventIdentity);
  });

  test(
    'a provider id with a moved start keeps the imported local copy',
    () async {
      await seedInstallation('install-test');
      final localPreview = await repository.previewCalendarImport(
        request([
          timed(
            sourceEventId: 'local:42',
            occurrenceId: 'local:42@1',
            deviceOccurrenceId: 'local:42',
          ),
        ]),
      );
      final copy = (await repository.confirmCalendarImport(localPreview))
          .created
          .single;
      await repository.updateSchedule(
        copy.id,
        ScheduleDraft(
          title: '我改到下午的本机日程',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 15),
            endsAt: DateTime.utc(2026, 11, 16, 16),
          ),
        ),
      );

      final syncedPreview = await repository.previewCalendarImport(
        request([
          timed(
            sourceEventId: 'evt-42@example.com',
            occurrenceId: 'evt-42@example.com@2',
            deviceOccurrenceId: 'local:42',
            startsAt: DateTime.utc(2026, 11, 16, 11),
            endsAt: DateTime.utc(2026, 11, 16, 12),
          ),
        ]),
      );
      expect(syncedPreview.pending, isEmpty);
      expect(syncedPreview.duplicateCount, 1);

      await repository.confirmCalendarImport(syncedPreview);
      expect(await repository.getSchedules(), hasLength(1));
      final stored = (await repository.getSchedules()).single;
      expect(stored.title, '我改到下午的本机日程');
      expect(stored.startsAt, DateTime.utc(2026, 11, 16, 15));
    },
  );

  test('delimiter characters in public ids never collide', () async {
    await seedInstallation('install-test');
    final preview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'e|x',
          occurrenceId: 'o',
          deviceOccurrenceId: 'local:1@o',
          isRecurring: true,
        ),
        timed(
          sourceEventId: 'e',
          occurrenceId: 'x|o',
          deviceOccurrenceId: 'local:2@x|o',
          isRecurring: true,
        ),
      ]),
    );

    expect(preview.duplicateCount, 0);
    expect(preview.pending, hasLength(2));
    expect(
      preview.pending.map((item) => item.identityKey).toSet(),
      hasLength(2),
    );
    final outcome = await repository.confirmCalendarImport(preview);
    expect(outcome.createdCount, 2);
  });

  test(
    'an installation-scoped v1 identity still skips on this installation',
    () async {
      await seedInstallation('install-test');
      await seedImportedCopy(
        scheduleId: 'seeded-v1',
        identity: 'calendar-import/1|device:install-test:7|source-a|local:42|local:42@1',
      );

      final preview = await repository.previewCalendarImport(
        request([
          timed(
            sourceEventId: 'local:42',
            occurrenceId: 'local:42@1',
            deviceOccurrenceId: 'local:42',
          ),
        ]),
      );
      expect(preview.pending, isEmpty);
      expect(preview.duplicateCount, 1);
      expect(await repository.getSchedules(), hasLength(1));
    },
  );

  test('a v1 identity of another installation never skips', () async {
    await seedInstallation('install-test');
    await seedImportedCopy(
      scheduleId: 'seeded-other',
      identity: 'calendar-import/1|device:install-other:7|source-a|local:42|local:42@1',
    );

    final preview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'local:42',
          occurrenceId: 'local:42@1',
          deviceOccurrenceId: 'local:42',
        ),
      ]),
    );
    expect(preview.pending, hasLength(1));
    expect(preview.duplicateCount, 0);
    final outcome = await repository.confirmCalendarImport(preview);
    expect(outcome.createdCount, 1);
    expect(await repository.getSchedules(), hasLength(2));
  });

  test('a legacy device-local copy never causes a false skip', () async {
    await seedInstallation('install-test');
    await database
        .into(database.localCalendarSources)
        .insert(
          LocalCalendarSourcesCompanion.insert(
            userId: 'user-a',
            sourceId: 'source-a',
            displayName: '工作',
            timeZoneId: 'Asia/Shanghai',
            updatedAt: DateTime.utc(2026, 11, 1),
          ),
        );
    const rawIdentity = 'local:42@1763283600000';
    await database
        .into(database.localCalendarBlocks)
        .insert(
          LocalCalendarBlocksCompanion.insert(
            userId: 'user-a',
            sourceId: 'source-a',
            sourceEventId: 'local:42',
            occurrenceId: rawIdentity,
            eventIdentity: rawIdentity,
            title: '别的设备的本机事件',
            startsAt: DateTime.utc(2026, 11, 16, 9),
            endsAt: DateTime.utc(2026, 11, 16, 10),
            availability: 'busy',
            timeZoneId: 'Asia/Shanghai',
            updatedAt: DateTime.utc(2026, 11, 1),
          ),
        );
    await repository.promoteLegacyCalendarBlocks();
    expect(
      (await repository.getSchedules()).single.origin,
      ScheduleOrigin.legacyCalendarBlock,
    );

    final preview = await repository.previewCalendarImport(
      request([
        timed(
          sourceEventId: 'local:42',
          occurrenceId: rawIdentity,
          deviceOccurrenceId: 'local:42',
        ),
      ]),
    );
    expect(preview.duplicateCount, 0);
    expect(preview.pending, hasLength(1));
  });
}
