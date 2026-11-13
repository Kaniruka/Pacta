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
/// The output closes when either input closes, and the first error of either
/// input is forwarded before both subscriptions are cancelled and the output
/// completed, so a failed pair never keeps an input listener alive.
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
  var done = false;

  Future<void> terminate({bool closeOutput = true}) async {
    if (done) return;
    done = true;
    final pendingFirst = firstSubscription;
    final pendingSecond = secondSubscription;
    firstSubscription = null;
    secondSubscription = null;
    await pendingFirst?.cancel();
    await pendingSecond?.cancel();
    if (closeOutput && !controller.isClosed) {
      await controller.close();
    }
  }

  void emit() {
    if (!hasFirst || !hasSecond || done) return;
    controller.add(combine(latestFirst as A, latestSecond as B));
  }

  Future<void> fail(Object error, StackTrace stackTrace) async {
    if (done) return;
    controller.addError(error, stackTrace);
    await terminate();
  }

  controller = StreamController<R>(
    onListen: () {
      firstSubscription = first.listen(
        (value) {
          latestFirst = value;
          hasFirst = true;
          emit();
        },
        onError: fail,
        onDone: terminate,
      );
      secondSubscription = second.listen(
        (value) {
          latestSecond = value;
          hasSecond = true;
          emit();
        },
        onError: fail,
        onDone: terminate,
      );
    },
    onCancel: () => terminate(closeOutput: false),
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
