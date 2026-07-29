/// A GPS position sample sent to the backend for live operator tracking.
class TrackingPoint {
  const TrackingPoint({
    required this.missionId,
    required this.operatorId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.recordedAt,
  });

  final String missionId;
  final String operatorId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;
}

/// Collects and transmits tracking points.
///
/// Phase 1: stores points in memory and provides a callback for simulated
/// transmission. Real-time WebSocket integration will follow.
class TrackingService {
  TrackingService({
    required this.missionId,
    required this.operatorId,
    this.onTransmit,
  });

  final String missionId;
  final String operatorId;

  /// Called with the latest point when tracking should be sent to the backend.
  /// Phase 1: set to `null` (points are collected but not transmitted).
  final void Function(TrackingPoint)? onTransmit;

  final List<TrackingPoint> _points = [];

  /// All tracking points collected so far.
  List<TrackingPoint> get points => List.unmodifiable(_points);

  /// Number of points collected.
  int get count => _points.length;

  /// Record a new position fix and optionally transmit it.
  void record({
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? recordedAt,
  }) {
    final point = TrackingPoint(
      missionId: missionId,
      operatorId: operatorId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      recordedAt: recordedAt ?? DateTime.now(),
    );
    _points.add(point);
    onTransmit?.call(point);
  }

  /// Clear all collected points.
  void reset() => _points.clear();
}
