import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/geo.dart';

class KodLokasiResult {
  const KodLokasiResult({
    required this.kodLokasi,
    this.alamat,
    this.location,
  });

  final String kodLokasi;
  final String? alamat;
  final GeoPoint? location;
}

class KodLokasiService {
  KodLokasiService({
    required this.apiKey,
    http.Client? client,
    this.baseUri = 'https://api.kodlokasi.my',
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;
  final String baseUri;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      };

  Future<KodLokasiResult?> search(GeoPoint point) async {
    if (apiKey.isEmpty) return null;
    try {
      final response = await _client.get(
        Uri.parse('$baseUri/api/v1/search?lat=${point.latitude}&lng=${point.longitude}'),
        headers: _headers,
      );
      if (response.statusCode != 200) return null;
      return _parseSearchResult(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<KodLokasiResult?> reverse(String kodLokasi) async {
    if (apiKey.isEmpty) return null;
    try {
      final response = await _client.post(
        Uri.parse('$baseUri/api/v1/reverse'),
        headers: _headers,
        body: jsonEncode({'kod': kodLokasi}),
      );
      if (response.statusCode != 200) return null;
      return _parseReverseResult(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  KodLokasiResult? _parseSearchResult(Map<String, dynamic> body) {
    final kode = body['kod'] as String?;
    if (kode == null || kode.isEmpty) return null;

    double? lat;
    double? lng;
    final coords = body['coordinates'] as Map<String, dynamic>?;
    if (coords != null) {
      lat = (coords['latitude'] as num?)?.toDouble();
      lng = (coords['longitude'] as num?)?.toDouble();
    }

    String? alamat;
    final district = body['district'] as Map<String, dynamic>?;
    if (district != null) {
      final d = district['name'];
      final s = district['state_name'];
      if (d != null && s != null) alamat = '$d, $s';
    }

    return KodLokasiResult(
      kodLokasi: kode,
      alamat: alamat,
      location: lat != null && lng != null ? GeoPoint(lat, lng) : null,
    );
  }

  KodLokasiResult? _parseReverseResult(Map<String, dynamic> body) {
    final kode = body['kod'] as String?;
    if (kode == null || kode.isEmpty) return null;

    final lat = (body['lat'] as num?)?.toDouble();
    final lng = (body['lng'] as num?)?.toDouble();

    String? alamat;
    final latest = body['latest'] as Map<String, dynamic>?;
    if (latest != null) {
      final d = latest['district_name'];
      final s = latest['state_code'];
      if (d != null && s != null) alamat = '$d, $s';
    }

    return KodLokasiResult(
      kodLokasi: kode,
      alamat: alamat,
      location: lat != null && lng != null ? GeoPoint(lat, lng) : null,
    );
  }
}
