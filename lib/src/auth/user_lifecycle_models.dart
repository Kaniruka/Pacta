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

class ManagedUserLifecycle {
  const ManagedUserLifecycle({
    required this.userId,
    required this.email,
    required this.createdAt,
    required this.isSuspended,
    required this.isEligibleForPurge,
    this.suspendedAt,
    this.restoredAt,
    this.purgeEligibleAt,
  });

  final String userId;
  final String? email;
  final DateTime createdAt;
  final bool isSuspended;
  final DateTime? suspendedAt;
  final DateTime? restoredAt;
  final DateTime? purgeEligibleAt;
  final bool isEligibleForPurge;

  factory ManagedUserLifecycle.fromJson(Map<String, dynamic> json) =>
      ManagedUserLifecycle(
        userId: json['user_id'] as String,
        email: json['email'] as String?,
        createdAt:
            _dateTimeFromJson(json['created_at']) ?? DateTime.now().toUtc(),
        isSuspended: json['is_suspended'] as bool? ?? false,
        suspendedAt: _dateTimeFromJson(json['suspended_at']),
        restoredAt: _dateTimeFromJson(json['restored_at']),
        purgeEligibleAt: _dateTimeFromJson(json['purge_eligible_at']),
        isEligibleForPurge: json['is_eligible_for_purge'] as bool? ?? false,
      );
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.parse(value).toUtc();
}
