import 'package:flutter/material.dart';

import 'models/geo.dart';
import 'models/mission.dart';
import 'services/directions_service.dart';
import 'services/kod_lokasi_service.dart';
import 'services/location_service.dart';
import 'services/mission_clock.dart';
import 'services/mission_engine.dart';
import 'services/places_service.dart';
import 'ui/mission_screen.dart';

/// Google Maps API key for routing and places.
/// Set via: `--dart-define=GOOGLE_MAPS_API_KEY=...`
const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// KodLokasi API key for grid-code location lookup.
/// Set via: `--dart-define=KODLOKASI_API_KEY=...`
const String kodLokasiApiKey = String.fromEnvironment('KODLOKASI_API_KEY');

/// Use real device GPS instead of simulated operator.
/// Set via: `--dart-define=USE_DEVICE_LOCATION=true`.
const bool useDeviceLocation = bool.fromEnvironment('USE_DEVICE_LOCATION');

/// Routing backend: `google`, `osrm`, or `mock`.
/// Auto-selects Google when a key is present, otherwise OSRM.
/// Set via: `--dart-define=ROUTING_BACKEND=...`
const String routingBackend = String.fromEnvironment('ROUTING_BACKEND');

bool get _useGoogleApis => googleMapsApiKey.isNotEmpty;

String get _activeBackend => routingBackend.isNotEmpty
    ? routingBackend
    : _useGoogleApis
        ? 'google'
        : 'osrm';

void main() {
  runApp(const MissionRouterApp());
}

class MissionRouterApp extends StatefulWidget {
  const MissionRouterApp({super.key});

  @override
  State<MissionRouterApp> createState() => _MissionRouterAppState();
}

class _MissionRouterAppState extends State<MissionRouterApp> {
  late final ScaledClock _clock;
  late final LocationService _location;
  late final MissionEngine _engine;
  late final PlacesService _places;
  late final KodLokasiService _kodLokasi;

  /// Real dispatch sites in Kota Kinabalu; Point A is the depot.
  static final _startingPoint = MissionPoint(
    id: 'a',
    label: 'Asia City',
    address: 'Asia City, 88000 Kota Kinabalu, Sabah, Malaysia',
    location: const GeoPoint(5.977123, 116.072573),
  );

  static final _destinations = [
    MissionPoint(
      id: 'b',
      label: 'City Mall',
      address: 'City Mall, Jln Lintas, 88300 Kota Kinabalu, Sabah, Malaysia',
      location: const GeoPoint(5.96137, 116.0971866),
    ),
    MissionPoint(
      id: 'c',
      label: 'Sutera Harbour',
      address: 'Sutera Harbour, 88100 Kota Kinabalu, Sabah, Malaysia',
      location: const GeoPoint(5.968281, 116.0581489),
    ),
    MissionPoint(
      id: 'd',
      label: 'Imago Mall',
      address: 'KK Times Square, Phase 2, Off Coastal Highway, 88100 Kota Kinabalu, Sabah, Malaysia',
      location: const GeoPoint(5.9708621, 116.0663544),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _clock = ScaledClock(timeScale: useDeviceLocation ? 1 : 60);
    _location = useDeviceLocation
        ? GeolocatorLocationService()
        : SimulatedLocationService(
            initialPosition: _startingPoint.location,
            clock: _clock,
          );
    _places = _buildPlacesService();
    _kodLokasi = KodLokasiService(apiKey: kodLokasiApiKey);
    _engine = MissionEngine(
      startingPoint: _startingPoint,
      destinations: _destinations,
      directionsService: _buildDirectionsService(),
      locationService: _location,
      clock: _clock,
      missionId: 'm001',
      missionNumber: 'MSN-2026-0728',
      title: 'KK City Delivery Run',
      instructions: 'Deliver packages to all stops. Proof of delivery required at City Mall.',
      scheduledAt: DateTime(2026, 7, 28, 8, 0),
      reoptimizeInterval: useDeviceLocation
          ? const Duration(minutes: 5)
          : const Duration(minutes: 20),
    );
    _engine.initialize();
  }

  @override
  void dispose() {
    _engine.dispose();
    switch (_location) {
      case final SimulatedLocationService location:
        location.dispose();
      case final GeolocatorLocationService location:
        location.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mission Router',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B6E4B)),
        useMaterial3: true,
      ),
      home: MissionScreen(
        engine: _engine,
        places: _places,
        kodLokasi: _kodLokasi,
        dataSource: switch (_activeBackend) {
          'google' => 'Google APIs',
          'osrm' => 'OSRM + OSM',
          _ => 'Mock data',
        },
        liveApis: _activeBackend != 'mock',
      ),
    );
  }

  DirectionsService _buildDirectionsService() {
    return switch (_activeBackend) {
      'google' => GoogleDirectionsService(apiKey: googleMapsApiKey),
      'osrm' => OsrmDirectionsService(),
      _ => MockDirectionsService(),
    };
  }

  PlacesService _buildPlacesService() {
    return switch (_activeBackend) {
      'google' when _useGoogleApis => GooglePlacesService(apiKey: googleMapsApiKey),
      'mock' => const MockPlacesService(),
      _ => NominatimPlacesService(),
    };
  }
}
