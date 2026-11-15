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
    this.displayTimeZoneId,
    this.updatedAt,
    this.hasPendingSave = false,
    this.syncError,
    this.editSequence = 0,
    this.pendingTimeZoneUpload = false,
  });

  final String userId;
  final String displayName;
  final ProfileAvatar? avatar;

  /// The account display time zone (IANA identifier), shared by every device.
  ///
  /// Null means the account has not recorded one yet; display then uses the
  /// fixed account-empty fallback instead of the device zone. It travels with
  /// the account profile and is never part of the business snapshot.
  final String? displayTimeZoneId;
  final DateTime? updatedAt;

  /// A local edit that the account store has not accepted yet.
  final bool hasPendingSave;

  /// The last account write or read failure, cleared by a successful retry.
  final String? syncError;

  /// Local payload revision. A network result may only be committed while this
  /// value is unchanged, so a late response never overwrites a newer edit.
  final int editSequence;

  /// True when this device's display time zone changed locally and the account
  /// store has not accepted it yet. Nickname/avatar saves omit the zone unless
  /// this is set, so a stale cached zone never replaces an account value that
  /// another device wrote later.
  final bool pendingTimeZoneUpload;

  bool get hasDisplayName => displayName.isNotEmpty;

  String get effectiveDisplayName => hasDisplayName ? displayName : '当前用户';

  bool get hasDisplayTimeZoneId => displayTimeZoneId != null;

  ProfileAccount copyWith({
    String? displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
    String? displayTimeZoneId,
    DateTime? updatedAt,
    bool? hasPendingSave,
    String? syncError,
    bool clearSyncError = false,
    int? editSequence,
    bool? pendingTimeZoneUpload,
  }) => ProfileAccount(
    userId: userId,
    displayName: displayName ?? this.displayName,
    avatar: clearAvatar ? null : (avatar ?? this.avatar),
    displayTimeZoneId: displayTimeZoneId ?? this.displayTimeZoneId,
    updatedAt: updatedAt ?? this.updatedAt,
    hasPendingSave: hasPendingSave ?? this.hasPendingSave,
    syncError: clearSyncError ? null : (syncError ?? this.syncError),
    editSequence: editSequence ?? this.editSequence,
    pendingTimeZoneUpload: pendingTimeZoneUpload ?? this.pendingTimeZoneUpload,
  );
}
