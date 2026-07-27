import 'package:flutter_test/flutter_test.dart';
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

  group('decodePolyline', () {
    test('decodes the reference Google example', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.00001));
      expect(points[0].longitude, closeTo(-120.2, 0.00001));
      expect(points[2].latitude, closeTo(43.252, 0.00001));
      expect(points[2].longitude, closeTo(-126.453, 0.00001));
    });
  });
}
