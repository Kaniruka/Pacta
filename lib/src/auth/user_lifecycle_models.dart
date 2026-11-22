class UserLifecycleStatus {
  const UserLifecycleStatus({
    required this.isSuspended,
    required this.checkedAt,
    this.suspendedAt,
    this.purgeEligibleAt,
    this.isEligibleForPurge = false,
  });

  final bool isSuspended;
  final DateTime? suspendedAt;
  final DateTime? purgeEligibleAt;
  final bool isEligibleForPurge;
  final DateTime checkedAt;

  factory UserLifecycleStatus.fromJson(Map<String, dynamic> json) =>
      UserLifecycleStatus(
        isSuspended: json['is_suspended'] as bool? ?? false,
        suspendedAt: _dateTimeFromJson(json['suspended_at']),
        purgeEligibleAt: _dateTimeFromJson(json['purge_eligible_at']),
        isEligibleForPurge: json['is_eligible_for_purge'] as bool? ?? false,
        checkedAt:
            _dateTimeFromJson(json['checked_at']) ?? DateTime.now().toUtc(),
      );
}

enum UserPurgeStatus { pending, completed }

class UserPurgeReceipt {
  const UserPurgeReceipt({
    required this.userId,
    required this.status,
    this.purgedAt,
  });

  final String userId;
  final UserPurgeStatus status;
  final DateTime? purgedAt;

  bool confirmsPurgedUser(String expectedUserId) =>
      userId == expectedUserId &&
      status == UserPurgeStatus.completed &&
      purgedAt != null;

  factory UserPurgeReceipt.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final statusValue = json['status'];
    if (userId is! String || userId.isEmpty || statusValue is! String) {
      throw const FormatException('清除回执格式无效。');
    }

    final status = switch (statusValue) {
      'pending' => UserPurgeStatus.pending,
      'completed' => UserPurgeStatus.completed,
      _ => throw const FormatException('清除回执状态无效。'),
    };
    final purgedAtValue = json['purged_at'];
    if (purgedAtValue != null && purgedAtValue is! String) {
      throw const FormatException('清除回执时间格式无效。');
    }

    return UserPurgeReceipt(
      userId: userId,
      status: status,
      purgedAt: _dateTimeFromJson(purgedAtValue),
    );
  }
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.parse(value).toUtc();
}
