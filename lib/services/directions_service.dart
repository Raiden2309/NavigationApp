import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/geo.dart';
import '../models/mission.dart';
import 'traffic_profile.dart';

/// Computes the optimal visiting order and the traffic-aware driving legs
/// between stops.
///
/// Each leg is priced for the time it is actually predicted to be driven —
/// the arrival at the previous stop plus that stop's on-site allowance — so a
/// mission that runs into rush hour is estimated with rush hour traffic rather
/// than with the conditions at the moment of planning.
abstract class DirectionsService {
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,

    /// When the operator leaves [origin]. Defaults to now.
    DateTime? departureTime,

    /// On-site time per entry of [destinations], added between legs when
    /// predicting each leg's departure time.
    List<Duration> dwellTimes = const [],
  });
}

/// Offline stand-in for the Directions API.
///
/// Distances are great-circle distances inflated by [detourFactor] to
/// approximate road networks, the visiting order is solved with
/// nearest-neighbour + 2-opt (mirroring `waypoints=optimize:true`), and travel
/// times are scaled by [trafficProfile] for the predicted departure time of
/// each leg (mirroring `duration_in_traffic`).
class MockDirectionsService implements DirectionsService {
  MockDirectionsService({
    this.averageSpeedKmh = 40,
    this.detourFactor = 1.25,
    this.pointsPerLeg = 24,
    this.trafficProfile = const TrafficProfile(),
  });

  final double averageSpeedKmh;
  final double detourFactor;
  final int pointsPerLeg;
  final TrafficProfile trafficProfile;

  @override
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
    DateTime? departureTime,
    List<Duration> dwellTimes = const [],
  }) async {
    if (destinations.isEmpty) return RoutePlan.empty;
    final order = _solveOrder(origin, destinations);
    final legs = <RouteLeg>[];
    var from = origin;
    var cursor = departureTime ?? DateTime.now();
    for (final index in order) {
      final to = destinations[index];
      final leg = _buildLeg(from, to, cursor);
      legs.add(leg);
      cursor = cursor.add(leg.duration).add(
            index < dwellTimes.length ? dwellTimes[index] : Duration.zero,
          );
      from = to;
    }
    return RoutePlan(waypointOrder: order, legs: legs);
  }

  RouteLeg _buildLeg(GeoPoint from, GeoPoint to, DateTime departure) {
    final polyline = _syntheticRoad(from, to);
    final distance = polylineLength(polyline);
    final freeFlowSeconds = distance / (averageSpeedKmh * 1000 / 3600);
    final freeFlow = Duration(seconds: freeFlowSeconds.round());
    final congested = Duration(
      seconds: (freeFlowSeconds * trafficProfile.multiplierAt(departure)).round(),
    );
    return RouteLeg(
      origin: from,
      destination: to,
      distanceMeters: distance,
      duration: congested,
      freeFlowDuration: freeFlow,
      departureTime: departure,
      polyline: polyline,
    );
  }

  /// Bends the straight line between two stops so the drawn route looks like a
  /// road and its length matches [detourFactor].
  List<GeoPoint> _syntheticRoad(GeoPoint from, GeoPoint to) {
    final straight = from.distanceTo(to);
    if (straight == 0) return [from, to];
    final amplitude = (detourFactor - 1) * straight * 0.9;
    final metersPerDegree = 111320.0;
    final normalLat = -(to.longitude - from.longitude);
    final normalLng = to.latitude - from.latitude;
    final normalLength = math.sqrt(normalLat * normalLat + normalLng * normalLng);
    // Derived from the coordinates so a leg keeps the same shape and length
    // across replans.
    final phase = ((from.latitude + to.longitude) * 1000).abs() % math.pi;
    final points = <GeoPoint>[];
    for (var i = 0; i <= pointsPerLeg; i++) {
      final t = i / pointsPerLeg;
      final base = from.lerp(to, t);
      if (normalLength == 0 || i == 0 || i == pointsPerLeg) {
        points.add(base);
        continue;
      }
      final offset = math.sin(t * math.pi * 2 + phase) * math.sin(t * math.pi) * amplitude;
      final scale = offset / metersPerDegree / normalLength;
      points.add(GeoPoint(base.latitude + normalLat * scale, base.longitude + normalLng * scale));
    }
    return points;
  }

  List<int> _solveOrder(GeoPoint origin, List<GeoPoint> destinations) {
    final order = _nearestNeighbour(origin, destinations);
    return _twoOpt(origin, destinations, order);
  }

  List<int> _nearestNeighbour(GeoPoint origin, List<GeoPoint> destinations) {
    final remaining = List<int>.generate(destinations.length, (i) => i);
    final order = <int>[];
    var current = origin;
    while (remaining.isNotEmpty) {
      var bestIndex = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final distance = current.distanceTo(destinations[remaining[i]]);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = i;
        }
      }
      final chosen = remaining.removeAt(bestIndex);
      order.add(chosen);
      current = destinations[chosen];
    }
    return order;
  }

  List<int> _twoOpt(GeoPoint origin, List<GeoPoint> destinations, List<int> order) {
    if (order.length < 3) return order;
    final best = List<int>.from(order);
    var improved = true;
    while (improved) {
      improved = false;
      for (var i = 0; i < best.length - 1; i++) {
        for (var j = i + 1; j < best.length; j++) {
          final candidate = List<int>.from(best)
            ..setRange(i, j + 1, best.sublist(i, j + 1).reversed);
          if (_pathLength(origin, destinations, candidate) <
              _pathLength(origin, destinations, best) - 0.5) {
            best.setAll(0, candidate);
            improved = true;
          }
        }
      }
    }
    return best;
  }

  double _pathLength(GeoPoint origin, List<GeoPoint> destinations, List<int> order) {
    var total = 0.0;
    var current = origin;
    for (final index in order) {
      total += current.distanceTo(destinations[index]);
      current = destinations[index];
    }
    return total;
  }
}

/// Google Routes API (`directions/v2:computeRoutes`) implementation.
///
/// The visiting order comes from one `optimizeWaypointOrder` request. Every
/// later leg is then re-quoted with its own `departureTime`, because a single
/// request prices the whole route from one departure and would otherwise quote
/// the last leg with the traffic of the first — the difference between leaving
/// the depot at 16:00 and driving the final leg at 18:30.
class GoogleDirectionsService implements DirectionsService {
  GoogleDirectionsService({
    required this.apiKey,
    http.Client? client,
    this.repriceLegs = true,
    Uri? endpoint,
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        endpoint = endpoint ??
            Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
        _now = now ?? DateTime.now;

  final String apiKey;
  final http.Client _client;
  final Uri endpoint;

  /// Re-requests every leg after the first with its own predicted departure
  /// time. Costs one extra request per leg; disable to stay on one request.
  final bool repriceLegs;

  final DateTime Function() _now;

  /// How far ahead of now a departure time is pushed when the caller asks to
  /// leave immediately.
  static const Duration departureCushion = Duration(seconds: 60);

  static const _fieldMask = 'routes.optimizedIntermediateWaypointIndex,'
      'routes.legs.duration,routes.legs.staticDuration,routes.legs.distanceMeters,'
      'routes.legs.startLocation,routes.legs.endLocation,'
      'routes.legs.polyline.encodedPolyline';

  @override
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
    DateTime? departureTime,
    List<Duration> dwellTimes = const [],
  }) async {
    if (destinations.isEmpty) return RoutePlan.empty;
    final start = departureTime ?? _now();
    final intermediates = destinations.sublist(0, destinations.length - 1);

    final route = await _computeRoute(
      origin: origin,
      destination: destinations.last,
      intermediates: intermediates,
      departure: start,
    );

    final optimized = (route['optimizedIntermediateWaypointIndex'] as List?) ?? const [];
    final waypointOrder = [
      for (final index in optimized) index as int,
      destinations.length - 1,
    ];
    var legs = [
      for (final leg in route['legs'] as List) _parseLeg(leg as Map<String, dynamic>, start),
    ];
    if (repriceLegs && legs.length > 1) {
      legs = await _repriceLegs(legs, waypointOrder, dwellTimes, start);
    }
    return RoutePlan(waypointOrder: waypointOrder, legs: legs);
  }

  /// Walks the route forward, re-quoting each leg for the time the operator is
  /// predicted to actually start driving it: the previous arrival plus that
  /// stop's on-site allowance.
  Future<List<RouteLeg>> _repriceLegs(
    List<RouteLeg> legs,
    List<int> waypointOrder,
    List<Duration> dwellTimes,
    DateTime start,
  ) async {
    final repriced = <RouteLeg>[];
    var cursor = start;
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final priced = i == 0 ? leg : await _singleLeg(leg, cursor);
      repriced.add(priced);
      final destinationIndex = i < waypointOrder.length ? waypointOrder[i] : -1;
      final dwell = destinationIndex >= 0 && destinationIndex < dwellTimes.length
          ? dwellTimes[destinationIndex]
          : defaultDwellTime;
      cursor = cursor.add(priced.duration).add(dwell);
    }
    return repriced;
  }

  Future<RouteLeg> _singleLeg(RouteLeg leg, DateTime departure) async {
    try {
      final route = await _computeRoute(
        origin: leg.origin,
        destination: leg.destination,
        intermediates: const [],
        departure: departure,
      );
      return _parseLeg((route['legs'] as List).first as Map<String, dynamic>, departure);
    } on DirectionsException {
      // Keep the estimate from the planning request rather than failing the
      // whole mission plan.
      return leg;
    }
  }

  Future<Map<String, dynamic>> _computeRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    required List<GeoPoint> intermediates,
    required DateTime departure,
  }) async {
    final optimizing = intermediates.isNotEmpty;
    final body = {
      'origin': _waypoint(origin),
      'destination': _waypoint(destination),
      if (optimizing) 'intermediates': [for (final point in intermediates) _waypoint(point)],
      'travelMode': 'DRIVE',
      // TRAFFIC_AWARE_OPTIMAL is the most accurate traffic model but the API
      // rejects it together with waypoint optimization.
      'routingPreference': optimizing ? 'TRAFFIC_AWARE' : 'TRAFFIC_AWARE_OPTIMAL',
      if (optimizing) 'optimizeWaypointOrder': true,
      'departureTime': _departureParam(departure),
    };

    final response = await _client.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': _fieldMask,
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw DirectionsException(
        'Routes API returned HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = decoded['routes'] as List? ?? const [];
    if (routes.isEmpty) throw DirectionsException('Routes API returned no route');
    return routes.first as Map<String, dynamic>;
  }

  Map<String, dynamic> _waypoint(GeoPoint point) => {
        'location': {
          'latLng': {'latitude': point.latitude, 'longitude': point.longitude},
        },
      };

  /// Traffic-aware routing rejects a departure time that is not in the future,
  /// so a departure of "now" is pushed past the request's own round trip and
  /// any clock skew between this device and Google.
  String _departureParam(DateTime departure) {
    final earliest = _now().add(departureCushion);
    final effective = departure.isAfter(earliest) ? departure : earliest;
    return effective.toUtc().toIso8601String();
  }

  RouteLeg _parseLeg(Map<String, dynamic> leg, DateTime departure) {
    final origin = _point(leg['startLocation'] as Map<String, dynamic>);
    final destination = _point(leg['endLocation'] as Map<String, dynamic>);
    final encoded = (leg['polyline'] as Map<String, dynamic>?)?['encodedPolyline'] as String?;
    final polyline = encoded == null ? <GeoPoint>[] : decodePolyline(encoded);
    return RouteLeg(
      origin: origin,
      destination: destination,
      distanceMeters: ((leg['distanceMeters'] as num?) ?? 0).toDouble(),
      duration: _duration(leg['duration']),
      // staticDuration is the same route without live/predicted traffic.
      freeFlowDuration: _duration(leg['staticDuration'] ?? leg['duration']),
      departureTime: departure,
      polyline: polyline.isEmpty ? [origin, destination] : polyline,
    );
  }

  GeoPoint _point(Map<String, dynamic> location) {
    final latLng = location['latLng'] as Map<String, dynamic>;
    return GeoPoint(
      (latLng['latitude'] as num).toDouble(),
      (latLng['longitude'] as num).toDouble(),
    );
  }

  /// Durations arrive as protobuf strings such as `"1832s"`.
  Duration _duration(Object? value) {
    if (value is! String) return Duration.zero;
    final seconds = double.tryParse(value.replaceAll('s', '')) ?? 0;
    return Duration(seconds: seconds.round());
  }
}

class DirectionsException implements Exception {
  DirectionsException(this.message);

  final String message;

  @override
  String toString() => 'DirectionsException: $message';
}

/// Decodes Google's encoded polyline format.
List<GeoPoint> decodePolyline(String encoded) {
  final points = <GeoPoint>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    lat += _decodeValue(encoded, index, (next) => index = next);
    lng += _decodeValue(encoded, index, (next) => index = next);
    points.add(GeoPoint(lat / 1e5, lng / 1e5));
  }
  return points;
}

int _decodeValue(String encoded, int start, void Function(int) setIndex) {
  var index = start;
  var shift = 0;
  var result = 0;
  int byte;
  do {
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);
  setIndex(index);
  // A trailing 1 bit marks a negative value. `~` is avoided: compiled to
  // JavaScript it yields an unsigned 32-bit result, which sends the decoded
  // coordinates off the planet.
  final magnitude = result >> 1;
  return (result & 1) != 0 ? -magnitude - 1 : magnitude;
}
