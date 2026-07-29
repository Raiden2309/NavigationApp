import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mission_router/models/geo.dart';
import 'package:mission_router/services/kod_lokasi_service.dart';

const _apiKey = 'kl_test_key_12345';
const _kodLokasiCode = 'SBKK.568.62';

/// Full reverse-endpoint response shape.
Map<String, dynamic> _reverseBody({
  String? kode,
  double? lat,
  double? lng,
  String? districtName,
  String? stateCode,
}) {
  final body = <String, dynamic>{
    'kod': kode ?? _kodLokasiCode,
    'kodlokasiCode': kode ?? _kodLokasiCode,
    'stateCode': stateCode ?? 'SB',
    'districtCode': 'KK',
    'codeType': 'base',
    'latest': {
      'district_name': districtName ?? 'Kota Kinabalu',
      'district_code': 'KK',
      'state_code': stateCode ?? 'SB',
      'origin_latitude': 5.9818,
      'origin_longitude': 116.0755,
      'current_code': kode ?? _kodLokasiCode,
    },
  };
  if (lat != null) body['lat'] = lat;
  if (lng != null) body['lng'] = lng;
  return body;
}

/// Older /search-endpoint response shape.
Map<String, dynamic> _searchBody({
  String? kode,
  double? lat,
  double? lng,
  String? districtName,
  String? stateName,
}) =>
    {
      'kod': kode ?? _kodLokasiCode,
      if (lat != null || lng != null)
        'coordinates': {
          'latitude': lat,
          'longitude': lng,
        },
      if (districtName != null || stateName != null)
        'district': {
          'name': districtName,
          'district_code': 'PG',
          'state_name': stateName ?? 'Sabah',
          'state_code': 'SB',
          'origin': {'latitude': 5.9155, 'longitude': 116.1081},
        },
    };

void main() {
  group('KodLokasiService', () {
    test('search sends GET to /api/v1/search with correct URL and headers',
        () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;

      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        return http.Response(
            jsonEncode(_searchBody(lat: 5.83, lng: 118.05)), 200);
      });

      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.search(const GeoPoint(5.83, 118.05));

      expect(capturedUri?.path, '/api/v1/search');
      expect(capturedUri?.queryParameters, {'lat': '5.83', 'lng': '118.05'});
      expect(capturedHeaders?['X-API-Key'], _apiKey);
      expect(result?.kodLokasi, _kodLokasiCode);
      expect(result?.location?.latitude, 5.83);
      expect(result?.location?.longitude, 118.05);
    });

    test('reverse sends POST to /api/v1/reverse with kod in body', () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        capturedBody = request.body;
        return http.Response(
            jsonEncode(_reverseBody(lat: 5.9873, lng: 116.1265)), 200);
      });

      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.reverse(_kodLokasiCode);

      expect(capturedUri?.path, '/api/v1/reverse');
      expect(capturedHeaders?['X-API-Key'], _apiKey);
      expect(capturedHeaders?['Content-Type'], 'application/json');
      expect(jsonDecode(capturedBody!), {'kod': _kodLokasiCode});
      expect(result?.kodLokasi, _kodLokasiCode);
      expect(result?.location?.latitude, 5.9873);
      expect(result?.location?.longitude, 116.1265);
    });

    test('reverse builds alamat from latest block', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode(_reverseBody(
              lat: 5.9873,
              lng: 116.1265,
              districtName: 'Penampang',
              stateCode: 'SB',
            )),
            200,
          ));

      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.reverse(_kodLokasiCode);

      expect(result?.alamat, 'Penampang, SB');
    });

    test('search returns null on non-200 response', () async {
      final client =
          MockClient((_) async => http.Response('Not found', 404));
      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.search(const GeoPoint(1.0, 103.0));
      expect(result, isNull);
    });

    test('reverse returns null on non-200 response', () async {
      final client =
          MockClient((_) async => http.Response('Server error', 500));
      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.reverse('KLxxx');
      expect(result, isNull);
    });

    test('search returns null when API key is empty', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final service = KodLokasiService(apiKey: '', client: client);
      final result = await service.search(const GeoPoint(1.0, 103.0));
      expect(result, isNull);
    });

    test('reverse returns null when API key is empty', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final service = KodLokasiService(apiKey: '', client: client);
      final result = await service.reverse('KLxxx');
      expect(result, isNull);
    });

    test('parses reverse result with latest but no coordinates', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode(_reverseBody(districtName: 'Penampang', stateCode: 'SB')),
            200,
          ));
      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.reverse(_kodLokasiCode);

      expect(result?.kodLokasi, _kodLokasiCode);
      expect(result?.alamat, 'Penampang, SB');
      expect(result?.location, isNull);
    });

    test('handles network error gracefully', () async {
      final client =
          MockClient((_) async => throw Exception('Connection refused'));
      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.search(const GeoPoint(1.0, 103.0));
      expect(result, isNull);
    });

    test('parses reverse result with full location data', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode(_reverseBody(
              kode: 'SBKK.1.1',
              lat: 5.981819,
              lng: 116.075535,
              districtName: 'Kota Kinabalu',
              stateCode: 'SB',
            )),
            200,
          ));
      final service = KodLokasiService(apiKey: _apiKey, client: client);
      final result = await service.reverse('SBKK.1.1');

      expect(result?.kodLokasi, 'SBKK.1.1');
      expect(result?.alamat, 'Kota Kinabalu, SB');
      expect(result?.location?.latitude, 5.981819);
      expect(result?.location?.longitude, 116.075535);
    });
  });
}
