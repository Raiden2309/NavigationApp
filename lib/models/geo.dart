import 'dart:math' as math;

/// A WGS84 coordinate.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  static const double _earthRadiusMeters = 6371008.8;

  /// Great-circle distance in meters.
  double distanceTo(GeoPoint other) {
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);
    final dLat = lat2 - lat1;
    final dLng = _toRadians(other.longitude - longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Initial bearing in degrees towards [other].
  double bearingTo(GeoPoint other) {
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);
    final dLng = _toRadians(other.longitude - longitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (_toDegrees(math.atan2(y, x)) + 360) % 360;
  }

  /// Linear interpolation towards [other]; [t] is clamped to `[0, 1]`.
  GeoPoint lerp(GeoPoint other, double t) {
    final f = t.clamp(0.0, 1.0);
    return GeoPoint(
      latitude + (other.latitude - latitude) * f,
      longitude + (other.longitude - longitude) * f,
    );
  }

  Map<String, dynamic> toJson() => {'lat': latitude, 'lng': longitude};

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());

  @override
  String toString() => '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _toDegrees(double radians) => radians * 180 / math.pi;
}

/// Total length in meters of a polyline.
double polylineLength(List<GeoPoint> path) {
  var total = 0.0;
  for (var i = 1; i < path.length; i++) {
    total += path[i - 1].distanceTo(path[i]);
  }
  return total;
}

/// Projects [point] onto [path] and returns how far along the path (in meters)
/// the closest position lies. Returns 0 for an empty or single-point path.
double distanceAlongPath(List<GeoPoint> path, GeoPoint point) {
  if (path.length < 2) return 0;
  var travelled = 0.0;
  var bestTravelled = 0.0;
  var bestDistance = double.infinity;
  for (var i = 1; i < path.length; i++) {
    final segmentStart = path[i - 1];
    final segmentEnd = path[i];
    final segmentLength = segmentStart.distanceTo(segmentEnd);
    final t = segmentLength == 0 ? 0.0 : _projectionFactor(segmentStart, segmentEnd, point);
    final projection = segmentStart.lerp(segmentEnd, t);
    final distance = projection.distanceTo(point);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestTravelled = travelled + segmentLength * t;
    }
    travelled += segmentLength;
  }
  return bestTravelled;
}

/// Splits [path] at [meters] from its start, so the two halves can be drawn
/// differently. Both halves share the split point, keeping the line unbroken.
(List<GeoPoint>, List<GeoPoint>) splitPath(List<GeoPoint> path, double meters) {
  if (path.length < 2 || meters <= 0) return (const [], path);
  var remaining = meters;
  for (var i = 1; i < path.length; i++) {
    final segmentLength = path[i - 1].distanceTo(path[i]);
    if (remaining <= segmentLength) {
      final t = segmentLength == 0 ? 0.0 : remaining / segmentLength;
      final split = path[i - 1].lerp(path[i], t);
      return ([...path.take(i), split], [split, ...path.skip(i)]);
    }
    remaining -= segmentLength;
  }
  return (path, const []);
}

/// Returns the position [meters] along [path] from its start.
GeoPoint pointAlongPath(List<GeoPoint> path, double meters) {
  if (path.isEmpty) throw ArgumentError('path must not be empty');
  if (path.length == 1 || meters <= 0) return path.first;
  var remaining = meters;
  for (var i = 1; i < path.length; i++) {
    final segmentLength = path[i - 1].distanceTo(path[i]);
    if (remaining <= segmentLength) {
      final t = segmentLength == 0 ? 0.0 : remaining / segmentLength;
      return path[i - 1].lerp(path[i], t);
    }
    remaining -= segmentLength;
  }
  return path.last;
}

double _projectionFactor(GeoPoint a, GeoPoint b, GeoPoint p) {
  // Equirectangular approximation is accurate enough at street scale.
  final cosLat = math.cos(GeoPoint._toRadians(a.latitude));
  final ax = a.longitude * cosLat;
  final bx = b.longitude * cosLat;
  final px = p.longitude * cosLat;
  final dx = bx - ax;
  final dy = b.latitude - a.latitude;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return 0;
  final t = ((px - ax) * dx + (p.latitude - a.latitude) * dy) / lengthSquared;
  return t.clamp(0.0, 1.0);
}
