---
name: testing-mission-router
description: How to run and end-to-end test the Mission Router Flutter app against the real Google Routes/Places APIs in a headless-desktop Chrome environment.
---

# Testing Mission Router (Flutter web + real Google APIs)

## Running the app

```bash
export PATH=/home/ubuntu/flutter/bin:$PATH   # Flutter SDK location on the test box
cd <repo>
flutter run -d web-server --web-port 8081 \
  --dart-define=GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_API_KEY
```

* First build takes ~60–90 s; poll `curl -s -o /dev/null -w "%{http_code}" http://localhost:8081`.
* Port 8080 may already be taken by another server on a shared box — pick a free port and open that
  URL in the already-running Chrome rather than assuming 8080 is your app.
* Do **not** pass `USE_DEVICE_LOCATION=true` unless real GPS exists; the default simulated operator
  runs on a 60× `ScaledClock`, which makes ETA/countdown changes observable within ~20 s.
* Never echo the key; pass it through `env` expansion only.

## Where the features live

* Live-API chip ("Google APIs" vs "Mock data"): app bar, driven by `useGoogleApis` in `lib/main.dart`.
* Place search: **Mission Control** tab → pencil icon on a stop, or "Add destination" → modal with
  "Search a place or address". 350 ms debounce, **3-character minimum** before any request.
* Traffic component and live ETA: **Operator** tab summary card ("X of that is traffic",
  "in Xh Ym"), plus "Start mission".

## Proving the search is really hitting Google

`MockPlacesService` matches a hard-coded 14-entry Singapore gazetteer (Jurong Port, Tuas Mega Port,
Marina Bay Sands, Changi …). Querying one of those names does **not** prove live APIs. Use a query
absent from that list (e.g. "Gardens by the Bay", "Jewel Changi", "Sentosa Cove") — suggestions for
those can only come from Places API (New).

## Known failure modes to check for (may already be fixed)

* **Silent plan failure on load**: `directions/v2:computeRoutes` can return
  `400 INVALID_ARGUMENT "Timestamp must be set to a future time"` because the departure timestamp is
  only sub-second in the future. The UI then shows "Mission complete · 0 stop(s) left" with no error
  (the error is stored then cleared by the next simulated position tick). Always hard-reload a few
  times and check the Network tab, not just the UI. Workaround to keep testing: save any destination
  edit — the 60× clock has moved on, so the re-plan succeeds.
* **Polyline corruption on web**: `decodePolyline` is correct on the Dart VM but produced
  out-of-range coordinates (e.g. longitude 212) in the JS build, which distorts the map and drags the
  simulated operator off-planet; that in turn makes place search fail with
  `Invalid value at 'location_bias.circle.center.longitude'`. Compare the browser map against a
  VM-side decode (`dart run` a small script in `tool/` importing
  `package:mission_router/services/directions_service.dart`) to tell the two apart.
* Sanity-check the key server-side before blaming the app:
  `curl -X POST https://places.googleapis.com/v1/places:autocomplete -H "X-Goog-Api-Key: $KEY" …`
  and the equivalent `routes.googleapis.com/directions/v2:computeRoutes` call. Only Routes API and
  Places API (New) are enabled; legacy Directions/Geocoding/Places return REQUEST_DENIED.
* `flutter run -d web-server` uses DDC; the console always contains a noisy dwds
  `_JsonMap is not a subtype of List<Object?>` error from `client.js` — it is unrelated to the app.

## Devin Secrets Needed

* `GOOGLE_MAPS_API_KEY` — Google Cloud key with Routes API and Places API (New) enabled, no HTTP
  referrer restriction (works from `http://localhost`).
