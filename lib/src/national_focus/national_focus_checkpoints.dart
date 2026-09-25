const nationalFocusCheckpointUtcHour = 20;
const nationalFocusCheckpointPeriod = Duration(days: 1);

/// Returns the fixed 20:00 UTC instant that most recently occurred.
///
/// This is the same instant as 04:00 on the following calendar day in Beijing.
DateTime nationalFocusCheckpointAtOrBefore(DateTime instant) {
  final utc = instant.toUtc();
  final todayAtCheckpoint = DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    nationalFocusCheckpointUtcHour,
  );
  return todayAtCheckpoint.isAfter(utc)
      ? todayAtCheckpoint.subtract(nationalFocusCheckpointPeriod)
      : todayAtCheckpoint;
}

/// Returns the next fixed checkpoint, strictly after [instant].
DateTime nextNationalFocusCheckpoint(DateTime instant) =>
    nationalFocusCheckpointAtOrBefore(instant)
        .add(nationalFocusCheckpointPeriod);
