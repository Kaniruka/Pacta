/// 含最新份在内保留的成功云备份份数。服务端与客户端共同遵守该上限。
const int cloudSnapshotHistoryLimit = 15;

/// 一份已成功写入的云端备份元数据；列表只读这些字段，不读取整份载荷。
class CloudSnapshotHistoryEntry {
  const CloudSnapshotHistoryEntry({
    required this.revision,
    required this.deviceName,
    required this.rowCount,
    required this.dataUpdatedAt,
    required this.uploadedAt,
    this.deviceManufacturer,
    this.deviceModel,
  });

  final int revision;

  /// 来源标签：Android 为型号加平台，Windows 为设备名加平台。
  final String deviceName;
  final int rowCount;
  final DateTime dataUpdatedAt;
  final DateTime uploadedAt;
  final String? deviceManufacturer;
  final String? deviceModel;
}

/// 恢复在写入任何本机业务数据之前被取消，本机数据保持不变。
class CloudRestoreCancelled implements Exception {
  const CloudRestoreCancelled();

  @override
  String toString() => '恢复已取消，本机数据未替换。';
}
