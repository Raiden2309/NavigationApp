import 'geo.dart';

/// Default on-site allowance for unloading, loading and other tasks.
const Duration defaultDwellTime = Duration(minutes: 15);

enum MissionPointStatus { pending, enRoute, onSite, completed }

enum ProofType { checkin, photo, note }

/// A proof artifact captured at a stop: a check-in, photo or note.
class MissionProof {
  MissionProof({
    required this.id,
    required this.type,
    this.fileUrl,
    this.note,
    this.location,
    this.accuracyMeters,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  final String id;
  final ProofType type;

  /// File path or URL for photo proofs.
  final String? fileUrl;

  /// Text content for note proofs.
  final String? note;

  /// Where the proof was captured.
  final GeoPoint? location;

  /// GPS accuracy at the time of capture, in meters.
  final double? accuracyMeters;

  final DateTime capturedAt;
}

/// A stop on the mission. Point A is the starting point, every later point is
/// a destination the mission operator can add, move or remove.
class MissionPoint {
  MissionPoint({
    required this.id,
    required this.label,
    required this.location,
    this.address,
    this.dwellTime = defaultDwellTime,
    this.status = MissionPointStatus.pending,
    this.arrivedAt,
    this.completedAt,
    this.checkedInAt,
    List<MissionProof>? proofs,
  }) : proofs = proofs ?? [];

  final String id;
  String label;
  GeoPoint location;

  /// Human readable address of [location], when it came from a place lookup.
  String? address;

  Duration dwellTime;
  MissionPointStatus status;
  DateTime? arrivedAt;
  DateTime? completedAt;

  /// Manual check-in timestamp, set by the operator when on site.
  DateTime? checkedInAt;

  /// Proof artifacts (photos, notes, check-ins) captured at this stop.
  final List<MissionProof> proofs;

  bool get isCompleted => status == MissionPointStatus.completed;

  bool get checkedIn => checkedInAt != null;

  /// Whether this stop can be completed: all three proof types (check-in,
  /// photo, note) must have been captured.
  bool get canComplete {
    final hasCheckIn = checkedIn;
    final hasPhoto = proofs.any((p) => p.type == ProofType.photo);
    final hasNote = proofs.any((p) => p.type == ProofType.note);
    return hasCheckIn && hasPhoto && hasNote;
  }

  /// Dwell time still to be served, given [now].
  Duration remainingDwell(DateTime now) {
    if (status == MissionPointStatus.completed) return Duration.zero;
    final arrival = arrivedAt;
    if (status != MissionPointStatus.onSite || arrival == null) return dwellTime;
    final served = now.difference(arrival);
    final remaining = dwellTime - served;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  MissionPoint copyWith({
    String? label,
    GeoPoint? location,
    String? address,
    Duration? dwellTime,
  }) =>
      MissionPoint(
        id: id,
        label: label ?? this.label,
        location: location ?? this.location,
        address: address ?? this.address,
        dwellTime: dwellTime ?? this.dwellTime,
        status: status,
        arrivedAt: arrivedAt,
        completedAt: completedAt,
        checkedInAt: checkedInAt,
        proofs: List.of(proofs),
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
    Duration? freeFlowDuration,
    this.departureTime,
  }) : freeFlowDuration = freeFlowDuration ?? duration;

  final GeoPoint origin;
  final GeoPoint destination;
  final double distanceMeters;

  /// Traffic-aware travel time for a departure at [departureTime].
  final Duration duration;

  /// Travel time without traffic, for comparison.
  final Duration freeFlowDuration;

  /// Time the leg is predicted to be driven; what the routing provider priced
  /// the traffic for.
  final DateTime? departureTime;

  final List<GeoPoint> polyline;

  Duration get trafficDelay {
    final delay = duration - freeFlowDuration;
    return delay.isNegative ? Duration.zero : delay;
  }
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

  /// Driving time added by traffic across the whole remaining route.
  Duration get totalTrafficDelay =>
      legs.fold(Duration.zero, (sum, leg) => sum + leg.trafficDelay);

  List<GeoPoint> get fullPolyline => [for (final leg in legs) ...leg.polyline];
}
