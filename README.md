# Mission Router

Flutter mission-routing service: an operator is dispatched from **Point A** (starting point)
through a set of destinations, driving the optimal route, spending an allowance of
**15 minutes** at each stop, with the **mission completion ETA updated live**.

Destinations are real places, routed with the **Google Routes API**: the optimal visiting order,
traffic-aware leg durations, and each leg priced for the time it is actually driven — so a mission
that runs into the evening rush hour is estimated at rush hour speeds.

Without an API key the same interfaces are served by offline mocks (a gazetteer of real sites, a
time-of-day traffic model and a simulated operator), so the app can be demoed with no key and the
tests run without network access.

## What it does

| Requirement | Where |
| --- | --- |
| Point A is the start; the remaining points are served in customer priority order, or optimized on request | `DirectionsService.optimizedRoute(optimizeOrder: ...)` (`optimizeWaypointOrder` on the Routes API, `/table` + 2-opt on OSRM) |
| Live tracking of the operator | `LocationService` position stream, projected onto the planned polyline |
| Points after A can be added / re-prioritized / removed by a Mission Operator | `MissionEngine.addDestination` / `updateDestination` / `moveDestination` / `removeDestination` → immediate re-plan of the remaining stops |
| 15 minutes of on-site tasks per destination | `MissionPoint.dwellTime` (`defaultDwellTime`), started by the arrival geofence, editable per stop |
| Live, traffic-aware mission completion ETA | `MissionEngine.etas` / `missionCompletionEta`, recomputed on every position fix and tick |

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

Without a key the app routes on **OSRM** and searches places on **OpenStreetMap** (see below), and
runs an accelerated mission clock (`ScaledClock`, default 60x, switchable in the app bar) so a
15 minute dwell plays out in 15 seconds. The **Operator** tab is the driver's live view; the
**Mission Control** tab edits the destinations — search for a place or tap the map to drop one.

## Visiting order

Stops are driven in the order the mission operator lists them — customer priority — so a
destination added mid-mission queues last. The arrows on each stop in Mission Control move it up
or down that queue; a stop already being served keeps its place. **Optimize visiting order** in
Mission Control hands the ordering to the router instead (`MissionEngine.optimizeOrder`), which
re-orders the pending stops for the fastest route and keeps doing so on the re-optimization
interval.

## Routing backends

`--dart-define=ROUTING_BACKEND=google|osrm|mock` picks the backend; the default is `google` when a
key is set and `osrm` otherwise.

| Backend | Roads and times | Traffic | Needs |
| --- | --- | --- | --- |
| `google` | Routes API | live + predicted, per leg | API key, quota |
| `osrm` | real OSM roads via `router.project-osrm.org` | none from OSRM — `TrafficProfile` rush-hour model applied per leg | nothing |
| `mock` | synthetic curved roads | `TrafficProfile` | nothing, works offline |

```bash
flutter run -d chrome --dart-define=ROUTING_BACKEND=osrm
```

OSRM is the no-key stand-in for Google: `OsrmDirectionsService` takes the visiting order from one
`/table` travel-time matrix (nearest-neighbour + 2-opt — the demo server's `/trip` optimizes a
*round* trip, which a delivery run is not) and the geometry from one `/route` request with
`steps=true`, stitching each leg's steps into its polyline. Because OSRM has no traffic data its
durations are free flow, so `duration` is the free-flow time scaled by `TrafficProfile` for the
time that leg is predicted to be driven — the same rush-hour stacking as the Google backend, from
a model rather than from Google. Place search falls back to Nominatim
(`NominatimPlacesService`), which returns real names, addresses and coordinates with no key; its
usage policy allows about one request a second, which the search box's debounce respects.

## Real Google APIs

```bash
flutter run -d chrome \
  --dart-define=GOOGLE_MAPS_API_KEY=your_key \
  --dart-define=USE_DEVICE_LOCATION=true      # optional: track the real device
```

Enable **Routes API** and **Places API (New)** on the Google Cloud project (the legacy Directions,
Geocoding and Places endpoints are not enabled for projects created after March 2025) and restrict
the key to those two APIs. Both APIs send CORS headers, so web builds call them directly — no
proxy needed. The key is only read from `--dart-define`, never committed.

### Traffic and rush hour

`GoogleDirectionsService` calls `routes.googleapis.com/directions/v2:computeRoutes`:

- `optimizeWaypointOrder: true` returns the optimal visiting order
  (`optimizedIntermediateWaypointIndex`) for the stops after Point A.
- `routingPreference: TRAFFIC_AWARE` (the API rejects `TRAFFIC_AWARE_OPTIMAL` together with
  waypoint optimization; single-leg requests do use `TRAFFIC_AWARE_OPTIMAL`).
- `duration` is the traffic-aware travel time and `staticDuration` the same route without traffic;
  the difference is surfaced as the traffic delay in the operator view.
- **Each leg is re-quoted with its own `departureTime`** — the predicted arrival at the previous
  stop plus that stop's 15 minute allowance. One request prices the whole route from a single
  departure, which would quote the last leg with the traffic of the first; a mission leaving the
  depot at 16:00 really drives its final leg at 18:30, so that leg is priced for 18:30.
- Departure times in the past are clamped to now, and a failed re-quote keeps the estimate from
  the planning request instead of failing the mission.

Measured against the live API for the demo mission (Jurong Port → Keppel Distripark → Changi
Airfreight → Woodlands Checkpoint), departing 18:00 SGT: 108 min with traffic vs 87 min free flow.

`tool/live_check.dart` prints the optimized order and per-leg traffic vs free-flow durations:

```bash
GOOGLE_MAPS_API_KEY=... dart run tool/live_check.dart
```

### Places

`GooglePlacesService` uses Places Autocomplete (New) for the search box, Place Details for the
coordinates and address, and `places:searchNearby` to name a pin dropped on the map. Offline, the
same interface is served by `NominatimPlacesService` (OpenStreetMap) or, on the `mock` backend, by
`MockPlacesService` over a list of real Singapore sites.

### Live tracking

`GeolocatorLocationService` wraps the platform geolocation API (GPS on mobile, the browser
geolocation API on web): it checks that location services are on, requests permission, and streams
fixes with a 10 m distance filter. A denied permission surfaces in the operator view instead of
breaking the mission. Android permissions are declared in `AndroidManifest.xml`; add
`NSLocationWhenInUseUsageDescription` when adding the iOS target.

Map: `RouteMap` is a `CustomPainter` stand-in that draws the polyline, the stops and the live
operator marker. Replace it with `GoogleMap` from `google_maps_flutter`, feeding
`engine.plan.fullPolyline` into a `Polyline` and the stops into `Marker`s.

## Layout

```
lib/
  models/       geo.dart (distance/projection maths), mission.dart (MissionPoint, RouteLeg, RoutePlan)
  services/     directions_service.dart (mock + Routes API + OSRM), places_service.dart (mock +
                Places API + Nominatim),
                location_service.dart (simulated + geolocator), traffic_profile.dart (mock rush hour),
                mission_clock.dart, mission_engine.dart (state, arrival, dwell, live ETAs)
  ui/           mission_screen.dart, operator_panel.dart, mission_control_panel.dart, route_map.dart
test/           geo, directions, traffic-aware routing, mission engine and widget tests
tool/           live_check.dart (smoke-checks the real APIs with a key)
```
