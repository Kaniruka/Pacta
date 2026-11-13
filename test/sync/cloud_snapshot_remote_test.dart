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
    var calls = 0;
    final client = await _authenticatedClient((request) async {
      calls++;
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

    expect(calls, 1);
    expect(sentParameters?['p_device_manufacturer'], 'Example Corp');
    expect(sentParameters?['p_device_model'], 'Example Model');
    expect(snapshot.deviceManufacturer, 'Example Corp');
    expect(snapshot.deviceModel, 'Example Model');
  });

  test(
    'upload retries the confirmed old RPC with unchanged snapshot',
    () async {
      final requests = <http.Request>[];
      final client = await _authenticatedClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            requests.length == 1
                ? _oldRpcError()
                : _snapshotRow(hardware: false),
          ),
          requests.length == 1 ? 404 : 200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.dispose);
      final saved = await _upload(SupabaseCloudSnapshotRemote(client));
      expect(saved.revision, 4);
      expect(requests, hasLength(2));
      final first = jsonDecode(requests.first.body) as Map<String, dynamic>;
      final second = jsonDecode(requests.last.body) as Map<String, dynamic>;
      // 首次带上全部可选参数（含上传请求标识），退回时只去掉该标识。
      expect(first, hasLength(10));
      expect(second, {
        'p_expected_revision': 3,
        'p_payload': {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
        'p_device_id': 'device-a',
        'p_device_name': 'Phone A',
        'p_data_updated_at': '2026-10-01T00:00:00.000Z',
        'p_row_count': 0,
        'p_expected_legacy_token': null,
        'p_device_manufacturer': 'Example Corp',
        'p_device_model': 'Example Model',
      });
    },
  );

  test('upload does not retry a transport failure', () async {
    var calls = 0;
    final client = await _authenticatedClient((request) async {
      calls++;
      throw http.ClientException('offline', request.url);
    });
    addTearDown(client.dispose);
    await expectLater(
      _upload(SupabaseCloudSnapshotRemote(client)),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 1);
  });

  test('old RPC retry preserves the inspected legacy token', () async {
    const token = '0123456789abcdef0123456789abcdef';
    final uploads = <Map<String, dynamic>>[];
    final client = await _authenticatedClient((request) async {
      Object body;
      var status = 200;
      if (request.url.path.endsWith('/cloud_business_snapshots')) {
        body = [];
      } else if (request.url.path.endsWith('/read_legacy_business_records')) {
        body = {
          'token': token,
          'records': {
            'tasks': [],
            'focus_sessions': [],
            'focus_appointments': [],
            'focus_nodes': [],
            'focus_chain_records': [],
            'appointment_chain_records': [],
            'focus_precedent_rules': [],
            'focus_sync_sources': [],
            'calendar_sources': [],
            'calendar_blocks': [],
            'goals': [
              {
                'id': 'goal-1',
                'user_id': 'user-a',
                'title': 'Legacy goal',
                'classification': 'regular',
                'created_at': '2026-09-01T00:00:00Z',
                'updated_at': '2026-09-02T03:04:05Z',
                'deleted_at': null,
              },
            ],
          },
        };
      } else {
        uploads.add(jsonDecode(request.body) as Map<String, dynamic>);
        body = uploads.length == 1
            ? _oldRpcError()
            : _snapshotRow(hardware: false);
        status = uploads.length == 1 ? 404 : 200;
      }
      return http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    final remote = SupabaseCloudSnapshotRemote(client);
    final preview = await remote.inspect(userId: 'user-a');
    await remote.upload(
      userId: 'user-a',
      expectedRevision: preview!.revision,
      payload: preview.payload!,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: preview.dataUpdatedAt,
      rowCount: preview.rowCount,
    );
    expect(uploads, hasLength(2));
    for (final sent in uploads) {
      expect(sent['p_expected_revision'], 0);
      expect(sent['p_expected_legacy_token'], token);
      expect(sent['p_payload'], preview.payload);
    }
    // 退回 9 参数签名时必须去掉上传请求标识，其余参数保持不变。
    expect(uploads.first.containsKey('p_request_id'), isTrue);
    expect(uploads.last.containsKey('p_request_id'), isFalse);
    expect(uploads.last.containsKey('p_device_manufacturer'), isTrue);
  });

  test('old RPC retry drops both optional parameter groups', () async {
    const token = '0123456789abcdef0123456789abcdef';
    final uploads = <Map<String, dynamic>>[];
    final client = await _authenticatedClient((request) async {
      Object body;
      var status = 200;
      if (request.url.path.endsWith('/cloud_business_snapshots')) {
        body = [];
      } else if (request.url.path.endsWith('/read_legacy_business_records')) {
        body = {
          'token': token,
          'records': {
            'goals': [
              {
                'id': 'goal-1',
                'user_id': 'user-a',
                'title': 'Legacy goal',
                'classification': 'regular',
                'created_at': '2026-09-01T00:00:00Z',
                'updated_at': '2026-09-02T03:04:05Z',
                'deleted_at': null,
              },
            ],
            'tasks': [],
            'focus_sessions': [],
            'focus_appointments': [],
            'focus_nodes': [],
            'focus_chain_records': [],
            'appointment_chain_records': [],
            'focus_precedent_rules': [],
            'focus_sync_sources': [],
            'calendar_sources': [],
            'calendar_blocks': [],
          },
        };
      } else {
        uploads.add(jsonDecode(request.body) as Map<String, dynamic>);
        body = uploads.length == 1
            ? _oldestRpcError()
            : _snapshotRow(hardware: false);
        status = uploads.length == 1 ? 404 : 200;
      }
      return http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    final remote = SupabaseCloudSnapshotRemote(client);
    final preview = await remote.inspect(userId: 'user-a');
    await remote.upload(
      userId: 'user-a',
      expectedRevision: preview!.revision,
      payload: preview.payload!,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: preview.dataUpdatedAt,
      rowCount: preview.rowCount,
      requestId: 'request-92',
    );
    expect(uploads, hasLength(2));
    expect(uploads.first['p_request_id'], 'request-92');
    for (final dropped in const [
      'p_request_id',
      'p_device_manufacturer',
      'p_device_model',
    ]) {
      expect(uploads.last.containsKey(dropped), isFalse);
    }
    expect(uploads.last['p_device_id'], 'device-a');
  });

  for (final scenario in [
    (
      name: 'unrelated missing function',
      code: 'PGRST202',
      status: 404,
      oldHint: false,
      mapped: false,
    ),
    (
      name: 'permission',
      code: '42501',
      status: 403,
      oldHint: true,
      mapped: true,
    ),
    (
      name: 'authentication',
      code: 'PGRST301',
      status: 401,
      oldHint: true,
      mapped: false,
    ),
    (name: 'conflict', code: 'PT409', status: 409, oldHint: true, mapped: true),
  ]) {
    test('upload does not retry ${scenario.name}', () async {
      var calls = 0;
      final client = await _authenticatedClient((request) async {
        calls++;
        final error = _oldRpcError()..['code'] = scenario.code;
        if (!scenario.oldHint) error['hint'] = 'No matching function';
        return http.Response(
          jsonEncode(error),
          scenario.status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.dispose);
      await expectLater(
        _upload(SupabaseCloudSnapshotRemote(client)),
        throwsA(
          scenario.mapped ? isA<StateError>() : isA<PostgrestException>(),
        ),
      );
      expect(calls, 1);
    });
  }

  for (final code in ['PT409', '42501', 'PGRST202']) {
    test(
      'old RPC failure $code is not retried again and keeps error mapping',
      () async {
        var calls = 0;
        final client = await _authenticatedClient((request) async {
          calls++;
          return http.Response(
            jsonEncode(
              calls == 1 ? _oldRpcError() : {..._oldRpcError(), 'code': code},
            ),
            calls == 1 ? 404 : 409,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        });
        addTearDown(client.dispose);
        await expectLater(
          _upload(SupabaseCloudSnapshotRemote(client)),
          throwsA(
            code == 'PGRST202' ? isA<PostgrestException>() : isA<StateError>(),
          ),
        );
        expect(calls, 2);
      },
    );
  }

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

/// 服务端只剩 9 参数签名（含设备元数据、无上传请求标识）时 PostgREST 的报错：
/// message 列出客户端实际请求的 10 个参数，hint 列出已存在的 9 参数签名。
Map<String, Object?> _oldRpcError() => {
  'code': 'PGRST202',
  'message': 'Could not find the function public.save_cloud_business_snapshot(p_data_updated_at, p_device_id, p_device_manufacturer, p_device_model, p_device_name, p_expected_legacy_token, p_expected_revision, p_payload, p_request_id, p_row_count) in the schema cache',
  'hint': 'Perhaps you meant to call the function public.save_cloud_business_snapshot(p_data_updated_at, p_device_id, p_device_manufacturer, p_device_model, p_device_name, p_expected_legacy_token, p_expected_revision, p_payload, p_row_count)',
};

/// 服务端只剩最初的 7 参数签名时：两层可选参数都要退回。
Map<String, Object?> _oldestRpcError() => {
  'code': 'PGRST202',
  'message': 'Could not find the function public.save_cloud_business_snapshot(p_data_updated_at, p_device_id, p_device_manufacturer, p_device_model, p_device_name, p_expected_legacy_token, p_expected_revision, p_payload, p_request_id, p_row_count) in the schema cache',
  'hint': 'Perhaps you meant to call the function public.save_cloud_business_snapshot(p_data_updated_at, p_device_id, p_device_name, p_expected_legacy_token, p_expected_revision, p_payload, p_row_count)',
};

Future<CloudSnapshotMetadata> _upload(SupabaseCloudSnapshotRemote remote) =>
    remote.upload(
      userId: 'user-a',
      expectedRevision: 3,
      payload: const {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: DateTime.utc(2026, 10, 1),
      rowCount: 0,
      deviceManufacturer: 'Example Corp',
      deviceModel: 'Example Model',
    );
