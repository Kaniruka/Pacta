import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userA = 'user-a';
const _userB = 'user-b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('自动上传开关默认关闭，并按用户分别保存', () async {
    const preference = CloudAutoUploadPreference();
    expect(await preference.load(_userA), isFalse);
    await preference.save(_userA, true);
    expect(await preference.load(_userA), isTrue);
    expect(await preference.load(_userB), isFalse);
    await preference.save(_userA, false);
    expect(await preference.load(_userA), isFalse);
  });

  test('待上传意图与已发出请求跨实例保留，并按用户隔离', () async {
    const store = SharedPreferencesCloudAutoUploadQueueStore();
    expect((await store.load(_userA)).hasWork, isFalse);

    final intentAt = DateTime.utc(2026, 11, 13, 12);
    await store.save(
      _userA,
      const CloudAutoUploadQueue().recordIntent(intentAt),
    );
    final reloaded = const SharedPreferencesCloudAutoUploadQueueStore();
    final intent = await reloaded.load(_userA);
    expect(intent.pending, isTrue);
    expect(intent.requestedAt, intentAt);
    expect(intent.request, isNull);
    expect((await reloaded.load(_userB)).pending, isFalse);

    final attempt = CloudAutoUploadAttempt(
      requestId: 'request-1',
      fingerprint: 'v2:0000000000000001',
      expectedRevision: 4,
      startedAt: DateTime.utc(2026, 11, 13, 12, 1),
      attempted: true,
      payload: const {
        'schemaVersion': 1,
        'userId': _userA,
        'tables': {
          'local_goals': [
            {'id': 'goal-1', 'title': '离线确认'},
          ],
        },
      },
      rowCount: 1,
      dataUpdatedAt: DateTime.utc(2026, 11, 13, 11, 59),
    );
    await reloaded.save(
      _userA,
      (await reloaded.load(_userA)).startRequest(attempt),
    );
    final started = await reloaded.load(_userA);
    expect(started.pending, isFalse);
    expect(started.request!.requestId, 'request-1');
    expect(started.request!.expectedRevision, 4);
    expect(started.request!.attempted, isTrue);
    expect(started.request!.payload['userId'], _userA);
    expect(started.request!.fingerprint, attempt.fingerprint);
    expect(started.request!.rowCount, 1);
  });

  test('重复意图合并为一条，阻塞原因保留到明确清除', () async {
    var queue = const CloudAutoUploadQueue()
        .recordIntent(DateTime.utc(2026, 11, 13, 8))
        .recordIntent(DateTime.utc(2026, 11, 13, 9));
    expect(queue.pending, isTrue);
    expect(queue.requestedAt, DateTime.utc(2026, 11, 13, 8));

    queue = queue.block('云端有新版本');
    expect(queue.hasWork, isTrue);
    expect(queue.blockedReason, '云端有新版本');

    final attempt = CloudAutoUploadAttempt(
      requestId: 'request-2',
      fingerprint: 'v2:0000000000000002',
      expectedRevision: 0,
      startedAt: DateTime.utc(2026, 11, 13, 9, 1),
      attempted: true,
      payload: const {'schemaVersion': 1, 'userId': _userA, 'tables': {}},
      rowCount: 0,
      dataUpdatedAt: DateTime.utc(2026, 11, 13, 9),
    );
    expect(queue.startRequest(attempt).request, attempt);
    expect(queue.startRequest(attempt).pending, isFalse);
    expect(queue.startRequest(attempt).blockedReason, '云端有新版本');
    expect(queue.clearRequest().request, isNull);
    expect(queue.clearRequest().pending, isTrue);
    expect(queue.reset().hasWork, isFalse);
    expect(queue.reset().blockedReason, isNull);
  });

  test('损坏或非对象内容按空队列处理，不抛类型错误', () async {
    SharedPreferences.setMockInitialValues({
      'pacta.device.cloud_auto_upload.queue.$_userA': '{"pending": "yes"}',
      'pacta.device.cloud_auto_upload.queue.$_userB': '[1,2,3]',
    });
    const store = SharedPreferencesCloudAutoUploadQueueStore();
    expect((await store.load(_userA)).hasWork, isFalse);
    expect((await store.load(_userB)).hasWork, isFalse);
  });

  test('清空后不再保留该用户的键', () async {
    const store = SharedPreferencesCloudAutoUploadQueueStore();
    await store.save(
      _userA,
      const CloudAutoUploadQueue().recordIntent(DateTime.utc(2026, 11, 13)),
    );
    await store.clear(_userA);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('pacta.device.cloud_auto_upload.queue.$_userA'),
      isNull,
    );
  });
}
