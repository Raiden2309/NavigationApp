# Mission Router

Flutter mission-routing service: an operator is dispatched from **Point A** (starting point)
through a set of destinations, driving the optimal route, spending an allowance of
**15 minutes** at each stop, with the **mission completion ETA updated live**.

The app runs fully offline against mocked Google Maps / geolocation providers, so it can be
demoed without an API key. Both providers sit behind interfaces and swap to the real APIs
without touching the mission logic.

## What it does

| Requirement | Where |
| --- | --- |
| Point A is the start; the route through the remaining points is optimized | `DirectionsService.optimizedRoute` (`waypoints=optimize:true` on the real API, nearest-neighbour + 2-opt in the mock) |
| Live tracking of the operator | `LocationService` position stream, projected onto the planned polyline |
| Points after A can be added / moved / removed by a Mission Operator | `MissionEngine.addDestination` / `updateDestination` / `removeDestination` → immediate re-optimization of the remaining stops |
| 15 minutes of on-site tasks per destination | `MissionPoint.dwellTime` (`defaultDwellTime`), started by the arrival geofence, editable per stop |
| Live mission completion ETA | `MissionEngine.etas` / `missionCompletionEta`, recomputed on every position fix and tick |

Behavioural details:

- Arrival is detected when a fix lands within `arrivalRadiusMeters` (40 m) of the next stop; the
  on-site countdown starts then, and the operator can depart early with *Tasks complete*.
- ETAs stack: `arrival(n) = now + remaining drive time + Σ remaining on-site time of stops before n`.
  The mission completion ETA is the departure time from the last stop.
- Editing the destinations re-optimizes only what is left to visit, from the operator's current
  position. A stop that is currently being served is anchored first and cannot be removed.

## Running

```bash
flutter pub get
flutter run -d chrome        # or any device
flutter test
```

The demo runs on an accelerated mission clock (`ScaledClock`, default 60x, switchable in the app
bar) so a 15 minute dwell plays out in 15 seconds. The **Operator** tab is the driver's live view;
the **Mission Control** tab edits the destinations — tap the map to drop a new one.

## Switching to the real Google APIs

Routing: pass a key and the real Directions client is used instead of the mock.

```bash
flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key
```

`GoogleDirectionsService` requests the route with `waypoints=optimize:true` and
`departure_time=now`, so Google returns both the optimal visiting order (`waypoint_order`) and
traffic-aware leg durations (`duration_in_traffic`).

Tracking: implement `LocationService` on top of the platform geolocation API (e.g. the
`geolocator` package — see the doc comment on `LocationService`) and pass it to `MissionEngine`
instead of `SimulatedLocationService`. Nothing else changes.

Map: `RouteMap` is a `CustomPainter` stand-in that draws the polyline, the stops and the live
operator marker. Replace it with `GoogleMap` from `google_maps_flutter`, feeding
`engine.plan.fullPolyline` into a `Polyline` and the stops into `Marker`s.

## Layout

```
lib/
  models/       geo.dart (distance/projection maths), mission.dart (MissionPoint, RouteLeg, RoutePlan)
  services/     directions_service.dart (mock + Google), location_service.dart (simulated + real),
                mission_clock.dart, mission_engine.dart (state, arrival, dwell, live ETAs)
  ui/           mission_screen.dart, operator_panel.dart, mission_control_panel.dart, route_map.dart
test/           geo, directions, mission engine (arrival, dwell, re-planning) and widget tests
```
