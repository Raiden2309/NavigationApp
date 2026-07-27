import 'package:flutter/material.dart';

import 'models/geo.dart';
import 'models/mission.dart';
import 'services/directions_service.dart';
import 'services/location_service.dart';
import 'services/mission_clock.dart';
import 'services/mission_engine.dart';
import 'ui/mission_screen.dart';

/// Set to a Google Maps API key (e.g. `--dart-define=GOOGLE_MAPS_API_KEY=...`)
/// to route with the real Directions API instead of the offline mock.
const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

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
  late final SimulatedLocationService _location;
  late final MissionEngine _engine;

  @override
  void initState() {
    super.initState();
    final startingPoint = MissionPoint(
      id: 'a',
      label: 'Point A — Depot',
      location: const GeoPoint(1.2966, 103.7764),
    );
    _clock = ScaledClock(timeScale: 60);
    _location = SimulatedLocationService(
      initialPosition: startingPoint.location,
      clock: _clock,
    );
    _engine = MissionEngine(
      startingPoint: startingPoint,
      destinations: [
        MissionPoint(id: 'b', label: 'Point B — Warehouse', location: const GeoPoint(1.3210, 103.8198)),
        MissionPoint(id: 'c', label: 'Point C — Port gate', location: const GeoPoint(1.2644, 103.8220)),
        MissionPoint(id: 'd', label: 'Point D — Site yard', location: const GeoPoint(1.3400, 103.7800)),
      ],
      directionsService: googleMapsApiKey.isEmpty
          ? MockDirectionsService()
          : GoogleDirectionsService(apiKey: googleMapsApiKey),
      locationService: _location,
      clock: _clock,
    );
    _engine.initialize();
  }

  @override
  void dispose() {
    _engine.dispose();
    _location.dispose();
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
      home: MissionScreen(engine: _engine),
    );
  }
}
