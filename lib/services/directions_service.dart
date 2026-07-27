import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/geo.dart';
import '../models/mission.dart';

/// Computes the optimal visiting order and the driving legs between stops.
///
/// [MockDirectionsService] is used by default so the app runs without any API
/// key; [GoogleDirectionsService] talks to the real Directions API and is a
/// drop-in replacement.
abstract class DirectionsService {
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
  });
}

/// Offline stand-in for the Directions API.
///
/// Distances are great-circle distances inflated by [detourFactor] to
/// approximate road networks, and the visiting order is solved with
/// nearest-neighbour + 2-opt, which mirrors `waypoints=optimize:true`.
class MockDirectionsService implements DirectionsService {
  MockDirectionsService({
    this.averageSpeedKmh = 40,
    this.detourFactor = 1.25,
    this.pointsPerLeg = 24,
    int seed = 7,
  }) : _random = math.Random(seed);

  final double averageSpeedKmh;
  final double detourFactor;
  final int pointsPerLeg;
  final math.Random _random;

  @override
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
  }) async {
    if (destinations.isEmpty) return RoutePlan.empty;
    final order = _solveOrder(origin, destinations);
    final legs = <RouteLeg>[];
    var from = origin;
    for (final index in order) {
      final to = destinations[index];
      legs.add(_buildLeg(from, to));
      from = to;
    }
    return RoutePlan(waypointOrder: order, legs: legs);
  }

  RouteLeg _buildLeg(GeoPoint from, GeoPoint to) {
    final polyline = _syntheticRoad(from, to);
    final distance = polylineLength(polyline);
    final seconds = distance / (averageSpeedKmh * 1000 / 3600);
    return RouteLeg(
      origin: from,
      destination: to,
      distanceMeters: distance,
      duration: Duration(seconds: seconds.round()),
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
    final phase = _random.nextDouble() * math.pi;
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

/// Google Directions API implementation.
///
/// Requests the route with `waypoints=optimize:true` so Google returns the
/// optimal visiting order for every stop after the starting point.
class GoogleDirectionsService implements DirectionsService {
  GoogleDirectionsService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<RoutePlan> optimizedRoute({
    required GeoPoint origin,
    required List<GeoPoint> destinations,
  }) async {
    if (destinations.isEmpty) return RoutePlan.empty;
    final last = destinations.last;
    final intermediate = destinations.sublist(0, destinations.length - 1);
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': _format(origin),
      'destination': _format(last),
      if (intermediate.isNotEmpty)
        'waypoints': 'optimize:true|${intermediate.map(_format).join('|')}',
      'mode': 'driving',
      'departure_time': 'now',
      'key': apiKey,
    });

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw DirectionsException('Directions API returned HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final status = body['status'] as String? ?? 'UNKNOWN';
    if (status != 'OK') {
      throw DirectionsException('Directions API status $status: ${body['error_message'] ?? ''}');
    }

    final route = (body['routes'] as List).first as Map<String, dynamic>;
    final waypointOrder = [
      ...((route['waypoint_order'] as List?) ?? const []).map((e) => e as int),
      destinations.length - 1,
    ];
    final legs = [
      for (final leg in route['legs'] as List) _parseLeg(leg as Map<String, dynamic>),
    ];
    return RoutePlan(waypointOrder: waypointOrder, legs: legs);
  }

  RouteLeg _parseLeg(Map<String, dynamic> leg) {
    final start = leg['start_location'] as Map<String, dynamic>;
    final end = leg['end_location'] as Map<String, dynamic>;
    // duration_in_traffic is only present when a departure_time is supplied.
    final duration = (leg['duration_in_traffic'] ?? leg['duration']) as Map<String, dynamic>;
    final polyline = <GeoPoint>[];
    for (final step in leg['steps'] as List) {
      final encoded = (step as Map<String, dynamic>)['polyline']['points'] as String;
      polyline.addAll(decodePolyline(encoded));
    }
    return RouteLeg(
      origin: GeoPoint((start['lat'] as num).toDouble(), (start['lng'] as num).toDouble()),
      destination: GeoPoint((end['lat'] as num).toDouble(), (end['lng'] as num).toDouble()),
      distanceMeters: ((leg['distance'] as Map<String, dynamic>)['value'] as num).toDouble(),
      duration: Duration(seconds: (duration['value'] as num).round()),
      polyline: polyline.isEmpty
          ? [
              GeoPoint((start['lat'] as num).toDouble(), (start['lng'] as num).toDouble()),
              GeoPoint((end['lat'] as num).toDouble(), (end['lng'] as num).toDouble()),
            ]
          : polyline,
    );
  }

  String _format(GeoPoint point) => '${point.latitude},${point.longitude}';
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
  return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
}
