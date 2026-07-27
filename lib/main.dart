import 'package:flutter/material.dart';

import 'models/mission.dart';
import 'services/directions_service.dart';
import 'services/location_service.dart';
import 'services/mission_clock.dart';
import 'services/mission_engine.dart';
import 'services/places_service.dart';
import 'ui/mission_screen.dart';

/// Set to a Google Maps API key (e.g. `--dart-define=GOOGLE_MAPS_API_KEY=...`)
/// to route with the real, traffic-aware Directions API and search real places
/// instead of using the offline mocks.
const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// Track the real device with the platform geolocation API instead of the
/// simulated operator: `--dart-define=USE_DEVICE_LOCATION=true`.
const bool useDeviceLocation = bool.fromEnvironment('USE_DEVICE_LOCATION');

/// Which routing backend to use: `google`, `osrm` or `mock`. Defaults to
/// Google when a key is configured and to OSRM otherwise — OSRM routes on real
/// OpenStreetMap roads with no key and no quota, but has no traffic data, so
/// rush hour comes from the app's own [TrafficProfile].
const String routingBackend = String.fromEnvironment('ROUTING_BACKEND');

bool get useGoogleApis => googleMapsApiKey.isNotEmpty;

DirectionsService buildDirectionsService() {
  final backend = routingBackend.isNotEmpty
      ? routingBackend
      : useGoogleApis
          ? 'google'
          : 'osrm';
  return switch (backend) {
    'google' => GoogleDirectionsService(apiKey: googleMapsApiKey),
    'osrm' => OsrmDirectionsService(),
    _ => MockDirectionsService(),
  };
}

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

  /// Real dispatch sites; Point A is the depot the operator starts from.
  static final MissionPoint _startingPoint = _pointFor('a', singaporeLandmarks[0]);
  static final List<MissionPoint> _destinations = [
    _pointFor('b', singaporeLandmarks[3]),
    _pointFor('c', singaporeLandmarks[4]),
    _pointFor('d', singaporeLandmarks[6]),
  ];

  static MissionPoint _pointFor(String id, Place place) => MissionPoint(
        id: id,
        label: place.name,
        address: place.address,
        location: place.location,
      );

  @override
  void initState() {
    super.initState();
    // Real GPS moves in real time; the simulated operator can be sped up so a
    // 15 minute on-site allowance plays out in 15 seconds.
    _clock = ScaledClock(timeScale: useDeviceLocation ? 1 : 60);
    _location = useDeviceLocation
        ? GeolocatorLocationService()
        : SimulatedLocationService(
            initialPosition: _startingPoint.location,
            clock: _clock,
          );
    // Without a Google key, places still come from OpenStreetMap rather than
    // the built-in gazetteer, so any real address can be searched offline of
    // Google.
    _places = useGoogleApis
        ? GooglePlacesService(apiKey: googleMapsApiKey)
        : routingBackend == 'mock'
            ? const MockPlacesService()
            : NominatimPlacesService();
    _engine = MissionEngine(
      startingPoint: _startingPoint,
      destinations: _destinations,
      directionsService: buildDirectionsService(),
      locationService: _location,
      clock: _clock,
      // Measured on the mission clock, so the sped-up demo re-checks traffic
      // every 20 seconds of real time rather than every 20 minutes.
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
      home: MissionScreen(engine: _engine, places: _places, liveApis: useGoogleApis),
    );
  }
}
