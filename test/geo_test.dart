import 'package:flutter_test/flutter_test.dart';
import 'package:mission_router/models/geo.dart';

void main() {
  test('distanceTo matches a known great-circle distance', () {
    const singapore = GeoPoint(1.3521, 103.8198);
    const kualaLumpur = GeoPoint(3.1390, 101.6869);
    expect(singapore.distanceTo(kualaLumpur) / 1000, closeTo(309, 2));
  });

  test('pointAlongPath walks the polyline', () {
    const path = [GeoPoint(1.0, 103.0), GeoPoint(1.01, 103.0), GeoPoint(1.02, 103.0)];
    final total = polylineLength(path);
    final middle = pointAlongPath(path, total / 2);
    expect(middle.latitude, closeTo(1.01, 0.0005));
    expect(pointAlongPath(path, -5), path.first);
    expect(pointAlongPath(path, total * 2), path.last);
  });

  test('distanceAlongPath projects an off-route position onto the path', () {
    const path = [GeoPoint(1.0, 103.0), GeoPoint(1.0, 103.02)];
    final total = polylineLength(path);
    // Slightly north of the halfway point.
    final travelled = distanceAlongPath(path, const GeoPoint(1.0005, 103.01));
    expect(travelled, closeTo(total / 2, total * 0.02));
  });

  test('splitPath cuts the polyline into a driven and a remaining half', () {
    const path = [GeoPoint(1.0, 103.0), GeoPoint(1.0, 103.01), GeoPoint(1.0, 103.02)];
    final total = polylineLength(path);
    final (driven, ahead) = splitPath(path, total / 2);

    expect(driven.last, ahead.first, reason: 'the halves must stay joined');
    expect(driven.last.longitude, closeTo(103.01, 0.0005));
    expect(polylineLength(driven) + polylineLength(ahead), closeTo(total, 1));
    expect(splitPath(path, 0).$1, isEmpty);
    expect(splitPath(path, total * 2).$2, isEmpty);
  });
}
