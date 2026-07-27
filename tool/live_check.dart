// Smoke-checks the real Google APIs with a key from the environment:
//
//   GOOGLE_MAPS_API_KEY=... dart run tool/live_check.dart
//
// Prints the optimized order, per-leg traffic-aware durations and the
// predicted departure time each leg was priced for.
import 'dart:io';

import 'package:mission_router/services/directions_service.dart';
import 'package:mission_router/services/places_service.dart';

Future<void> main() async {
  final key = Platform.environment['GOOGLE_MAPS_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set GOOGLE_MAPS_API_KEY');
    exit(1);
  }

  final places = GooglePlacesService(apiKey: key);
  final directions = GoogleDirectionsService(apiKey: key);

  final suggestions = await places.search('Jurong Port Singapore');
  stdout.writeln('Autocomplete: ${suggestions.map((s) => s.title).toList()}');
  final origin = await places.resolve(suggestions.first);
  stdout.writeln('Origin: ${origin?.name} ${origin?.address} ${origin?.location}');

  final destinations = [
    singaporeLandmarks[3].location,
    singaporeLandmarks[4].location,
    singaporeLandmarks[6].location,
  ];

  for (final scenario in {
    'now': DateTime.now().add(const Duration(minutes: 1)),
    'tomorrow 18:00 Singapore time': _nextWeekdayAt(18),
  }.entries) {
    final plan = await directions.optimizedRoute(
      origin: origin?.location ?? singaporeLandmarks[0].location,
      destinations: destinations,
      departureTime: scenario.value,
      dwellTimes: const [Duration(minutes: 15), Duration(minutes: 15), Duration(minutes: 15)],
    );
    stdout.writeln('\n--- departing ${scenario.key} (${scenario.value}) ---');
    stdout.writeln('order: ${plan.waypointOrder}');
    for (final leg in plan.legs) {
      stdout.writeln('  leg ${(leg.distanceMeters / 1000).toStringAsFixed(1)} km  '
          'traffic ${leg.duration.inMinutes} min  '
          'free flow ${leg.freeFlowDuration.inMinutes} min  '
          'departs ${leg.departureTime}');
    }
    stdout.writeln('total ${plan.totalDrivingTime.inMinutes} min '
        '(+${plan.totalTrafficDelay.inMinutes} min traffic)');
  }
}

/// The next weekday at [hour] Singapore time (UTC+8), where the demo stops are.
DateTime _nextWeekdayAt(int hour) {
  var day = DateTime.now().toUtc().add(const Duration(days: 1));
  while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime.utc(day.year, day.month, day.day, hour - 8);
}
