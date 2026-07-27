import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mission_router/models/geo.dart';
import 'package:mission_router/models/mission.dart';
import 'package:mission_router/services/directions_service.dart';
import 'package:mission_router/services/location_service.dart';
import 'package:mission_router/services/mission_clock.dart';
import 'package:mission_router/services/mission_engine.dart';

class ManualClock implements MissionClock {
  ManualClock(this._now);

  DateTime _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  DateTime now() => _now;

  @override
  double get timeScale => 1;
}

/// Fails route requests until [failures] have been served.
class FlakyDirectionsService implements DirectionsService {
  FlakyDirectionsService(this.failures);

  int failures;
  int calls = 0;
  final DirectionsService _delegate = MockDirectionsService();

  @override
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
    DateTime? departureTime,
    List<Duration> dwellTimes = const [],
    bool optimizeOrder = true,
  }) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw DirectionsException('temporarily unavailable');
    }
    return _delegate.optimizedRoute(
      origin: origin,
      destinations: destinations,
      departureTime: departureTime,
      dwellTimes: dwellTimes,
      optimizeOrder: optimizeOrder,
    );
  }
}

/// Counts how many times the route was requested.
class CountingDirectionsService implements DirectionsService {
  int calls = 0;
  final DirectionsService _delegate = MockDirectionsService();

  @override
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
    DateTime? departureTime,
    List<Duration> dwellTimes = const [],
    bool optimizeOrder = true,
  }) {
    calls++;
    return _delegate.optimizedRoute(
      origin: origin,
      destinations: destinations,
      departureTime: departureTime,
      dwellTimes: dwellTimes,
      optimizeOrder: optimizeOrder,
    );
  }
}

class FakeLocationService implements LocationService {
  final StreamController<OperatorPosition> _controller =
      StreamController<OperatorPosition>.broadcast();
  OperatorPosition? _last;
  bool started = false;

  @override
  Stream<OperatorPosition> get positions => _controller.stream;

  @override
  OperatorPosition? get lastPosition => _last;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;

  Future<void> emit(GeoPoint point, DateTime timestamp) async {
    _last = OperatorPosition(
      point: point,
      speedMetersPerSecond: 10,
      headingDegrees: 0,
      timestamp: timestamp,
    );
    _controller.add(_last!);
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() => _controller.close();
}

void main() {
  const start = GeoPoint(1.2966, 103.7764);
  const pointB = GeoPoint(1.3210, 103.8198);
  const pointC = GeoPoint(1.2644, 103.8220);
  const pointD = GeoPoint(1.3400, 103.7800);

  late ManualClock clock;
  late FakeLocationService location;
  late MissionEngine engine;

  MissionPoint stop(String id, String label, GeoPoint location) =>
      MissionPoint(id: id, label: label, location: location);

  Future<MissionEngine> buildEngine(
    List<MissionPoint> destinations, {
    bool optimizeOrder = true,
  }) async {
    clock = ManualClock(DateTime(2026, 1, 1, 8));
    location = FakeLocationService();
    engine = MissionEngine(
      startingPoint: stop('a', 'Point A', start),
      destinations: destinations,
      directionsService: MockDirectionsService(),
      locationService: location,
      clock: clock,
      refreshInterval: const Duration(hours: 1),
      optimizeOrder: optimizeOrder,
    );
    await engine.initialize();
    return engine;
  }

  tearDown(() {
    engine.dispose();
    location.dispose();
  });

  test('plans an optimized route through every destination', () async {
    await buildEngine([
      stop('b', 'Point B', pointB),
      stop('c', 'Point C', pointC),
      stop('d', 'Point D', pointD),
    ]);

    expect(engine.routeOrder.map((p) => p.id).toSet(), {'b', 'c', 'd'});
    expect(engine.plan.legs, hasLength(3));
    expect(engine.status, MissionStatus.planning);
  });

  test('keeps the customer priority order and queues a new stop last', () async {
    await buildEngine(
      [stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)],
      optimizeOrder: false,
    );
    // Point D is nearest to the start, so an optimizer would pull it forward.
    await engine.addDestination(stop('d', 'Point D', pointD));

    expect(engine.routeOrder.map((p) => p.id), ['b', 'c', 'd']);
    expect(engine.plan.legs.last.destination, pointD);

    await engine.moveDestination('d', -1);
    expect(engine.routeOrder.map((p) => p.id), ['b', 'd', 'c']);

    await engine.setOptimizeOrder(true);
    expect(engine.routeOrder.map((p) => p.id), isNot(['b', 'd', 'c']),
        reason: 'the optimizer takes over once it is switched on');
  });

  test('ETAs stack the 15 minute on-site allowance of every preceding stop', () async {
    await buildEngine([stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)]);
    await engine.start();

    final etas = engine.etas;
    expect(etas, hasLength(2));
    expect(etas.first.departure.difference(etas.first.arrival), defaultDwellTime);
    expect(etas[1].arrival.isAfter(etas.first.departure), isTrue);
    expect(engine.missionCompletionEta, etas.last.departure);
    // Completion allows two 15 minute stops plus driving.
    expect(engine.missionCompletionEta!.difference(clock.now()),
        greaterThan(defaultDwellTime * 2));
  });

  test('arriving within the geofence starts the on-site countdown', () async {
    await buildEngine([stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)]);
    await engine.start();
    final first = engine.currentStop!;

    await location.emit(first.location, clock.now());

    expect(engine.status, MissionStatus.onSite);
    expect(first.status, MissionPointStatus.onSite);
    expect(first.remainingDwell(clock.now()), defaultDwellTime);

    clock.advance(const Duration(minutes: 5));
    expect(first.remainingDwell(clock.now()), const Duration(minutes: 10));
    expect(engine.etas.first.departure, first.arrivedAt!.add(defaultDwellTime));
  });

  test('the dwell timer completes the stop and moves to the next one', () async {
    await buildEngine([stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)]);
    await engine.start();
    final first = engine.currentStop!;

    await location.emit(first.location, clock.now());
    clock.advance(defaultDwellTime);
    await location.emit(first.location, clock.now());
    await Future<void>.delayed(Duration.zero);

    expect(first.status, MissionPointStatus.completed);
    expect(engine.status, MissionStatus.enRoute);
    expect(engine.currentStop!.id, isNot(first.id));
    expect(engine.routeOrder, hasLength(1));
  });

  test('completing tasks early departs before the allowance expires', () async {
    await buildEngine([stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)]);
    await engine.start();
    final first = engine.currentStop!;

    await location.emit(first.location, clock.now());
    clock.advance(const Duration(minutes: 3));
    await engine.completeCurrentStop();

    expect(first.completedAt, clock.now());
    expect(engine.status, MissionStatus.enRoute);
    expect(engine.routeOrder.map((p) => p.id), ['c']);
  });

  test('mission operator edits re-optimize the remaining route', () async {
    await buildEngine([stop('b', 'Point B', pointB)]);
    await engine.start();

    await engine.addDestination(stop('d', 'Point D', pointD));
    expect(engine.routeOrder.map((p) => p.id).toSet(), {'b', 'd'});

    await engine.updateDestination('d', location: const GeoPoint(1.2700, 103.7800), label: 'Point D moved');
    expect(engine.destinations.firstWhere((p) => p.id == 'd').label, 'Point D moved');
    expect(engine.plan.legs, hasLength(2));

    await engine.removeDestination('b');
    expect(engine.routeOrder.map((p) => p.id), ['d']);
  });

  test('a stop being served is never re-ordered away and cannot be removed', () async {
    await buildEngine([stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)]);
    await engine.start();
    final first = engine.currentStop!;
    await location.emit(first.location, clock.now());

    await engine.addDestination(stop('e', 'Point E', const GeoPoint(1.2980, 103.7800)));
    expect(engine.currentStop!.id, first.id);

    await engine.removeDestination(first.id);
    expect(engine.destinations.any((p) => p.id == first.id), isTrue);
  });

  test('re-plans in the background after a routing failure', () async {
    clock = ManualClock(DateTime(2026, 1, 1, 8));
    location = FakeLocationService();
    final directions = FlakyDirectionsService(1);
    engine = MissionEngine(
      startingPoint: stop('a', 'Point A', start),
      destinations: [stop('b', 'Point B', pointB)],
      directionsService: directions,
      locationService: location,
      clock: clock,
      refreshInterval: const Duration(milliseconds: 10),
      planRetryInterval: Duration.zero,
    );
    await engine.initialize();

    expect(engine.routeOrder, isEmpty);
    expect(engine.lastError, isA<DirectionsException>());

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(directions.calls, greaterThan(1));
    expect(engine.routeOrder, hasLength(1));
    expect(engine.lastError, isNull);
  });

  test('re-optimizes the remaining route on its own while driving', () async {
    clock = ManualClock(DateTime(2026, 1, 1, 8));
    location = FakeLocationService();
    final directions = CountingDirectionsService();
    engine = MissionEngine(
      startingPoint: stop('a', 'Point A', start),
      destinations: [stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)],
      directionsService: directions,
      locationService: location,
      clock: clock,
      refreshInterval: const Duration(milliseconds: 10),
      reoptimizeInterval: const Duration(minutes: 10),
    );
    await engine.initialize();
    await engine.start();
    final planned = directions.calls;

    // Not yet due: the mission clock has barely moved.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(directions.calls, planned);
    expect(engine.lastReoptimizedAt, clock.now());

    clock.advance(const Duration(minutes: 11));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(directions.calls, greaterThan(planned));
    expect(engine.lastReoptimizedAt, clock.now());
    expect(engine.routeOrder, hasLength(2));
  });

  test('a position past the stop still counts as an arrival', () async {
    await buildEngine([stop('b', 'Point B', pointB), stop('c', 'Point C', pointC)]);
    await engine.start();
    final first = engine.currentStop!;

    // A coarse GPS fix (or a fast simulated tick) lands well beyond the stop
    // instead of inside its 40 m geofence.
    await location.emit(
      GeoPoint(first.location.latitude + 0.01, first.location.longitude + 0.01),
      clock.now(),
    );

    expect(engine.status, MissionStatus.onSite);
    expect(first.status, MissionPointStatus.onSite);
  });

  test('the mission finishes once the last stop is served', () async {
    await buildEngine([stop('b', 'Point B', pointB)]);
    await engine.start();

    await location.emit(pointB, clock.now());
    await engine.completeCurrentStop();

    expect(engine.status, MissionStatus.completed);
    expect(engine.routeOrder, isEmpty);
    expect(engine.missionCompletionEta, isNull);
  });
}
