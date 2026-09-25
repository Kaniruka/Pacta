import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _testEmail = String.fromEnvironment('TEST_ADMIN_EMAIL');
const _testPassword = String.fromEnvironment('TEST_ADMIN_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final missingConfiguration =
      _supabaseUrl.isEmpty ||
      _supabaseKey.isEmpty ||
      _testEmail.isEmpty ||
      _testPassword.isEmpty;

  testWidgets('T18 真实 Supabase 适配器断网保留、重连上传、重复同步幂等', (tester) async {
    final result = await tester.runAsync(() async {
      final httpClient = _ToggleableHttpClient(http.Client());
      final client = SupabaseClient(
        _supabaseUrl,
        _supabaseKey,
        httpClient: httpClient,
      );
      try {
        final auth = await client.auth.signInWithPassword(
          email: _testEmail,
          password: _testPassword,
        );
        final userId = auth.user?.id;
        if (userId == null) {
          throw StateError('Supabase test login did not return a user.');
        }
        return await _verifyCloudRoundTrip(
          userId: userId,
          client: client,
          httpClient: httpClient,
        );
      } finally {
        await client.dispose();
        httpClient.close();
      }
    });

    expect(result, isNotNull);
    expect(result!.offlineDataRetained, isTrue);
    expect(result.uploadedCard, isTrue);
    expect(result.repeatedUploadWasIdempotent, isTrue);
    expect(result.downloadedToSecondDevice, isTrue);
  }, skip: missingConfiguration);
}

Future<
  ({
    bool offlineDataRetained,
    bool uploadedCard,
    bool repeatedUploadWasIdempotent,
    bool downloadedToSecondDevice,
  })
>
_verifyCloudRoundTrip({
  required String userId,
  required SupabaseClient client,
  required _ToggleableHttpClient httpClient,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'pacta-ticket-18-supabase-',
  );
  final firstDatabase = PactaDatabase(
    NativeDatabase(File('${directory.path}/first.sqlite')),
  );
  final firstRepository = LocalNationalFocusRepository(
    database: firstDatabase,
    userId: userId,
    remote: SupabaseNationalFocusRemoteDataSource(client),
  );
  PactaDatabase? secondDatabase;
  LocalNationalFocusRepository? secondRepository;

  try {
    await firstRepository.sync();
    final card = await firstRepository.createCard(
      NationalFocusCardDraft(
        triggerCondition:
            'T18 云端验收 ${DateTime.now().toUtc().toIso8601String()}',
        action: '保持在验收账号的国策卡片库中',
      ),
    );

    httpClient.online = false;
    Object? offlineFailure;
    try {
      await firstRepository.sync();
    } catch (error) {
      offlineFailure = error;
    }
    final locallyRetainedCard = await firstRepository.getCard(card.id);
    final offlineDataRetained =
        offlineFailure != null && !locallyRetainedCard.isInTree;

    httpClient.online = true;
    await firstRepository.sync();
    final remote = SupabaseNationalFocusRemoteDataSource(client);
    final firstUpload = await remote.pull(userId: userId);
    final uploadedCard = firstUpload.any(
      (source) => source.payload.contains(card.id),
    );
    final firstSourceIds = firstUpload.map((source) => source.sourceId).toSet();

    await firstRepository.sync();
    final repeatedUpload = await remote.pull(userId: userId);
    final repeatedSourceIds = repeatedUpload
        .map((source) => source.sourceId)
        .toSet();
    final repeatedUploadWasIdempotent =
        firstSourceIds.length == repeatedUpload.length &&
        firstSourceIds.containsAll(repeatedSourceIds) &&
        repeatedSourceIds.containsAll(firstSourceIds);

    secondDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/second.sqlite')),
    );
    secondRepository = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: userId,
      remote: SupabaseNationalFocusRemoteDataSource(client),
    );
    await secondRepository.sync();
    final downloadedCard = await secondRepository.getCard(card.id);

    return (
      offlineDataRetained: offlineDataRetained,
      uploadedCard: uploadedCard,
      repeatedUploadWasIdempotent: repeatedUploadWasIdempotent,
      downloadedToSecondDevice: downloadedCard.id == card.id,
    );
  } finally {
    await secondRepository?.dispose();
    await secondDatabase?.close();
    await firstRepository.dispose();
    await firstDatabase.close();
    await directory.delete(recursive: true);
  }
}

class _ToggleableHttpClient extends http.BaseClient {
  _ToggleableHttpClient(this._delegate);

  final http.Client _delegate;
  bool online = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!online) {
      throw const SocketException('T18 acceptance test forced offline mode.');
    }
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}
