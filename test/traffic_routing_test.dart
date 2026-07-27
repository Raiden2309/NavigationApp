import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mission_router/models/geo.dart';
import 'package:mission_router/services/directions_service.dart';
import 'package:mission_router/services/traffic_profile.dart';

const _origin = GeoPoint(1.2966, 103.7164);
const _b = GeoPoint(1.2712, 103.8194);
const _c = GeoPoint(1.3612, 103.9860);

/// A Routes API response with [legs] hops, each priced at [staticSeconds]
/// without traffic and [trafficSeconds] with it.
String _response({
  required int legs,
  required int staticSeconds,
  required int trafficSeconds,
  List<int>? optimizedOrder,
  bool includeStaticDuration = true,
}) =>
    jsonEncode({
      'routes': [
        {
          'optimizedIntermediateWaypointIndex': ?optimizedOrder,
          'legs': [
            for (var i = 0; i < legs; i++)
              {
                'startLocation': {
                  'latLng': {'latitude': 1.0 + i, 'longitude': 103.0 + i},
                },
                'endLocation': {
                  'latLng': {'latitude': 2.0 + i, 'longitude': 104.0 + i},
                },
                'distanceMeters': 12000,
                'duration': '${trafficSeconds}s',
                if (includeStaticDuration) 'staticDuration': '${staticSeconds}s',
                'polyline': {'encodedPolyline': '_p~iF~ps|U_ulLnnqC'},
              },
          ],
        },
      ],
    });

Map<String, dynamic> _bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  group('GoogleDirectionsService', () {
    test('asks for traffic-aware driving at the requested departure time', () async {
      final bodies = <Map<String, dynamic>>[];
      final headers = <Map<String, String>>[];
      final service = GoogleDirectionsService(
        apiKey: 'test-key',
        repriceLegs: false,
        client: MockClient((request) async {
          bodies.add(_bodyOf(request));
          headers.add(request.headers);
          return http.Response(
            _response(legs: 1, staticSeconds: 600, trafficSeconds: 900),
            200,
          );
        }),
      );

      final departure = DateTime.now().add(const Duration(hours: 3));
      await service.optimizedRoute(
        origin: _origin,
        destinations: [_b],
        departureTime: departure,
      );

      expect(bodies.single['travelMode'], 'DRIVE');
      expect(bodies.single['routingPreference'], 'TRAFFIC_AWARE_OPTIMAL');
      expect(bodies.single['departureTime'], departure.toUtc().toIso8601String());
      expect(headers.single['X-Goog-Api-Key'], 'test-key');
      expect(headers.single['X-Goog-FieldMask'], contains('routes.legs.staticDuration'));
    });

    test('optimizes the waypoint order for a multi-stop mission', () async {
      late Map<String, dynamic> body;
      final service = GoogleDirectionsService(
        apiKey: 'k',
        repriceLegs: false,
        client: MockClient((request) async {
          body = _bodyOf(request);
          return http.Response(
            _response(legs: 3, staticSeconds: 600, trafficSeconds: 900, optimizedOrder: [1, 0]),
            200,
          );
        }),
      );

      final plan = await service.optimizedRoute(origin: _origin, destinations: [_b, _c, _b]);

      expect(body['optimizeWaypointOrder'], isTrue);
      // Optimization and TRAFFIC_AWARE_OPTIMAL are mutually exclusive.
      expect(body['routingPreference'], 'TRAFFIC_AWARE');
      expect(body['intermediates'], hasLength(2));
      expect(plan.waypointOrder, [1, 0, 2]);
    });

    test('clamps a departure time in the past to now', () async {
      late Map<String, dynamic> body;
      final now = DateTime(2026, 7, 27, 9);
      final service = GoogleDirectionsService(
        apiKey: 'k',
        repriceLegs: false,
        now: () => now,
        client: MockClient((request) async {
          body = _bodyOf(request);
          return http.Response(
            _response(legs: 1, staticSeconds: 600, trafficSeconds: 600),
            200,
          );
        }),
      );

      await service.optimizedRoute(
        origin: _origin,
        destinations: [_b],
        departureTime: now.subtract(const Duration(hours: 2)),
      );

      expect(
        DateTime.parse(body['departureTime'] as String).isAfter(now),
        isTrue,
      );
    });

    test('uses the traffic duration and keeps staticDuration for comparison', () async {
      final service = GoogleDirectionsService(
        apiKey: 'k',
        repriceLegs: false,
        client: MockClient((_) async => http.Response(
              _response(legs: 1, staticSeconds: 600, trafficSeconds: 960),
              200,
            )),
      );

      final plan = await service.optimizedRoute(origin: _origin, destinations: [_b]);

      expect(plan.legs.single.duration, const Duration(seconds: 960));
      expect(plan.legs.single.freeFlowDuration, const Duration(minutes: 10));
      expect(plan.totalTrafficDelay, const Duration(minutes: 6));
    });

    test('falls back to duration when no staticDuration is returned', () async {
      final service = GoogleDirectionsService(
        apiKey: 'k',
        repriceLegs: false,
        client: MockClient((_) async => http.Response(
              _response(
                legs: 1,
                staticSeconds: 600,
                trafficSeconds: 900,
                includeStaticDuration: false,
              ),
              200,
            )),
      );

      final plan = await service.optimizedRoute(origin: _origin, destinations: [_b]);

      expect(plan.legs.single.duration, const Duration(minutes: 15));
      expect(plan.totalTrafficDelay, Duration.zero);
    });

    test('re-prices each leg for when it is actually driven', () async {
      final departures = <DateTime>[];
      final now = DateTime(2026, 7, 27, 6);
      final service = GoogleDirectionsService(
        apiKey: 'k',
        now: () => now,
        client: MockClient((request) async {
          final body = _bodyOf(request);
          departures.add(DateTime.parse(body['departureTime'] as String));
          final isMultiStop = body.containsKey('intermediates');
          return http.Response(
            _response(
              legs: isMultiStop ? 2 : 1,
              staticSeconds: 600,
              trafficSeconds: 1200,
              optimizedOrder: isMultiStop ? [0] : null,
            ),
            200,
          );
        }),
      );

      await service.optimizedRoute(
        origin: _origin,
        destinations: [_b, _c],
        departureTime: now,
        dwellTimes: const [Duration(minutes: 15), Duration(minutes: 15)],
      );

      // First the optimizing request at the mission departure, then leg 2
      // re-quoted for 20 min of driving plus 15 min on site.
      expect(departures.first.isAfter(now.subtract(const Duration(minutes: 1))), isTrue);
      expect(departures.last.toUtc(), now.add(const Duration(minutes: 35)).toUtc());
    });

    test('keeps the original leg estimate when a re-price request fails', () async {
      var call = 0;
      final service = GoogleDirectionsService(
        apiKey: 'k',
        client: MockClient((request) async {
          call++;
          if (call > 1) return http.Response('{"error":{"code":429}}', 429);
          return http.Response(
            _response(legs: 2, staticSeconds: 600, trafficSeconds: 1200, optimizedOrder: [0]),
            200,
          );
        }),
      );

      final plan = await service.optimizedRoute(origin: _origin, destinations: [_b, _c]);

      expect(plan.legs, hasLength(2));
      expect(plan.legs.last.duration, const Duration(minutes: 20));
    });

    test('surfaces API errors', () async {
      final service = GoogleDirectionsService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'error': {'code': 403, 'message': 'denied'},
              }),
              403,
            )),
      );

      expect(
        () => service.optimizedRoute(origin: _origin, destinations: [_b]),
        throwsA(isA<DirectionsException>()),
      );
    });
  });

  group('TrafficProfile', () {
    const profile = TrafficProfile();

    test('slows traffic down at the weekday peaks', () {
      final morning = profile.multiplierAt(DateTime(2026, 7, 27, 8, 15));
      final evening = profile.multiplierAt(DateTime(2026, 7, 27, 18));
      final midday = profile.multiplierAt(DateTime(2026, 7, 27, 13));

      expect(morning, greaterThan(midday));
      expect(evening, greaterThan(morning));
      expect(midday, closeTo(1.0, 0.15));
    });

    test('stays near free flow at night and on weekends', () {
      expect(profile.multiplierAt(DateTime(2026, 7, 27, 3)), lessThan(1.0));
      expect(profile.multiplierAt(DateTime(2026, 8, 1, 18)), lessThan(1.3));
    });
  });

  group('MockDirectionsService', () {
    test('prices each leg for its own predicted departure time', () async {
      final service = MockDirectionsService();

      final offPeak = await service.optimizedRoute(
        origin: _origin,
        destinations: [_b],
        departureTime: DateTime(2026, 7, 27, 13),
      );
      final rushHour = await service.optimizedRoute(
        origin: _origin,
        destinations: [_b],
        departureTime: DateTime(2026, 7, 27, 18),
      );

      expect(rushHour.totalDrivingTime, greaterThan(offPeak.totalDrivingTime));
      expect(rushHour.totalTrafficDelay, greaterThan(Duration.zero));
      expect(rushHour.legs.single.freeFlowDuration, offPeak.legs.single.freeFlowDuration);
    });

    test('pushes a later leg into rush hour via the dwell time', () async {
      final service = MockDirectionsService();

      final plan = await service.optimizedRoute(
        origin: _origin,
        destinations: [_b, _c],
        departureTime: DateTime(2026, 7, 27, 16, 30),
        dwellTimes: const [Duration(minutes: 45), Duration(minutes: 45)],
      );

      expect(plan.legs.first.departureTime!.hour, 16);
      expect(plan.legs.last.departureTime!.hour, greaterThanOrEqualTo(17));
      expect(plan.legs.last.trafficDelay, greaterThan(plan.legs.first.trafficDelay));
    });
  });
}
