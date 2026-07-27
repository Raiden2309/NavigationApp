import 'geo.dart';

/// Default on-site allowance for unloading, loading and other tasks.
const Duration defaultDwellTime = Duration(minutes: 15);

enum MissionPointStatus { pending, enRoute, onSite, completed }

/// A stop on the mission. Point A is the starting point, every later point is
/// a destination the mission operator can add, move or remove.
class MissionPoint {
  MissionPoint({
    required this.id,
    required this.label,
    required this.location,
    this.dwellTime = defaultDwellTime,
    this.status = MissionPointStatus.pending,
    this.arrivedAt,
    this.completedAt,
  });

  final String id;
  String label;
  GeoPoint location;
  Duration dwellTime;
  MissionPointStatus status;
  DateTime? arrivedAt;
  DateTime? completedAt;

  bool get isCompleted => status == MissionPointStatus.completed;

  /// Dwell time still to be served, given [now].
  Duration remainingDwell(DateTime now) {
    if (status == MissionPointStatus.completed) return Duration.zero;
    final arrival = arrivedAt;
    if (status != MissionPointStatus.onSite || arrival == null) return dwellTime;
    final served = now.difference(arrival);
    final remaining = dwellTime - served;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  MissionPoint copyWith({String? label, GeoPoint? location, Duration? dwellTime}) => MissionPoint(
        id: id,
        label: label ?? this.label,
        location: location ?? this.location,
        dwellTime: dwellTime ?? this.dwellTime,
        status: status,
        arrivedAt: arrivedAt,
        completedAt: completedAt,
      );
}

/// One optimized leg between two consecutive stops.
class RouteLeg {
  const RouteLeg({
    required this.origin,
    required this.destination,
    required this.distanceMeters,
    required this.duration,
    required this.polyline,
  });

  final GeoPoint origin;
  final GeoPoint destination;
  final double distanceMeters;
  final Duration duration;
  final List<GeoPoint> polyline;
}

/// The result of asking the directions provider for the best route through a
/// set of stops.
class RoutePlan {
  const RoutePlan({required this.waypointOrder, required this.legs});

  /// Indices into the requested destination list, in the optimized visiting
  /// order. Empty when there is nothing left to visit.
  final List<int> waypointOrder;

  /// One leg per hop, starting at the origin. `legs.length == waypointOrder.length`.
  final List<RouteLeg> legs;

  static const RoutePlan empty = RoutePlan(waypointOrder: [], legs: []);

  bool get isEmpty => legs.isEmpty;

  double get totalDistanceMeters =>
      legs.fold(0.0, (sum, leg) => sum + leg.distanceMeters);

  Duration get totalDrivingTime =>
      legs.fold(Duration.zero, (sum, leg) => sum + leg.duration);

  List<GeoPoint> get fullPolyline => [for (final leg in legs) ...leg.polyline];
}
