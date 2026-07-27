import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mission_router/models/geo.dart';
import 'package:mission_router/services/places_service.dart';

const _singapore = GeoPoint(1.2966, 103.7164);

String get _autocompleteResponse => jsonEncode({
      'suggestions': [
        {
          'placePrediction': {
            'placeId': 'place-1',
            'text': {'text': 'Jurong Port, Singapore'},
            'structuredFormat': {
              'mainText': {'text': 'Jurong Port'},
              'secondaryText': {'text': 'Singapore'},
            },
          },
        },
        // Query predictions carry no place; they are not selectable stops.
        {
          'queryPrediction': {
            'text': {'text': 'ports near me'},
          },
        },
      ],
    });

void main() {
  group('GooglePlacesService', () {
    test('biases autocomplete towards the operator', () async {
      late Map<String, dynamic> body;
      final service = GooglePlacesService(
        apiKey: 'k',
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(_autocompleteResponse, 200);
        }),
      );

      final suggestions = await service.search('Jurong Port', near: _singapore);

      expect(body['locationBias']['circle']['center'],
          {'latitude': _singapore.latitude, 'longitude': _singapore.longitude});
      expect(suggestions, hasLength(1));
      expect(suggestions.single.title, 'Jurong Port');
      expect(suggestions.single.subtitle, 'Singapore');
      expect(suggestions.single.placeId, 'place-1');
    });

    test('drops a location bias that is off the map instead of failing', () async {
      late Map<String, dynamic> body;
      final service = GooglePlacesService(
        apiKey: 'k',
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(_autocompleteResponse, 200);
        }),
      );

      final suggestions = await service.search(
        'Jurong Port',
        near: const GeoPoint(1.29977, 212.06850),
      );

      expect(body.containsKey('locationBias'), isFalse);
      expect(suggestions, hasLength(1));
    });

    test('does not call the API for a query below the minimum length', () async {
      var calls = 0;
      final service = GooglePlacesService(
        apiKey: 'k',
        client: MockClient((_) async {
          calls++;
          return http.Response(_autocompleteResponse, 200);
        }),
      );

      expect(await service.search('ju'), isEmpty);
      expect(calls, 0);
    });

    test('resolves a suggestion to coordinates and a formatted address', () async {
      final service = GooglePlacesService(
        apiKey: 'k',
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/places/place-1'));
          expect(request.headers['X-Goog-FieldMask'], contains('formattedAddress'));
          return http.Response(
            jsonEncode({
              'id': 'place-1',
              'displayName': {'text': 'Jurong Port'},
              'formattedAddress': 'Jurong Port, Singapore',
              'location': {'latitude': 1.30346, 'longitude': 103.72431},
            }),
            200,
          );
        }),
      );

      final place = await service.resolve(
        const PlaceSuggestion(title: 'Jurong Port', subtitle: 'Singapore', placeId: 'place-1'),
      );

      expect(place!.name, 'Jurong Port');
      expect(place.address, 'Jurong Port, Singapore');
      expect(place.location.latitude, closeTo(1.30346, 1e-6));
    });

    test('names a dropped pin after the nearest place', () async {
      final service = GooglePlacesService(
        apiKey: 'k',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['rankPreference'], 'DISTANCE');
          return http.Response(
            jsonEncode({
              'places': [
                {
                  'displayName': {'text': 'Keppel Distripark'},
                  'formattedAddress': '511 Kampong Bahru Rd, Singapore',
                },
              ],
            }),
            200,
          );
        }),
      );

      final place = await service.reverseGeocode(_singapore);

      expect(place!.name, 'Keppel Distripark');
      expect(place.location, _singapore);
    });

    test('surfaces API errors', () async {
      final service = GooglePlacesService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response('{"error":{"code":403}}', 403)),
      );

      expect(
        () => service.search('Jurong Port'),
        throwsA(isA<PlacesException>()),
      );
    });
  });

  group('MockPlacesService', () {
    test('searches the offline gazetteer of real sites', () async {
      const service = MockPlacesService();

      final suggestions = await service.search('changi');

      expect(suggestions, isNotEmpty);
      final place = await service.resolve(suggestions.first);
      expect(place!.location.latitude, closeTo(1.36, 0.2));
    });
  });
}
