import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class FocusTimeZones {
  FocusTimeZones._();

  static bool _isInitialized = false;

  static void initialize() {
    if (_isInitialized) return;
    timezone_data.initializeTimeZones();
    _isInitialized = true;
  }

  static List<String> get identifiers {
    initialize();
    return List.unmodifiable(timezone.timeZoneDatabase.locations.keys);
  }

  static bool contains(String identifier) {
    initialize();
    return timezone.timeZoneDatabase.locations.containsKey(identifier);
  }

  static timezone.Location location(String identifier) {
    initialize();
    return timezone.getLocation(identifier);
  }
}
