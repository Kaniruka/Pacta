import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_page.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/support/fake_calendar_provider.dart';

Map<String, String> _readLocalEnvironment() {
  var directory = Directory.current;
  File? file;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File('${directory.path}${Platform.pathSeparator}.env');
    if (candidate.existsSync()) {
      file = candidate;
      break;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  final envFile = file;
  if (envFile == null) return const {};
  final values = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator < 1) continue;
    final key = trimmed.substring(0, separator).trim();
    var value = trimmed.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    values[key] = value;
  }
  return values;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final env = _readLocalEnvironment();
  final hasSupabaseConfiguration = [
    'SUPABASE_URL',
    'SUPABASE_PUBLISHABLE_KEY',
    'TEST_ADMIN_EMAIL',
    'TEST_ADMIN_PASSWORD',
  ].every((key) => env[key]?.isNotEmpty ?? false);

  testWidgets(
    'T20/T21 synthetic Android-side calendar changes reconcile through Supabase on Windows (requires .env)',
    (tester) async {
      final url = env['SUPABASE_URL']!;
      final publishableKey = env['SUPABASE_PUBLISHABLE_KEY']!;
      final email = env['TEST_ADMIN_EMAIL']!;
      final password = env['TEST_ADMIN_PASSWORD']!;

      SupabaseClient? androidClient;
      SupabaseClient? windowsClient;
      PactaDatabase? androidDatabase;
      PactaDatabase? windowsDatabase;
      LocalCalendarRepository? androidRepository;
      LocalCalendarRepository? windowsRepository;
      FakeCalendarProvider? androidProvider;
      CalendarEventOccurrence? firstRecurringOccurrence;
      CalendarEventOccurrence? secondRecurringOccurrence;
      String? firstRecurringIdentity;
      DateTime? dayStart;
      String? userId;
      String? sourceId;
      String? duplicateSourceId;
      var remoteStage = 'client setup';
      var remoteWriteAttempted = false;
      Object? sanitizedFailure;

      addTearDown(() async {
        Object? cleanupFailure;
        Future<void> disposeSafely(Future<void> Function() dispose) async {
          try {
            await dispose();
          } catch (error) {
            cleanupFailure ??= error.runtimeType;
          }
        }

        try {
          await tester.pumpWidget(const SizedBox.shrink());
        } catch (error) {
          cleanupFailure = error.runtimeType;
        }
        try {
          await tester.runAsync(() async {
            if (remoteWriteAttempted &&
                userId != null &&
                sourceId != null &&
                androidClient != null) {
              await androidClient!
                  .from('calendar_sources')
                  .delete()
                  .eq('user_id', userId!)
                  .inFilter('source_id', [sourceId!, duplicateSourceId!]);
            }
          });
        } catch (error) {
          cleanupFailure ??= error.runtimeType;
        } finally {
          try {
            await tester.runAsync(() async {
              await disposeSafely(() async {
                await androidRepository?.dispose();
              });
              await disposeSafely(() async {
                await windowsRepository?.dispose();
              });
              await disposeSafely(() async {
                await androidDatabase?.close();
              });
              await disposeSafely(() async {
                await windowsDatabase?.close();
              });
              await disposeSafely(() async {
                await androidClient?.auth.signOut();
              });
              await disposeSafely(() async {
                await windowsClient?.auth.signOut();
              });
              await disposeSafely(() async {
                await androidClient?.dispose();
              });
              await disposeSafely(() async {
                await windowsClient?.dispose();
              });
            });
          } catch (error) {
            cleanupFailure ??= error.runtimeType;
          }
        }
        if (cleanupFailure != null) {
          fail('T20 云端验收清理失败（${cleanupFailure.toString()}）；输出未包含凭据或日历内容。');
        }
      });

      await tester.runAsync(() async {
        androidClient = SupabaseClient(url, publishableKey);
        windowsClient = SupabaseClient(url, publishableKey);
        try {
          remoteStage = 'admin sign-in';
          await androidClient!.auth.signInWithPassword(
            email: email,
            password: password,
          );
          userId = androidClient!.auth.currentUser?.id;
          expect(userId, isNotNull);
          await windowsClient!.auth.signInWithPassword(
            email: email,
            password: password,
          );
          expect(windowsClient!.auth.currentUser?.id, userId);

          remoteStage = 'synthetic calendar setup';
          final now = DateTime.now();
          final currentDayStart = DateTime(now.year, now.month, now.day);
          dayStart = currentDayStart;
          final stamp = now.microsecondsSinceEpoch;
          sourceId = 't20-cloud-acceptance-$stamp';
          duplicateSourceId = 't21-cloud-duplicate-$stamp';
          final source = CalendarSource(
            id: sourceId!,
            displayName: 'Ticket-20 临时验收来源',
            timeZoneId: 'Asia/Shanghai',
          );
          final duplicateSource = CalendarSource(
            id: duplicateSourceId!,
            displayName: 'Ticket-21 重复日程验收来源',
            timeZoneId: 'Asia/Shanghai',
          );
          final firstOccurrence = CalendarEventOccurrence(
            sourceId: source.id,
            sourceEventId: 't21-recurring-$stamp',
            occurrenceId: 't21-recurring-first-$stamp',
            eventIdentity: 't21-recurring-first-identity-$stamp',
            title: 'Ticket-20 跨端验收样例',
            startsAt: currentDayStart.toUtc().add(const Duration(hours: 10)),
            endsAt: currentDayStart.toUtc().add(const Duration(hours: 11)),
            allDay: false,
            availability: CalendarAvailability.busy,
            timeZoneId: 'Asia/Shanghai',
          );
          firstRecurringOccurrence = firstOccurrence;
          firstRecurringIdentity = firstOccurrence.eventIdentity;
          final secondOccurrence = CalendarEventOccurrence(
            sourceId: source.id,
            sourceEventId: 't21-recurring-$stamp',
            occurrenceId: 't21-recurring-second-$stamp',
            eventIdentity: 't21-recurring-second-identity-$stamp',
            title: 'Ticket-20 跨端验收样例',
            startsAt: currentDayStart.toUtc().add(const Duration(hours: 12)),
            endsAt: currentDayStart.toUtc().add(const Duration(hours: 13)),
            allDay: false,
            availability: CalendarAvailability.busy,
            timeZoneId: 'Asia/Shanghai',
          );
          secondRecurringOccurrence = secondOccurrence;
          final duplicateOccurrence = CalendarEventOccurrence(
            sourceId: duplicateSource.id,
            sourceEventId: 't21-duplicate-$stamp',
            occurrenceId: firstOccurrence.occurrenceId,
            eventIdentity: firstOccurrence.eventIdentity,
            title: firstOccurrence.title,
            startsAt: firstOccurrence.startsAt,
            endsAt: firstOccurrence.endsAt,
            allDay: false,
            availability: CalendarAvailability.busy,
            timeZoneId: 'Asia/Shanghai',
          );
          androidProvider = FakeCalendarProvider(
            sources: [source, duplicateSource],
            events: [firstOccurrence, secondOccurrence, duplicateOccurrence],
            permission: CalendarPermissionState.granted,
          );

          androidDatabase = PactaDatabase(NativeDatabase.memory());
          androidRepository = LocalCalendarRepository(
            database: androidDatabase!,
            userId: userId!,
            provider: androidProvider!,
            remote: SupabaseCalendarRemoteDataSource(androidClient!),
          );
          await androidRepository!.requestAccess();
          remoteWriteAttempted = true;
          remoteStage = 'Supabase import';
          final imported = await androidRepository!.importCalendars({
            source.id,
            duplicateSource.id,
          });
          expect(imported.importedOccurrences, 3);
          expect(imported.synced, isTrue);

          windowsDatabase = PactaDatabase(NativeDatabase.memory());
          windowsRepository = LocalCalendarRepository(
            database: windowsDatabase!,
            userId: userId!,
            provider: const UnsupportedCalendarProvider(),
            remote: SupabaseCalendarRemoteDataSource(windowsClient!),
          );
          remoteStage = 'Windows Supabase sync';
          await windowsRepository!.sync();
          remoteStage = 'Windows initial agenda';
          final agenda = await windowsRepository!.getAgenda(
            from: currentDayStart,
            to: currentDayStart.add(const Duration(days: 1)),
          );
          expect(agenda.blocks, hasLength(2));
          final sharedOccurrence = agenda.blocks.singleWhere(
            (block) => block.eventIdentity == firstRecurringIdentity,
          );
          expect(
            sharedOccurrence.sourceIds,
            containsAll([source.id, duplicateSource.id]),
          );
          expect(
            agenda.blocks
                .singleWhere(
                  (block) =>
                      block.eventIdentity ==
                      secondRecurringOccurrence!.eventIdentity,
                )
                .sourceIds,
            [source.id],
          );
        } catch (error, stackTrace) {
          final frames = stackTrace.toString().split('\n').take(5).join(' ');
          sanitizedFailure = '$remoteStage:${error.runtimeType}:$frames';
        }
      });
      if (sanitizedFailure != null) {
        fail('T20 云端同步验收失败（${sanitizedFailure.toString()}）；敏感凭据和日历内容不会写入测试输出。');
      }
      if (windowsRepository == null) {
        fail('T20 云端同步验收未建立 Windows 本地副本。');
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: CalendarAgendaCard(repository: windowsRepository!),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ticket-20 跨端验收样例'), findsNWidgets(2));

      Object? reconciliationFailure;
      try {
        await tester.runAsync(() async {
          try {
            final previous = secondRecurringOccurrence!;
            final updated = CalendarEventOccurrence(
              sourceId: previous.sourceId,
              sourceEventId: previous.sourceEventId,
              occurrenceId: previous.occurrenceId,
              eventIdentity: previous.eventIdentity,
              title: 'Ticket-21 改期后的跨端验收样例',
              startsAt: previous.startsAt.add(const Duration(hours: 2)),
              endsAt: previous.endsAt.add(const Duration(hours: 2)),
              allDay: previous.allDay,
              availability: previous.availability,
              timeZoneId: previous.timeZoneId,
            );
            androidProvider!.events = [
              firstRecurringOccurrence!,
              updated,
              ...androidProvider!.events.where(
                (event) => event.sourceId == duplicateSourceId,
              ),
            ];
            await androidRepository!.sync();
            await windowsRepository!.sync();
            final agenda = await windowsRepository!.getAgenda(
              from: dayStart!,
              to: dayStart!.add(const Duration(days: 1)),
            );
            expect(agenda.blocks, hasLength(2));
            final updatedBlock = agenda.blocks.singleWhere(
              (block) => block.eventIdentity == updated.eventIdentity,
            );
            expect(updatedBlock.title, updated.title);
            expect(updatedBlock.startsAt, updated.startsAt);
          } catch (error) {
            reconciliationFailure = error.runtimeType;
          }
        });
      } catch (error) {
        reconciliationFailure ??= error.runtimeType;
      }
      if (reconciliationFailure != null) {
        fail(
          'T21 云端改期同步失败（${reconciliationFailure.toString()}）；敏感凭据和日历内容不会写入测试输出。',
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Ticket-21 改期后的跨端验收样例'), findsOneWidget);

      Object? occurrenceCancellationFailure;
      try {
        await tester.runAsync(() async {
          try {
            androidProvider!.events = androidProvider!.events
                .where(
                  (event) =>
                      event.sourceId != sourceId ||
                      event.occurrenceId !=
                          firstRecurringOccurrence!.occurrenceId,
                )
                .toList();
            await androidRepository!.sync();
            await windowsRepository!.sync();
            final agenda = await windowsRepository!.getAgenda(
              from: dayStart!,
              to: dayStart!.add(const Duration(days: 1)),
            );
            expect(agenda.blocks, hasLength(2));
            final canceledFromA = agenda.blocks.singleWhere(
              (block) => block.eventIdentity == firstRecurringIdentity,
            );
            expect(canceledFromA.sourceIds, [duplicateSourceId]);
            final remainingFromA = agenda.blocks.singleWhere(
              (block) => block.title == 'Ticket-21 改期后的跨端验收样例',
            );
            expect(remainingFromA.sourceIds, [sourceId]);
          } catch (error) {
            occurrenceCancellationFailure = error.runtimeType;
          }
        });
      } catch (error) {
        occurrenceCancellationFailure ??= error.runtimeType;
      }
      if (occurrenceCancellationFailure != null) {
        fail(
          'T21 单个重复日程取消同步失败（${occurrenceCancellationFailure.toString()}）；敏感凭据和日历内容不会写入测试输出。',
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Ticket-20 跨端验收样例'), findsOneWidget);

      Object? removalFailure;
      try {
        await tester.runAsync(() async {
          try {
            await androidRepository!.removeSources({sourceId!});
            await windowsRepository!.sync();
            final agenda = await windowsRepository!.getAgenda(
              from: dayStart!,
              to: dayStart!.add(const Duration(days: 1)),
            );
            expect(agenda.blocks, hasLength(1));
            expect(agenda.blocks.single.sourceIds, [duplicateSourceId]);
          } catch (error) {
            removalFailure = error.runtimeType;
          }
        });
      } catch (error) {
        removalFailure ??= error.runtimeType;
      }
      if (removalFailure != null) {
        fail('T21 云端撤源同步失败（${removalFailure.toString()}）；敏感凭据和日历内容不会写入测试输出。');
      }
      await tester.pumpAndSettle();
      expect(find.text('Ticket-21 改期后的跨端验收样例'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: CalendarSourcesPage(
            repository: windowsRepository!,
            isAndroid: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ticket-20 临时验收来源'), findsNothing);
      expect(find.text('Ticket-21 重复日程验收来源'), findsOneWidget);
    },
    skip: !hasSupabaseConfiguration,
  );
}
