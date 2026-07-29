import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mission_router/models/geo.dart';
import 'package:mission_router/models/mission.dart';
import 'package:mission_router/services/directions_service.dart';
import 'package:mission_router/services/location_service.dart';
import 'package:mission_router/services/mission_clock.dart';
import 'package:mission_router/services/mission_engine.dart';
import 'package:mission_router/services/places_service.dart';
import 'package:mission_router/ui/mission_screen.dart';

class _ManualClock implements MissionClock {
  _ManualClock(this._now);

  DateTime _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  DateTime now() => _now;

  @override
  double get timeScale => 1;
}

class _SilentLocationService extends LocationService {
  _SilentLocationService();

  @override
  OperatorPosition? get lastPosition => null;

  @override
  Stream<OperatorPosition> get positions => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('renders the operator view with live ETAs', (tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const start = GeoPoint(1.2966, 103.7764);
  final location = _SilentLocationService();
  final engine = MissionEngine(
    startingPoint: MissionPoint(id: 'a', label: 'Point A', location: start),
    destinations: [
      MissionPoint(id: 'b', label: 'Point B', location: const GeoPoint(1.3210, 103.8198)),
      MissionPoint(id: 'c', label: 'Point C', location: const GeoPoint(1.2644, 103.8220)),
    ],
    directionsService: MockDirectionsService(),
    locationService: location,
    clock: _ManualClock(DateTime(2026, 1, 1, 8)),
    refreshInterval: const Duration(hours: 1),
  );

  await engine.initialize();

  await tester.pumpWidget(MaterialApp(
    home: MissionScreen(engine: engine, places: const MockPlacesService()),
  ));

  await tester.pumpAndSettle(const Duration(seconds: 10));

  expect(find.text('Mission Router'), findsOneWidget);
  expect(find.text('Mission completion ETA'), findsOneWidget);
  expect(find.text('Start Mission'), findsOneWidget);
  expect(find.text('Next stop'), findsOneWidget);
  expect(find.text('Mission Control'), findsOneWidget);

  engine.dispose();
  });
}
