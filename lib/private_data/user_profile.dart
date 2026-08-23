import 'package:flutter/foundation.dart';
import 'package:pacta/auth/auth_session.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.updatedAt,
  });

  final AppUserId userId;
  final String? displayName;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          userId == other.userId &&
          displayName == other.displayName &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(userId, displayName, updatedAt);

  @override
  String toString() =>
      'UserProfile(userId: $userId, displayName: $displayName, '
      'updatedAt: $updatedAt)';
}
