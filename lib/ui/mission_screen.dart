import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import '../services/kod_lokasi_service.dart';
import '../services/mission_clock.dart';
import '../services/mission_engine.dart';
import '../services/places_service.dart';
import 'formatting.dart';
import 'operator_panel.dart';
import 'mission_control_panel.dart';
import 'route_map.dart';

/// Splits the app into the live operator view and the mission operator's
/// editor for the destinations after Point A.
class MissionScreen extends StatefulWidget {
  const MissionScreen({
    super.key,
    required this.engine,
    required this.places,
    this.kodLokasi,
    this.dataSource = 'Mock data',
    this.liveApis = false,
  });

  final MissionEngine engine;
  final PlacesService places;
  final KodLokasiService? kodLokasi;

  /// Where roads and places come from, e.g. `Google APIs` or `OSRM + OSM`.
  final String dataSource;

  /// Whether real network services are in use rather than the offline mocks.
  final bool liveApis;

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  MissionEngine get engine => widget.engine;

  bool get _editing => _tabs.index == 1;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mission Router'),
            backgroundColor: theme.colorScheme.inversePrimary,
            actions: [
              Chip(
                avatar: Icon(widget.liveApis ? Icons.cloud_done : Icons.cloud_off, size: 18),
                label: Text(widget.dataSource),
              ),
              const SizedBox(width: 12),
              _StatusChip(status: engine.status),
              const SizedBox(width: 12),
              _ClockControl(clock: engine.clock),
              const SizedBox(width: 12),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final map = RouteMap(
                startingPoint: engine.startingPoint,
                stops: engine.destinations,
                routeOrder: engine.routeOrder,
                polyline: engine.plan.fullPolyline,
                travelledMeters: engine.travelledDistanceMeters,
                operatorPosition: engine.operatorPosition,
                onMapTap: _editing ? _addPointAt : null,
              );
              final panel = _Panel(tabs: _tabs, engine: engine, places: widget.places, kodLokasi: widget.kodLokasi);
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    SizedBox(height: constraints.maxHeight * 0.42, child: map),
                    Expanded(child: panel),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: map),
                  SizedBox(width: 420, child: panel),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Map taps drop a real place: the coordinate is reverse geocoded so the stop
  /// carries a name and address rather than a bare latitude/longitude.
  Future<void> _addPointAt(GeoPoint location) async {
    Place? place;
    try {
      place = await widget.places.reverseGeocode(location);
    } catch (_) {
      place = null;
    }
    final nextLetter = String.fromCharCode(
      'A'.codeUnitAt(0) + (engine.destinations.length + 1).clamp(0, 25),
    );
    await engine.addDestination(MissionPoint(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      label: place?.name ?? 'Point $nextLetter',
      address: place?.address,
      location: location,
    ));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.tabs, required this.engine, required this.places, this.kodLokasi});

  final TabController tabs;
  final MissionEngine engine;
  final PlacesService places;
  final KodLokasiService? kodLokasi;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'Operator', icon: Icon(Icons.local_shipping)),
            Tab(text: 'Mission Control', icon: Icon(Icons.edit_location_alt)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              OperatorPanel(engine: engine),
              MissionControlPanel(engine: engine, places: places, kodLokasi: kodLokasi),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MissionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      MissionStatus.planning => ('Planning', Colors.blueGrey),
      MissionStatus.enRoute => ('En route', Colors.green),
      MissionStatus.onSite => ('On site', Colors.orange),
      MissionStatus.completed => ('Completed', Colors.purple),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
    );
  }
}

/// Lets a demo run at accelerated mission time so the 15 minute on-site
/// allowance is observable within seconds.
class _ClockControl extends StatelessWidget {
  const _ClockControl({required this.clock});

  final MissionClock clock;

  @override
  Widget build(BuildContext context) {
    final scaled = clock;
    if (scaled is! ScaledClock) {
      return Text(formatClockTimeWithSeconds(clock.now()));
    }
    return Row(
      children: [
        Text(formatClockTimeWithSeconds(scaled.now())),
        const SizedBox(width: 8),
        DropdownButton<double>(
          value: scaled.timeScale,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 1.0, child: Text('1x')),
            DropdownMenuItem(value: 10.0, child: Text('10x')),
            DropdownMenuItem(value: 60.0, child: Text('60x')),
            DropdownMenuItem(value: 300.0, child: Text('300x')),
          ],
          onChanged: (value) {
            if (value != null) scaled.timeScale = value;
          },
        ),
      ],
    );
  }
}
