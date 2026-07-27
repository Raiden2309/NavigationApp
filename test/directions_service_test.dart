import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mission_router/models/geo.dart';
import 'package:mission_router/services/directions_service.dart';

void main() {
  group('MockDirectionsService', () {
    const origin = GeoPoint(1.2966, 103.7764);

    test('returns no legs when there is nothing to visit', () async {
      final plan = await MockDirectionsService().optimizedRoute(origin: origin, destinations: []);
      expect(plan.isEmpty, isTrue);
      expect(plan.waypointOrder, isEmpty);
    });

    test('orders stops so the total route is shorter than the input order', () async {
      // Deliberately zig-zagging input order.
      const destinations = [
        GeoPoint(1.3400, 103.7800),
        GeoPoint(1.2644, 103.8220),
        GeoPoint(1.3210, 103.8198),
      ];
      final service = MockDirectionsService();
      final plan = await service.optimizedRoute(origin: origin, destinations: destinations);

      expect(plan.waypointOrder.toSet(), {0, 1, 2});
      expect(plan.legs, hasLength(3));

      double straightLineLength(List<int> order) {
        var total = 0.0;
        var current = origin;
        for (final index in order) {
          total += current.distanceTo(destinations[index]);
          current = destinations[index];
        }
        return total;
      }

      expect(straightLineLength(plan.waypointOrder),
          lessThanOrEqualTo(straightLineLength([0, 1, 2])));
    });

    test('each leg starts where the previous one ended', () async {
      const destinations = [GeoPoint(1.3210, 103.8198), GeoPoint(1.2644, 103.8220)];
      final plan =
          await MockDirectionsService().optimizedRoute(origin: origin, destinations: destinations);

      expect(plan.legs.first.origin, origin);
      for (var i = 1; i < plan.legs.length; i++) {
        expect(plan.legs[i].origin, plan.legs[i - 1].destination);
      }
      expect(plan.totalDrivingTime.inSeconds, greaterThan(0));
      expect(plan.totalDistanceMeters, greaterThan(plan.legs.first.origin.distanceTo(destinations.first)));
    });
  });

  group('OsrmDirectionsService', () {
    const origin = GeoPoint(1.2966, 103.7164);
    const keppel = GeoPoint(1.2712, 103.8194);
    const changi = GeoPoint(1.3612, 103.9860);

    /// One straight-ish step per leg, encoded the way OSRM does it.
    String stepGeometry(GeoPoint from, GeoPoint to) {
      final points = [from, from.lerp(to, 0.5), to];
      var lastLat = 0;
      var lastLng = 0;
      final buffer = StringBuffer();
      void write(int value) {
        var shifted = value < 0 ? ~(value << 1) : value << 1;
        while (shifted >= 0x20) {
          buffer.writeCharCode((0x20 | (shifted & 0x1f)) + 63);
          shifted >>= 5;
        }
        buffer.writeCharCode(shifted + 63);
      }

      for (final point in points) {
        final lat = (point.latitude * 1e5).round();
        final lng = (point.longitude * 1e5).round();
        write(lat - lastLat);
        write(lng - lastLng);
        lastLat = lat;
        lastLng = lng;
      }
      return buffer.toString();
    }

    Map<String, dynamic> leg(GeoPoint from, GeoPoint to, double seconds) => {
          'duration': seconds,
          'distance': from.distanceTo(to),
          'steps': [
            {'geometry': stepGeometry(from, to)},
          ],
        };

    test('orders stops by travel time and prices each leg for its departure',
        () async {
      var tableCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('/table/')) {
          tableCalls++;
          // Node 0 is the origin, node 1 is Changi (far) and node 2 is Keppel
          // (close), matching the destination order below.
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'durations': [
                [0, 2900, 1300],
                [2900, 0, 2000],
                [1300, 2000, 0],
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'legs': [leg(origin, keppel, 1300), leg(keppel, changi, 2000)],
              },
            ],
          }),
          200,
        );
      });

      final service = OsrmDirectionsService(client: client);
      final plan = await service.optimizedRoute(
        origin: origin,
        destinations: const [changi, keppel],
        // 18:00 on a Monday: the rush-hour model must inflate the free-flow
        // durations OSRM hands back.
        departureTime: DateTime(2026, 1, 5, 18),
        dwellTimes: const [Duration(minutes: 15), Duration(minutes: 15)],
      );

      expect(tableCalls, 1);
      expect(plan.waypointOrder, [1, 0], reason: 'nearest stop by drive time first');
      expect(plan.legs, hasLength(2));
      expect(plan.legs.first.polyline.length, greaterThanOrEqualTo(3));
      expect(plan.legs.first.freeFlowDuration, const Duration(seconds: 1300));
      expect(plan.legs.first.duration, greaterThan(plan.legs.first.freeFlowDuration));
      expect(plan.legs.first.destination, keppel);
      expect(plan.legs.last.origin, keppel);
    });

    test('reports the OSRM error code rather than an empty route', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'code': 'NoRoute', 'message': 'Impossible route'}),
            200,
          ));

      expect(
        () => OsrmDirectionsService(client: client)
            .optimizedRoute(origin: origin, destinations: const [keppel]),
        throwsA(isA<DirectionsException>()),
      );
    });
  });

  group('decodePolyline', () {
    test('decodes the reference Google example', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.00001));
      expect(points[0].longitude, closeTo(-120.2, 0.00001));
      expect(points[2].latitude, closeTo(43.252, 0.00001));
      expect(points[2].longitude, closeTo(-126.453, 0.00001));
    });

    test('stays on the planet when compiled to JavaScript', () {
      // Negative deltas used to be decoded with `~`, which is unsigned on web
      // and threw the coordinates into the billions.
      for (final point in decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@')) {
        expect(point.latitude.abs(), lessThanOrEqualTo(90));
        expect(point.longitude.abs(), lessThanOrEqualTo(180));
      }
    });
  });
}
