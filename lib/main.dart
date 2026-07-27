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

bool get useGoogleApis => googleMapsApiKey.isNotEmpty;

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
    _places = useGoogleApis
        ? GooglePlacesService(apiKey: googleMapsApiKey)
        : const MockPlacesService();
    _engine = MissionEngine(
      startingPoint: _startingPoint,
      destinations: _destinations,
      directionsService: useGoogleApis
          ? GoogleDirectionsService(apiKey: googleMapsApiKey)
          : MockDirectionsService(),
      locationService: _location,
      clock: _clock,
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
