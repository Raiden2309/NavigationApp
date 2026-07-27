import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/geo.dart';

/// A place the mission operator can pick as a destination.
class Place {
  const Place({required this.name, required this.address, required this.location, this.placeId});

  final String name;
  final String address;
  final GeoPoint location;
  final String? placeId;
}

/// An autocomplete result; [location] is null until the place is resolved.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    this.placeId,
    this.location,
  });

  final String title;
  final String subtitle;
  final String? placeId;
  final GeoPoint? location;
}

/// Turns what a mission operator types into real world coordinates.
abstract class PlacesService {
  /// Suggestions for [query], biased towards [near] when given.
  Future<List<PlaceSuggestion>> search(String query, {GeoPoint? near});

  /// Resolves a suggestion to coordinates.
  Future<Place?> resolve(PlaceSuggestion suggestion);

  /// Address of a coordinate, e.g. for a destination dropped on the map.
  Future<Place?> reverseGeocode(GeoPoint location);
}

/// Places API (New): Autocomplete, Place Details and nearest-place lookup for
/// coordinates dropped on the map.
class GooglePlacesService implements PlacesService {
  GooglePlacesService({
    required this.apiKey,
    http.Client? client,
    Uri? baseUri,
    this.sessionToken,
    this.searchRadiusMeters = 50000,
  })  : _client = client ?? http.Client(),
        baseUri = baseUri ?? Uri.parse('https://places.googleapis.com/v1');

  final String apiKey;
  final http.Client _client;
  final Uri baseUri;

  /// Groups autocomplete keystrokes with the follow-up details call so Google
  /// bills them as one session.
  final String? sessionToken;

  final int searchRadiusMeters;

  @override
  Future<List<PlaceSuggestion>> search(String query, {GeoPoint? near}) async {
    if (query.trim().length < 3) return const [];
    final body = await _post('/places:autocomplete', {
      'input': query,
      'sessionToken': ?sessionToken,
      if (near != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': searchRadiusMeters.toDouble(),
          },
        },
    });

    return [
      for (final suggestion in (body['suggestions'] as List? ?? const []))
        if ((suggestion as Map<String, dynamic>)['placePrediction'] != null)
          _suggestion(suggestion['placePrediction'] as Map<String, dynamic>),
    ];
  }

  PlaceSuggestion _suggestion(Map<String, dynamic> prediction) {
    final structured = prediction['structuredFormat'] as Map<String, dynamic>?;
    return PlaceSuggestion(
      title: structured?['mainText']?['text'] as String? ??
          prediction['text']?['text'] as String? ??
          '',
      subtitle: structured?['secondaryText']?['text'] as String? ?? '',
      placeId: prediction['placeId'] as String?,
    );
  }

  @override
  Future<Place?> resolve(PlaceSuggestion suggestion) async {
    final placeId = suggestion.placeId;
    if (placeId == null) {
      final location = suggestion.location;
      return location == null
          ? null
          : Place(name: suggestion.title, address: suggestion.subtitle, location: location);
    }
    final body = await _get('/places/$placeId', 'id,displayName,formattedAddress,location');
    final location = body['location'] as Map<String, dynamic>?;
    if (location == null) return null;
    return Place(
      name: body['displayName']?['text'] as String? ?? suggestion.title,
      address: body['formattedAddress'] as String? ?? suggestion.subtitle,
      location: GeoPoint(
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      ),
      placeId: placeId,
    );
  }

  /// The Places API has no reverse geocoder, so the nearest place to the
  /// dropped pin names the stop.
  @override
  Future<Place?> reverseGeocode(GeoPoint location) async {
    final body = await _post('/places:searchNearby', {
      'locationRestriction': {
        'circle': {
          'center': {'latitude': location.latitude, 'longitude': location.longitude},
          'radius': 500.0,
        },
      },
      'rankPreference': 'DISTANCE',
      'maxResultCount': 1,
    }, fieldMask: 'places.displayName,places.formattedAddress');
    final places = body['places'] as List? ?? const [];
    if (places.isEmpty) return null;
    final place = places.first as Map<String, dynamic>;
    return Place(
      name: place['displayName']?['text'] as String? ?? 'Dropped pin',
      address: place['formattedAddress'] as String? ?? '$location',
      location: location,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? fieldMask,
  }) async {
    final response = await _client.post(
      baseUri.replace(path: '${baseUri.path}$path'),
      headers: _headers(fieldMask),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path, String fieldMask) async {
    final response = await _client.get(
      baseUri.replace(path: '${baseUri.path}$path'),
      headers: _headers(fieldMask),
    );
    return _decode(response);
  }

  Map<String, String> _headers(String? fieldMask) => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': ?fieldMask,
      };

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw PlacesException('Places API returned HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

/// Offline place lookup over a fixed gazetteer of real locations, so the demo
/// still searches by name without an API key.
class MockPlacesService implements PlacesService {
  const MockPlacesService({this.places = singaporeLandmarks});

  final List<Place> places;

  @override
  Future<List<PlaceSuggestion>> search(String query, {GeoPoint? near}) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final matches = places
        .where((place) =>
            place.name.toLowerCase().contains(needle) ||
            place.address.toLowerCase().contains(needle))
        .toList();
    if (near != null) {
      matches.sort((a, b) =>
          near.distanceTo(a.location).compareTo(near.distanceTo(b.location)));
    }
    return [
      for (final place in matches.take(6))
        PlaceSuggestion(
          title: place.name,
          subtitle: place.address,
          placeId: place.placeId,
          location: place.location,
        ),
    ];
  }

  @override
  Future<Place?> resolve(PlaceSuggestion suggestion) async {
    final location = suggestion.location;
    if (location == null) return null;
    return Place(name: suggestion.title, address: suggestion.subtitle, location: location);
  }

  @override
  Future<Place?> reverseGeocode(GeoPoint location) async {
    if (places.isEmpty) return null;
    final nearest = places.reduce((a, b) =>
        location.distanceTo(a.location) <= location.distanceTo(b.location) ? a : b);
    final metres = location.distanceTo(nearest.location);
    if (metres < 400) return Place(name: nearest.name, address: nearest.address, location: location);
    return Place(
      name: 'Near ${nearest.name}',
      address: '${(metres / 1000).toStringAsFixed(1)} km from ${nearest.address}',
      location: location,
    );
  }
}

/// Real coordinates for well known Singapore logistics and landmark sites.
const List<Place> singaporeLandmarks = [
  Place(
    name: 'Jurong Port',
    address: '37 Jurong Port Rd, Singapore 619110',
    location: GeoPoint(1.2966, 103.7164),
  ),
  Place(
    name: 'Tuas Mega Port',
    address: 'Tuas South Blvd, Singapore 637000',
    location: GeoPoint(1.2494, 103.6272),
  ),
  Place(
    name: 'PSA Pasir Panjang Terminal',
    address: '31 Pasir Panjang Rd, Singapore 118503',
    location: GeoPoint(1.2755, 103.7778),
  ),
  Place(
    name: 'Keppel Distripark',
    address: '511 Kampong Bahru Rd, Singapore 099447',
    location: GeoPoint(1.2712, 103.8194),
  ),
  Place(
    name: 'Changi Airfreight Centre',
    address: '9 Airline Rd, Singapore 819827',
    location: GeoPoint(1.3612, 103.9860),
  ),
  Place(
    name: 'Changi Airport Terminal 3',
    address: '65 Airport Blvd, Singapore 819663',
    location: GeoPoint(1.3563, 103.9865),
  ),
  Place(
    name: 'Woodlands Checkpoint',
    address: '21 Woodlands Crossing, Singapore 738203',
    location: GeoPoint(1.4470, 103.7690),
  ),
  Place(
    name: 'Tuas Checkpoint',
    address: '11 Tuas Checkpoint, Singapore 639307',
    location: GeoPoint(1.3479, 103.6363),
  ),
  Place(
    name: 'Marina Bay Sands',
    address: '10 Bayfront Ave, Singapore 018956',
    location: GeoPoint(1.2834, 103.8607),
  ),
  Place(
    name: 'Singapore Expo',
    address: '1 Expo Dr, Singapore 486150',
    location: GeoPoint(1.3345, 103.9615),
  ),
  Place(
    name: 'Ang Mo Kio Industrial Park 2',
    address: 'Ang Mo Kio Industrial Park 2, Singapore 569511',
    location: GeoPoint(1.3760, 103.8552),
  ),
  Place(
    name: 'Sungei Kadut Industrial Estate',
    address: 'Sungei Kadut Way, Singapore 728785',
    location: GeoPoint(1.4131, 103.7480),
  ),
  Place(
    name: 'Toa Payoh Industrial Park',
    address: 'Lor 8 Toa Payoh, Singapore 319261',
    location: GeoPoint(1.3350, 103.8560),
  ),
  Place(
    name: 'Alexandra Distripark',
    address: '3 Pasir Panjang Rd, Singapore 118480',
    location: GeoPoint(1.2740, 103.8028),
  ),
];

class PlacesException implements Exception {
  PlacesException(this.message);

  final String message;

  @override
  String toString() => 'PlacesException: $message';
}
