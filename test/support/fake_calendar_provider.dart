import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';

class FakeCalendarProvider implements CalendarProvider {
  FakeCalendarProvider({
    required this.sources,
    required this.permission,
    this.events = const [],
    this.supported = true,
    this.failPermissionCheck = false,
    this.failSourceListing = false,
  });

  factory FakeCalendarProvider.unsupported() => FakeCalendarProvider(
    sources: const [],
    permission: CalendarPermissionState.unsupported,
    supported: false,
  );

  final List<CalendarSource> sources;
  CalendarPermissionState permission;
  List<CalendarEventOccurrence> events;
  final bool supported;
  bool failPermissionCheck;
  bool failSourceListing;
  final Set<String> failingReadSourceIds = {};

  @override
  bool get isSupported => supported;

  @override
  Future<CalendarPermissionState> requestPermission() async => permission;

  @override
  Future<CalendarPermissionState> permissionStatus() async {
    if (failPermissionCheck) throw StateError('Permission state unavailable.');
    return permission;
  }

  @override
  Future<List<CalendarSource>> listCalendars() async {
    if (failSourceListing) {
      throw StateError('Calendar source list unavailable.');
    }
    return sources;
  }

  @override
  Future<List<CalendarEventOccurrence>> readEvents({
    required Set<String> sourceIds,
    required DateTime from,
    required DateTime to,
  }) async => await _readEvents(sourceIds);

  Future<List<CalendarEventOccurrence>> _readEvents(
    Set<String> sourceIds,
  ) async {
    if (sourceIds.any(failingReadSourceIds.contains)) {
      throw StateError('Calendar event query failed.');
    }
    return events.where((event) => sourceIds.contains(event.sourceId)).toList();
  }
}
