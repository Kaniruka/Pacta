import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('inspect reads optional manufacturer and model metadata', () async {
    final requests = <http.Request>[];
    final client = await _authenticatedClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode([_snapshotRow(hardware: true)]),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    addTearDown(client.dispose);

    final snapshot = await SupabaseCloudSnapshotRemote(client)
        .inspect(userId: 'user-a');

    expect(snapshot?.deviceName, 'Phone A');
    expect(snapshot?.deviceManufacturer, 'Example Corp');
    expect(snapshot?.deviceModel, 'Example Model');
    expect(requests, hasLength(1));
    expect(
      requests.single.url.queryParameters['select'],
      contains('device_manufacturer'),
    );
    expect(
      requests.single.url.queryParameters['select'],
      contains('device_model'),
    );
  });

  test(
    'inspect falls back to old columns when cloud table lacks new columns',
    () async {
      final requests = <http.Request>[];
      final client = await _authenticatedClient((request) async {
        requests.add(request);
        final select = request.url.queryParameters['select'] ?? '';
        if (select.contains('device_manufacturer')) {
          return http.Response(
            jsonEncode({
              'code': 'PGRST204',
              'message':
                  "Could not find the 'device_manufacturer' column of "
                  "'cloud_business_snapshots' in the schema cache",
            }),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode([_snapshotRow(hardware: false)]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      addTearDown(client.dispose);

      final snapshot = await SupabaseCloudSnapshotRemote(client)
          .inspect(userId: 'user-a');

      expect(requests, hasLength(2));
      expect(
        requests.first.url.queryParameters['select'],
        contains('device_model'),
      );
      expect(
        requests.last.url.queryParameters['select'],
        isNot(contains('device_model')),
      );
      expect(snapshot?.revision, 4);
      expect(snapshot?.deviceName, 'Old Phone');
      expect(snapshot?.deviceManufacturer, isNull);
      expect(snapshot?.deviceModel, isNull);
      expect(snapshot?.uploadedAt, DateTime.utc(2026, 10, 1));
    },
  );

  test(
    'download accepts old snapshot rows without new metadata keys',
    () async {
      http.Request? requestSeen;
      final client = await _authenticatedClient((request) async {
        requestSeen = request;
        return http.Response(
          jsonEncode(_snapshotRow(hardware: false, includePayload: true)),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      addTearDown(client.dispose);

      final snapshot = await SupabaseCloudSnapshotRemote(client)
          .download(userId: 'user-a');

      expect(requestSeen?.url.queryParameters['select'], '*');
      expect(snapshot.payload, {
        'schemaVersion': 1,
        'userId': 'user-a',
        'tables': {},
      });
      expect(snapshot.deviceManufacturer, isNull);
      expect(snapshot.deviceModel, isNull);
      expect(snapshot.uploadedAt, DateTime.utc(2026, 10, 1));
    },
  );

  test('upload sends trimmed optional metadata through the RPC', () async {
    Map<String, dynamic>? sentParameters;
    final client = await _authenticatedClient((request) async {
      sentParameters = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(_snapshotRow(hardware: true)),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    addTearDown(client.dispose);

    final snapshot = await SupabaseCloudSnapshotRemote(client).upload(
      userId: 'user-a',
      expectedRevision: 0,
      payload: const {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: DateTime.utc(2026, 10, 1),
      rowCount: 0,
      deviceManufacturer: ' Example Corp ',
      deviceModel: ' Example Model ',
    );

    expect(sentParameters?['p_device_manufacturer'], 'Example Corp');
    expect(sentParameters?['p_device_model'], 'Example Model');
    expect(snapshot.deviceManufacturer, 'Example Corp');
    expect(snapshot.deviceModel, 'Example Model');
  });

  test(
    'current-user check still blocks access before the cloud request',
    () async {
      var requestCount = 0;
      final client = await _authenticatedClient((request) async {
        requestCount++;
        return http.Response('[]', 200, request: request);
      });
      addTearDown(client.dispose);

      await expectLater(
        SupabaseCloudSnapshotRemote(client).inspect(userId: 'user-b'),
        throwsA(isA<StateError>()),
      );
      expect(requestCount, 0);
    },
  );
}

Future<SupabaseClient> _authenticatedClient(
  Future<http.Response> Function(http.Request request) handler,
) async {
  final client = SupabaseClient(
    'https://pacta-test.supabase.co',
    'publishable-test-key',
    httpClient: MockClient(handler),
  );
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final token =
      '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': 'user-a', 'exp': expiry, 'iat': expiry - 3600})}.signature';
  final session = Session(
    accessToken: token,
    expiresIn: 3600,
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    user: const User(
      id: 'user-a',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
    ),
  );
  await client.auth.recoverSession(jsonEncode(session.toJson()));
  return client;
}

Map<String, Object?> _snapshotRow({
  required bool hardware,
  bool includePayload = false,
}) => {
  'revision': 4,
  'device_id': 'device-a',
  'device_name': hardware ? 'Phone A' : 'Old Phone',
  'data_updated_at': '2026-10-01T00:00:00Z',
  'uploaded_at': '2026-10-01T00:00:00Z',
  'row_count': 0,
  if (hardware) 'device_manufacturer': 'Example Corp',
  if (hardware) 'device_model': 'Example Model',
  if (includePayload)
    'payload': {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
};
