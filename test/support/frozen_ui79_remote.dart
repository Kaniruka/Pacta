import 'package:pacta/src/sync/cloud_snapshot_repository.dart';

// Keep widget and device presentation fixtures on the same cloud timestamp.
class FrozenUi79Remote extends InMemoryCloudSnapshotRemote {
  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    final value = await super.inspect(userId: userId);
    if (value == null) return null;
    return CloudSnapshotMetadata(
      revision: value.revision,
      deviceId: value.deviceId,
      deviceName: value.deviceName,
      dataUpdatedAt: value.dataUpdatedAt,
      uploadedAt: DateTime(2026, 11, 12, 10, 30),
      rowCount: value.rowCount,
      payload: value.payload,
      deviceManufacturer: value.deviceManufacturer,
      deviceModel: value.deviceModel,
    );
  }
}
