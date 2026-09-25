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
    'T20 synthetic Android-side import syncs through Supabase and renders on Windows (requires .env)',
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
      String? userId;
      String? sourceId;
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
                  .eq('source_id', sourceId!);
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

          final now = DateTime.now();
          final dayStart = DateTime(now.year, now.month, now.day);
          final stamp = now.microsecondsSinceEpoch;
          sourceId = 't20-cloud-acceptance-$stamp';
          final source = CalendarSource(
            id: sourceId!,
            displayName: 'Ticket-20 临时验收来源',
            timeZoneId: 'Asia/Shanghai',
          );
          final event = CalendarEventOccurrence(
            sourceId: source.id,
            sourceEventId: 't20-event-$stamp',
            occurrenceId: 't20-occurrence-$stamp',
            eventIdentity: 't20-identity-$stamp',
            title: 'Ticket-20 跨端验收样例',
            startsAt: dayStart.toUtc().add(const Duration(hours: 10)),
            endsAt: dayStart.toUtc().add(const Duration(hours: 11)),
            allDay: false,
            availability: CalendarAvailability.busy,
            timeZoneId: 'Asia/Shanghai',
          );

          androidDatabase = PactaDatabase(NativeDatabase.memory());
          androidRepository = LocalCalendarRepository(
            database: androidDatabase!,
            userId: userId!,
            provider: FakeCalendarProvider(
              sources: [source],
              events: [event],
              permission: CalendarPermissionState.granted,
            ),
            remote: SupabaseCalendarRemoteDataSource(androidClient!),
          );
          await androidRepository!.requestAccess();
          remoteWriteAttempted = true;
          final imported = await androidRepository!.importCalendars({
            source.id,
          });
          expect(imported.importedOccurrences, 1);
          expect(imported.synced, isTrue);

          windowsDatabase = PactaDatabase(NativeDatabase.memory());
          windowsRepository = LocalCalendarRepository(
            database: windowsDatabase!,
            userId: userId!,
            provider: const UnsupportedCalendarProvider(),
            remote: SupabaseCalendarRemoteDataSource(windowsClient!),
          );
          await windowsRepository!.sync();
          final agenda = await windowsRepository!.getAgenda(
            from: dayStart,
            to: dayStart.add(const Duration(days: 1)),
          );
          expect(agenda.blocks.single.title, event.title);
          expect(agenda.blocks.single.sourceIds, contains(source.id));
        } catch (error) {
          sanitizedFailure = error.runtimeType;
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
      expect(find.text('Ticket-20 跨端验收样例'), findsOneWidget);
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
      expect(find.text('Ticket-20 临时验收来源'), findsOneWidget);
    },
    skip: !hasSupabaseConfiguration,
  );
}
