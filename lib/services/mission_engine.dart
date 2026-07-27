import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import 'directions_service.dart';
import 'location_service.dart';
import 'mission_clock.dart';

enum MissionStatus { planning, enRoute, onSite, completed }

/// ETA for one stop on the remaining route.
class StopEta {
  const StopEta({
    required this.point,
    required this.arrival,
    required this.departure,
    required this.distanceMeters,
  });

  final MissionPoint point;
  final DateTime arrival;
  final DateTime departure;

  /// Driving distance still to cover before reaching this stop.
  final double distanceMeters;
}

/// Owns mission state: the optimized route, the live operator position, stop
/// progress and the continuously updated ETAs.
class MissionEngine extends ChangeNotifier {
  MissionEngine({
    required this.startingPoint,
    required List<MissionPoint> destinations,
    required DirectionsService directionsService,
    required LocationService locationService,
    MissionClock? clock,
    this.arrivalRadiusMeters = 40,
    this.refreshInterval = const Duration(milliseconds: 500),
    this.planRetryInterval = const Duration(seconds: 10),
    this.reoptimizeInterval = const Duration(minutes: 5),
  })  : _destinations = List.of(destinations),
        _directions = directionsService,
        _location = locationService,
        clock = clock ?? const SystemClock();

  final MissionPoint startingPoint;
  final DirectionsService _directions;
  final LocationService _location;
  final MissionClock clock;
  final double arrivalRadiusMeters;
  final Duration refreshInterval;

  /// Minimum wall-clock gap between attempts to re-plan a mission that has no
  /// route because the last routing request failed.
  final Duration planRetryInterval;

  /// How often a running mission re-quotes the remaining route against current
  /// traffic, re-ordering the stops still to come when that is quicker.
  final Duration reoptimizeInterval;

  final List<MissionPoint> _destinations;
  StreamSubscription<OperatorPosition>? _subscription;
  Timer? _ticker;
  RoutePlan _plan = RoutePlan.empty;
  List<MissionPoint> _routeOrder = const [];
  List<double> _legEndDistances = const [];
  GeoPoint? _operatorPosition;
  MissionStatus _status = MissionStatus.planning;
  bool _replanning = false;
  Object? _lastError;
  bool _planFailed = false;
  DateTime? _lastPlanAttempt;
  Future<void> _planQueue = Future<void>.value();
  DateTime? _lastReoptimizedAt;
  bool _lastReoptimizeChangedOrder = false;
  Duration _lastReoptimizeSaving = Duration.zero;

  /// Every destination after the starting point, in the order the mission
  /// operator entered them.
  List<MissionPoint> get destinations => List.unmodifiable(_destinations);

  /// Remaining stops in optimized visiting order.
  List<MissionPoint> get routeOrder => List.unmodifiable(_routeOrder);

  RoutePlan get plan => _plan;

  MissionStatus get status => _status;

  Object? get lastError => _lastError;

  /// When the remaining route was last re-quoted against live traffic.
  DateTime? get lastReoptimizedAt => _lastReoptimizedAt;

  /// Whether that re-quote changed the visiting order.
  bool get lastReoptimizeChangedOrder => _lastReoptimizeChangedOrder;

  /// How much the last re-quote took off the completion ETA; negative when
  /// traffic has got worse since the previous plan.
  Duration get lastReoptimizeSaving => _lastReoptimizeSaving;

  GeoPoint? get operatorPosition => _operatorPosition;

  MissionPoint? get currentStop => _routeOrder.isEmpty ? null : _routeOrder.first;

  bool get isRunning => _status == MissionStatus.enRoute || _status == MissionStatus.onSite;

  Future<void> initialize() async {
    _operatorPosition = _location.lastPosition?.point ?? startingPoint.location;
    await _replan();
    _subscription = _location.positions.listen(_onPosition, onError: _onLocationError);
    try {
      await _location.start();
    } catch (error) {
      // A denied permission or disabled GPS must not take the mission plan
      // down with it; the operator still sees the route and ETAs.
      _onLocationError(error);
    }
    _ticker ??= Timer.periodic(refreshInterval, (_) => _refresh());
  }

  /// Starts the run from Point A towards the first optimized destination.
  Future<void> start() async {
    if (_routeOrder.isEmpty) return;
    _status = MissionStatus.enRoute;
    _lastReoptimizedAt = clock.now();
    startingPoint.status = MissionPointStatus.completed;
    startingPoint.completedAt ??= clock.now();
    _routeOrder.first.status = MissionPointStatus.enRoute;
    _resumeTravel();
    notifyListeners();
  }

  void pause() {
    if (_status != MissionStatus.enRoute) return;
    _pauseTravel();
    notifyListeners();
  }

  void resume() {
    if (_status != MissionStatus.enRoute) return;
    _resumeTravel();
    notifyListeners();
  }

  /// Marks the on-site tasks as done before the 15 minute allowance expires.
  Future<void> completeCurrentStop() async {
    final stop = currentStop;
    if (stop == null || _status != MissionStatus.onSite) return;
    stop.status = MissionPointStatus.completed;
    stop.completedAt = clock.now();
    await _advance();
  }

  // --- Mission operator edits -------------------------------------------

  Future<void> addDestination(MissionPoint point) async {
    _destinations.add(point);
    await _replan();
    notifyListeners();
  }

  Future<void> updateDestination(
    String id, {
    String? label,
    GeoPoint? location,
    String? address,
    Duration? dwellTime,
  }) async {
    final index = _destinations.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final existing = _destinations[index];
    if (existing.isCompleted) return;
    existing.label = label ?? existing.label;
    existing.location = location ?? existing.location;
    existing.address = address ?? existing.address;
    existing.dwellTime = dwellTime ?? existing.dwellTime;
    await _replan();
    notifyListeners();
  }

  Future<void> removeDestination(String id) async {
    final index = _destinations.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final point = _destinations[index];
    if (point.isCompleted || point.status == MissionPointStatus.onSite) return;
    _destinations.removeAt(index);
    await _replan();
    notifyListeners();
  }

  // --- ETAs --------------------------------------------------------------

  /// Live ETAs for every remaining stop, including the 15 minute on-site
  /// allowance of each preceding stop.
  List<StopEta> get etas {
    final now = clock.now();
    final result = <StopEta>[];
    var cursor = now;
    for (var i = 0; i < _routeOrder.length; i++) {
      final point = _routeOrder[i];
      final onSiteNow = i == 0 && _status == MissionStatus.onSite;
      final arrival = onSiteNow ? (point.arrivedAt ?? now) : cursor.add(_travelTimeForLeg(i));
      final departure = onSiteNow
          ? now.add(point.remainingDwell(now))
          : arrival.add(point.dwellTime);
      result.add(StopEta(
        point: point,
        arrival: arrival,
        departure: departure,
        distanceMeters: _remainingDistanceToLeg(i),
      ));
      cursor = departure;
    }
    return result;
  }

  /// Live ETA for finishing the whole mission, i.e. leaving the last stop.
  DateTime? get missionCompletionEta {
    if (_status == MissionStatus.completed) return null;
    final all = etas;
    return all.isEmpty ? null : all.last.departure;
  }

  Duration get remainingDriveTime => _travelTimeToLeg(_plan.legs.length - 1);

  /// Driving time that traffic adds to the stops still ahead.
  Duration get remainingTrafficDelay => _plan.totalTrafficDelay;

  double get remainingDistanceMeters =>
      _routeOrder.isEmpty ? 0 : _remainingDistanceToLeg(_routeOrder.length - 1);

  // --- Internals ---------------------------------------------------------

  void _onPosition(OperatorPosition position) {
    _operatorPosition = position.point;
    _refresh();
  }

  void _onLocationError(Object error) {
    _lastError = error;
    notifyListeners();
  }

  void _refresh() {
    _retryPlanning();
    _reoptimizeIfDue();
    if (!isRunning) {
      notifyListeners();
      return;
    }
    final stop = currentStop;
    final position = _operatorPosition;
    if (stop != null && position != null && _status == MissionStatus.enRoute) {
      // A fast simulated tick, or a GPS fix that lands after the stop, can skip
      // straight over the geofence, so progress along the leg counts as an
      // arrival too.
      final leg = _currentLegIndex;
      if (position.distanceTo(stop.location) <= arrivalRadiusMeters ||
          (leg >= 0 && _remainingDistanceToLeg(leg) <= arrivalRadiusMeters)) {
        _arriveAt(stop);
      }
    }
    if (_status == MissionStatus.onSite && stop != null) {
      if (stop.remainingDwell(clock.now()) == Duration.zero) {
        stop.status = MissionPointStatus.completed;
        stop.completedAt = clock.now();
        unawaited(_advance());
        return;
      }
    }
    notifyListeners();
  }

  /// A route request can fail transiently (rate limit, a dropped connection),
  /// leaving the operator with no route at all or a stale one, so keep
  /// re-planning in the background until one succeeds.
  void _retryPlanning() {
    if (!_planFailed || _replanning) return;
    if (_destinations.every((p) => p.isCompleted)) return;
    final last = _lastPlanAttempt;
    final now = DateTime.now();
    if (last != null && now.difference(last) < planRetryInterval) return;
    _lastPlanAttempt = now;
    unawaited(_replan().then((_) => notifyListeners()));
  }

  /// Traffic moves while the operator drives, so a running mission keeps
  /// re-quoting the stops still ahead and re-orders them when that is faster.
  void _reoptimizeIfDue() {
    if (!isRunning || _replanning || _routeOrder.isEmpty) return;
    if (reoptimizeInterval <= Duration.zero) return;
    final last = _lastReoptimizedAt;
    final now = clock.now();
    if (last != null && now.difference(last) < reoptimizeInterval) return;
    _lastReoptimizedAt = now;
    unawaited(_reoptimize());
  }

  Future<void> _reoptimize() async {
    final previousOrder = [for (final point in _routeOrder) point.id];
    final previousEta = missionCompletionEta;
    await _replan();
    _lastReoptimizedAt = clock.now();
    _lastReoptimizeChangedOrder =
        !listEquals(previousOrder, [for (final point in _routeOrder) point.id]);
    final eta = missionCompletionEta;
    _lastReoptimizeSaving =
        previousEta == null || eta == null ? Duration.zero : previousEta.difference(eta);
    notifyListeners();
  }

  void _arriveAt(MissionPoint stop) {
    stop.status = MissionPointStatus.onSite;
    stop.arrivedAt = clock.now();
    _status = MissionStatus.onSite;
    _pauseTravel();
  }

  Future<void> _advance() async {
    await _replan();
    if (_routeOrder.isEmpty) {
      _status = MissionStatus.completed;
      _pauseTravel();
    } else {
      _status = MissionStatus.enRoute;
      _routeOrder.first.status = MissionPointStatus.enRoute;
      _resumeTravel();
    }
    notifyListeners();
  }

  /// Recomputes the optimal route through every stop that is still pending,
  /// starting from wherever the operator currently is.
  ///
  /// Re-plans are queued rather than dropped: a background re-optimization
  /// must not swallow the re-plan that follows an edit or a completed stop,
  /// nor land on top of it and undo the new state.
  Future<void> _replan() {
    final run = _planQueue.then((_) => _planOnce());
    _planQueue = run.catchError((Object _) {});
    return run;
  }

  Future<void> _planOnce() async {
    _replanning = true;
    try {
      final pending = _destinations.where((p) => !p.isCompleted).toList();
      final origin = _operatorPosition ?? startingPoint.location;
      if (pending.isEmpty) {
        _plan = RoutePlan.empty;
        _routeOrder = const [];
        _legEndDistances = const [];
        if (_status != MissionStatus.planning) _status = MissionStatus.completed;
        return;
      }

      // A stop that is currently being served stays first; only the rest is
      // re-optimized so the operator is never re-routed mid-task.
      final anchored = pending.firstWhereOrNull((p) => p.status == MissionPointStatus.onSite);
      final optimizable = pending.where((p) => p != anchored).toList();
      final now = clock.now();
      // Driving only resumes once the current stop's tasks are done, so that is
      // the departure time the traffic for the next leg must be priced for.
      final departure = anchored == null ? now : now.add(anchored.remainingDwell(now));
      final plan = await _directions.optimizedRoute(
        origin: anchored?.location ?? origin,
        destinations: [for (final p in optimizable) p.location],
        departureTime: departure,
        dwellTimes: [for (final p in optimizable) p.dwellTime],
      );
      final ordered = [
        ?anchored,
        for (final index in plan.waypointOrder) optimizable[index],
      ];

      if (anchored != null) {
        // Prepend a zero-length leg so legs stay aligned with [ordered].
        _plan = RoutePlan(
          waypointOrder: plan.waypointOrder,
          legs: [
            RouteLeg(
              origin: anchored.location,
              destination: anchored.location,
              distanceMeters: 0,
              duration: Duration.zero,
              polyline: [anchored.location, anchored.location],
            ),
            ...plan.legs,
          ],
        );
      } else {
        _plan = plan;
      }
      _routeOrder = ordered;
      _recomputeLegDistances();
      for (final point in _routeOrder.skip(1)) {
        if (point.status == MissionPointStatus.enRoute) {
          point.status = MissionPointStatus.pending;
        }
      }
      if (isRunning && _routeOrder.isNotEmpty && _status == MissionStatus.enRoute) {
        _routeOrder.first.status = MissionPointStatus.enRoute;
      }
      _followPlan();
      _lastError = null;
      _planFailed = false;
    } catch (error) {
      _lastError = error;
      _planFailed = true;
    } finally {
      _replanning = false;
    }
  }

  void _recomputeLegDistances() {
    final ends = <double>[];
    var cumulative = 0.0;
    for (final leg in _plan.legs) {
      cumulative += leg.distanceMeters;
      ends.add(cumulative);
    }
    _legEndDistances = ends;
  }

  /// Progress along the whole route. Only the leg in progress is projected
  /// onto: matching against the full route would snap the operator onto a
  /// later leg wherever the route drives down the same road twice.
  double _travelledOnPlan() {
    final index = _currentLegIndex;
    if (index < 0) return 0;
    final before = index == 0 ? 0.0 : _legEndDistances[index - 1];
    final position = _operatorPosition;
    final path = _plan.legs[index].polyline;
    if (position == null || path.length < 2) return before;
    return before + distanceAlongPath(path, position);
  }

  double _remainingDistanceToLeg(int legIndex) {
    if (legIndex < 0 || legIndex >= _legEndDistances.length) return 0;
    final remaining = _legEndDistances[legIndex] - _travelledOnPlan();
    return remaining < 0 ? 0 : remaining;
  }

  /// Traffic-aware time left on leg [legIndex] alone: its full duration, or
  /// the pro-rata remainder when the operator is already driving it.
  Duration _travelTimeForLeg(int legIndex) {
    if (legIndex < 0 || legIndex >= _plan.legs.length) return Duration.zero;
    final leg = _plan.legs[legIndex];
    if (leg.distanceMeters <= 0) return Duration.zero;
    final legEnd = _legEndDistances[legIndex];
    final legStart = legEnd - leg.distanceMeters;
    final travelled = _travelledOnPlan();
    if (travelled >= legEnd) return Duration.zero;
    final remaining = legEnd - math.max(travelled, legStart);
    return leg.duration * (remaining / leg.distanceMeters).clamp(0.0, 1.0);
  }

  Duration _travelTimeToLeg(int legIndex) {
    var total = Duration.zero;
    for (var i = 0; i <= legIndex; i++) {
      total += _travelTimeForLeg(i);
    }
    return total;
  }

  /// The leg the operator is driving now: the first one with a real distance,
  /// skipping the zero-length leg that anchors a stop being served.
  int get _currentLegIndex {
    for (var i = 0; i < _plan.legs.length; i++) {
      if (_plan.legs[i].distanceMeters > 0) return i;
    }
    return _plan.legs.isEmpty ? -1 : 0;
  }

  /// Part of the route the operator has already driven, in meters.
  double get travelledDistanceMeters => _travelledOnPlan();

  /// The simulator only ever follows the leg in progress, so it parks at the
  /// next stop instead of driving through it towards the end of the route.
  void _followPlan() {
    final simulator = _location;
    if (simulator is! SimulatedLocationService) return;
    final index = _currentLegIndex;
    if (index < 0) return;
    final path = _plan.legs[index].polyline;
    if (path.length >= 2) simulator.followPath(path);
  }

  void _pauseTravel() {
    final simulator = _location;
    if (simulator is SimulatedLocationService) simulator.pause();
  }

  void _resumeTravel() {
    final simulator = _location;
    if (simulator is SimulatedLocationService) {
      _followPlan();
      simulator.resume();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
