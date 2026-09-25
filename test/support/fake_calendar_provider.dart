import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';

class FakeCalendarProvider implements CalendarProvider {
  FakeCalendarProvider({
    required this.sources,
    required this.permission,
    this.events = const [],
    this.supported = true,
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

  @override
  bool get isSupported => supported;

  @override
  Future<CalendarPermissionState> requestPermission() async => permission;

  @override
  Future<CalendarPermissionState> permissionStatus() async => permission;

  @override
  Future<List<CalendarSource>> listCalendars() async => sources;

  @override
  Future<List<CalendarEventOccurrence>> readEvents({
    required Set<String> sourceIds,
    required DateTime from,
    required DateTime to,
  }) async =>
      events.where((event) => sourceIds.contains(event.sourceId)).toList();
}
