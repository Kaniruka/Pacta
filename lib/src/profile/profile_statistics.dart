import '../focus/focus_models.dart';
import '../focus/focus_statistics.dart';
import '../national_focus/national_focus_models.dart';

/// The four numbers shown on the My-page name card.
///
/// The two national-focus figures come from the retained card records; the two
/// focus figures reuse the accepted-settlement projections instead of inventing
/// a second time basis. Internalization never changes settlement, it only
/// classifies an existing successful-day total.
class ProfileStatistics {
  const ProfileStatistics({
    required this.litCardCount,
    required this.internalizedCardCount,
    required this.completedFocusCount,
    required this.effectiveFocusSeconds,
  });

  static const empty = ProfileStatistics(
    litCardCount: 0,
    internalizedCardCount: 0,
    completedFocusCount: 0,
    effectiveFocusSeconds: 0,
  );

  /// Lit cards that are still in the tree and not deleted.
  final int litCardCount;

  /// Non-deleted cards whose accumulated successful national-focus days
  /// reached the internalization threshold, from every card including the
  /// library.
  final int internalizedCardCount;

  /// Accepted focus sessions that reached the completed outcome.
  final int completedFocusCount;

  /// Effective focus time of every accepted settled session, including failed
  /// outcomes that still contributed reliable effective intervals.
  final int effectiveFocusSeconds;
}

ProfileStatistics computeProfileStatistics({
  required Iterable<NationalFocusCard> cards,
  required Iterable<FocusSession> sessions,
}) {
  var litCardCount = 0;
  var internalizedCardCount = 0;
  for (final card in cards) {
    if (card.isDeleted) continue;
    if (card.isInTree && card.state == NationalFocusCardState.lit) {
      litCardCount++;
    }
    if (card.isInternalized) internalizedCardCount++;
  }

  var completedFocusCount = 0;
  for (final session in sessions) {
    if (session.status != FocusSessionStatus.completed) continue;
    if (!session.reviewDisposition.contributesToFocusProgress) continue;
    completedFocusCount++;
  }

  final effectiveFocusSeconds = focusStatisticsByMode(sessions).values
      .fold<int>(0, (total, mode) => total + mode.totalDurationSeconds);

  return ProfileStatistics(
    litCardCount: litCardCount,
    internalizedCardCount: internalizedCardCount,
    completedFocusCount: completedFocusCount,
    effectiveFocusSeconds: effectiveFocusSeconds,
  );
}
