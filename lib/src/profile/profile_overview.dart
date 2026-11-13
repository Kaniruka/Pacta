import 'dart:async';

import '../focus/focus_models.dart';
import '../focus/focus_repository.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import 'profile_statistics.dart';

/// Reads the retained records behind the My-page statistics.
///
/// Kept as its own seam so the card and the detail pages depend on records they
/// show, not on the two feature repositories at once.
abstract interface class ProfileOverviewSource {
  /// Every non-deleted card, from the tree and the library.
  Stream<List<NationalFocusCard>> watchCards();

  Stream<List<FocusSession>> watchSessions();
}

class RepositoryProfileOverviewSource implements ProfileOverviewSource {
  const RepositoryProfileOverviewSource({
    required NationalFocusRepository nationalFocusRepository,
    required FocusRepository focusRepository,
  }) : _nationalFocus = nationalFocusRepository,
       _focus = focusRepository;

  final NationalFocusRepository _nationalFocus;
  final FocusRepository _focus;

  @override
  Stream<List<NationalFocusCard>> watchCards() => combineLatest2(
    _nationalFocus.watchTreeCards(),
    _nationalFocus.watchLibraryCards(),
    (tree, library) => [...tree, ...library],
  );

  @override
  Stream<List<FocusSession>> watchSessions() => _focus.watchSessions();
}

/// Emits once both sources produced a value and after every later update.
///
/// The result closes when either input closes, and forwards the first error of
/// either input so the caller can show a failed state instead of stale zeroes.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A first, B second) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? firstSubscription;
  StreamSubscription<B>? secondSubscription;
  A? latestFirst;
  B? latestSecond;
  var hasFirst = false;
  var hasSecond = false;
  var closed = false;

  void emit() {
    if (!hasFirst || !hasSecond || closed) return;
    controller.add(combine(latestFirst as A, latestSecond as B));
  }

  Future<void> finish() async {
    if (closed) return;
    closed = true;
    await firstSubscription?.cancel();
    await secondSubscription?.cancel();
    await controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      firstSubscription = first.listen(
        (value) {
          latestFirst = value;
          hasFirst = true;
          emit();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (closed) return;
          closed = true;
          controller.addError(error, stackTrace);
          finish();
        },
        onDone: finish,
      );
      secondSubscription = second.listen(
        (value) {
          latestSecond = value;
          hasSecond = true;
          emit();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (closed) return;
          closed = true;
          controller.addError(error, stackTrace);
          finish();
        },
        onDone: finish,
      );
    },
    onCancel: () async {
      closed = true;
      await firstSubscription?.cancel();
      await secondSubscription?.cancel();
    },
  );
  return controller.stream;
}

/// Statistics derived from one retained-record snapshot.
ProfileStatistics statisticsForOverview({
  required Iterable<NationalFocusCard> cards,
  required Iterable<FocusSession> sessions,
}) => computeProfileStatistics(cards: cards, sessions: sessions);

/// Cards that occupy the national-focus statistics detail page.
List<NationalFocusCard> litCardsForOverview(
  Iterable<NationalFocusCard> cards,
) => [
  for (final card in cards)
    if (!card.isDeleted &&
        card.isInTree &&
        card.state == NationalFocusCardState.lit)
      card,
];

/// Internalized cards listed on the same detail page.
List<NationalFocusCard> internalizedCardsForOverview(
  Iterable<NationalFocusCard> cards,
) => [
  for (final card in cards)
    if (!card.isDeleted && card.isInternalized) card,
];

/// Accepted completed sessions listed on the focus detail page, newest first.
List<FocusSession> completedSessionsForOverview(
  Iterable<FocusSession> sessions,
) {
  final completed = [
    for (final session in sessions)
      if (session.status == FocusSessionStatus.completed &&
          session.reviewDisposition.contributesToFocusProgress)
        session,
  ];
  completed.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return completed;
}
