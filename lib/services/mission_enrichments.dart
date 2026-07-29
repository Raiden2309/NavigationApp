import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import 'directions_service.dart';
import 'location_service.dart';
import 'mission_clock.dart';
import 'mission_engine.dart';

/// Interface for [MissionEngine] features needed by [MissionEnrichments].
abstract class EngineDelegate {
  RoutePlan get plan;
  List<MissionPoint> get routeOrder;
  List<MissionPoint> get destinations;
  GeoPoint? get operatorPosition;
  MissionStatus get status;
  bool get isRunning;
  bool get optimizeOrder;
  MissionClock get clock;
  double get arrivalRadiusMeters;
  Duration get reoptimizeInterval;
  DirectionsService get directionsService;
  LocationService get locationService;
  bool get enrichmentsIsReplanning;
  bool get enrichmentsPlanFailed;
  DateTime? get missionCompletionEta;
  Future<void> enrichmentsReplan();
  void applyDeviationRoute(RoutePlan plan, List<MissionPoint> routeOrder);
  void enrichmentNotify();
}

/// Optional add-on for [EngineDelegate] that provides:
/// - Periodic re-optimization of the remaining route against live traffic
/// - Route deviation detection and auto-re-route
///
/// These are Mission-Control dispatching features, not core operator-flow
/// features.
class MissionEnrichments {
  MissionEnrichments({required this.delegate});

  /// The engine this enrichments instance is bound to.
  final EngineDelegate delegate;

  DateTime? _lastReoptimizedAt;
  bool _lastReoptimizeChangedOrder = false;
  Duration _lastReoptimizeSaving = Duration.zero;
  int _reoptimizeBackoff = 1;
  int _plannedRemainingDriveTimeSeconds = 0;
  final double _routeDeviationThresholdMeters = 200;
  final Duration _routeDeviationEtaThreshold = const Duration(minutes: 10);
  bool _hasRouteDeviationNotification = false;
  String? _routeDeviationMessage;
  bool _deviationCheckInProgress = false;

  DateTime? get lastReoptimizedAt => _lastReoptimizedAt;
  bool get lastReoptimizeChangedOrder => _lastReoptimizeChangedOrder;
  Duration get lastReoptimizeSaving => _lastReoptimizeSaving;
  bool get hasRouteDeviationNotification => _hasRouteDeviationNotification;
  String? get routeDeviationMessage => _routeDeviationMessage;

  void dismissRouteDeviationNotification() {
    _hasRouteDeviationNotification = false;
    _routeDeviationMessage = null;
    delegate.enrichmentNotify();
  }

  void onRefresh() {
    _reoptimizeIfDue();
    _checkRouteDeviation();
  }

  void onMissionStarted() {
    _lastReoptimizedAt = delegate.clock.now();
  }

  void onPlanUpdated() {
    _plannedRemainingDriveTimeSeconds = delegate.plan.totalDrivingTime.inSeconds;
  }

  void _reoptimizeIfDue() {
    if (!delegate.isRunning || delegate.enrichmentsIsReplanning || delegate.routeOrder.isEmpty) return;
    if (delegate.reoptimizeInterval <= Duration.zero) return;
    final last = _lastReoptimizedAt;
    final now = delegate.clock.now();
    if (last != null && now.difference(last) < delegate.reoptimizeInterval * _reoptimizeBackoff) return;
    _lastReoptimizedAt = now;
    unawaited(_reoptimize());
  }

  Future<void> _reoptimize() async {
    final previousOrder = [for (final point in delegate.routeOrder) point.id];
    final previousEta = delegate.missionCompletionEta;
    await delegate.enrichmentsReplan();
    _reoptimizeBackoff = delegate.enrichmentsPlanFailed
        ? math.min(_reoptimizeBackoff * 2, 16)
        : 1;
    _lastReoptimizedAt = delegate.clock.now();
    _lastReoptimizeChangedOrder =
        !listEquals(previousOrder, [for (final point in delegate.routeOrder) point.id]);
    final eta = delegate.missionCompletionEta;
    _lastReoptimizeSaving =
        previousEta == null || eta == null ? Duration.zero : previousEta.difference(eta);
    delegate.enrichmentNotify();
  }

  void _checkRouteDeviation() {
    if (!delegate.isRunning || delegate.routeOrder.isEmpty) return;
    if (_hasRouteDeviationNotification || _deviationCheckInProgress) return;
    final position = delegate.operatorPosition;
    if (position == null) return;

    final routePolyline = delegate.plan.fullPolyline;
    if (routePolyline.length < 2) return;

    final distanceFrom = distanceFromPath(routePolyline, position);
    if (distanceFrom > _routeDeviationThresholdMeters) {
      unawaited(_handleRouteDeviation(position));
    }
  }

  Future<void> _handleRouteDeviation(GeoPoint position) async {
    _deviationCheckInProgress = true;
    final pending = delegate.destinations.where((p) => !p.isCompleted).toList();
    if (pending.isEmpty) {
      _deviationCheckInProgress = false;
      return;
    }

    try {
      final deviationPlan = await delegate.directionsService.optimizedRoute(
        origin: position,
        destinations: [for (final p in pending) p.location],
        departureTime: delegate.clock.now(),
        dwellTimes: [for (final p in pending) p.dwellTime],
        optimizeOrder: delegate.optimizeOrder,
      );

      final newEtaSeconds = deviationPlan.totalDrivingTime.inSeconds;
      final diffSeconds = newEtaSeconds - _plannedRemainingDriveTimeSeconds;

      if (diffSeconds >= _routeDeviationEtaThreshold.inSeconds) {
        final placed = [
          for (final index in deviationPlan.waypointOrder)
            if (index >= 0 && index < pending.length) pending[index],
        ];
        delegate.applyDeviationRoute(deviationPlan, placed);

        final extraMinutes = (diffSeconds / 60).round();
        _hasRouteDeviationNotification = true;
        _routeDeviationMessage =
            'Driver deviated from planned route. ETA increased by $extraMinutes min.';
        _plannedRemainingDriveTimeSeconds = newEtaSeconds;
        delegate.enrichmentNotify();
      }
    } catch (_) {
    } finally {
      _deviationCheckInProgress = false;
    }
  }
}
