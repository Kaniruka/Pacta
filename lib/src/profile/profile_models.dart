import 'avatar_image.dart';

/// The account-level identity shown on the My page.
///
/// The display name and avatar are deliberately separate from the business
/// snapshot: restoring a snapshot never rewinds them. [hasPendingSave] and
/// [syncError] describe only this device's last account write.
class ProfileAccount {
  const ProfileAccount({
    required this.userId,
    this.displayName = '',
    this.avatar,
    this.updatedAt,
    this.hasPendingSave = false,
    this.syncError,
    this.editSequence = 0,
  });

  final String userId;
  final String displayName;
  final ProfileAvatar? avatar;
  final DateTime? updatedAt;

  /// A local edit that the account store has not accepted yet.
  final bool hasPendingSave;

  /// The last account write or read failure, cleared by a successful retry.
  final String? syncError;

  /// Local payload revision. A network result may only be committed while this
  /// value is unchanged, so a late response never overwrites a newer edit.
  final int editSequence;

  bool get hasDisplayName => displayName.isNotEmpty;

  String get effectiveDisplayName => hasDisplayName ? displayName : '当前用户';

  ProfileAccount copyWith({
    String? displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
    DateTime? updatedAt,
    bool? hasPendingSave,
    String? syncError,
    bool clearSyncError = false,
    int? editSequence,
  }) => ProfileAccount(
    userId: userId,
    displayName: displayName ?? this.displayName,
    avatar: clearAvatar ? null : (avatar ?? this.avatar),
    updatedAt: updatedAt ?? this.updatedAt,
    hasPendingSave: hasPendingSave ?? this.hasPendingSave,
    syncError: clearSyncError ? null : (syncError ?? this.syncError),
    editSequence: editSequence ?? this.editSequence,
  );
}
