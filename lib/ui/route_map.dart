import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../models/geo.dart';
import '../models/mission.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.startingPoint,
    required this.stops,
    required this.routeOrder,
    required this.polyline,
    required this.travelledMeters,
    this.operatorPosition,
    this.onMapTap,
  });

  final MissionPoint startingPoint;
  final List<MissionPoint> stops;
  final List<MissionPoint> routeOrder;
  final List<GeoPoint> polyline;
  final double travelledMeters;
  final GeoPoint? operatorPosition;
  final void Function(GeoPoint)? onMapTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Convert GeoPoints to LatLng for flutter_map
    final allLatLongs = polyline
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    // Split path into driven vs remaining segments
    final (drivenPoints, aheadPoints) = splitPath(polyline, travelledMeters);
    
    final drivenLatLngs = drivenPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
        
    final aheadLatLngs = aheadPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    // Determine initial center
    final initialCenter = allLatLongs.isNotEmpty
        ? allLatLongs.first
        : LatLng(startingPoint.location.latitude, startingPoint.location.longitude);

    return FlutterMap(
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14.0,
      ),
      children: [
        // 1. Base Map Tile Layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.mission_router',
          tileProvider: CancellableNetworkTileProvider(),
        ),

        // 2. Polyline Layer (Driven & Remaining routes)
        PolylineLayer(
          polylines: [
            if (drivenLatLngs.length >= 2)
              Polyline(
                points: drivenLatLngs,
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                strokeWidth: 6.0,
              ),
            if (aheadLatLngs.length >= 2)
              Polyline(
                points: aheadLatLngs,
                color: theme.colorScheme.primary,
                strokeWidth: 6.0,
              ),
          ],
        ),

        // 3. Markers Layer (Starting Point, Mission Stops, Operator)
        MarkerLayer(
          markers: [
            // Starting Point Pin
            _buildStopMarker(
              point: startingPoint,
              glyph: 'A',
              color: _colorFor(startingPoint, theme),
              sequence: null,
            ),

            // Mission Stop Pins
            ...stops.map((stop) {
              final sequence = routeOrder.indexOf(stop);
              final glyph = stop.label.isNotEmpty
                  ? stop.label.characters.first.toUpperCase()
                  : '?';
              return _buildStopMarker(
                point: stop,
                glyph: glyph,
                color: _colorFor(stop, theme),
                sequence: sequence >= 0 ? sequence + 1 : null,
              );
            }),

            // Operator Marker
            if (operatorPosition != null)
              Marker(
                point: LatLng(
                  operatorPosition!.latitude,
                  operatorPosition!.longitude,
                ),
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withValues(alpha: 0.25),
                  ),
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Marker _buildStopMarker({
    required MissionPoint point,
    required String glyph,
    required Color color,
    required int? sequence,
  }) {
    final location = LatLng(point.location.latitude, point.location.longitude);

    return Marker(
      point: location,
      width: 70,
      height: 70,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Main Pin Circle
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                glyph,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Sequence Badge
          if (sequence != null)
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black87,
                ),
                child: Center(
                  child: Text(
                    '$sequence',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          // Label Text below pin
          Positioned(
            bottom: 2,
            child: Text(
              point.label,
              style: TextStyle(
                color: Colors.black.withValues(alpha: point.isCompleted ? 0.4 : 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(MissionPoint point, ThemeData theme) {
    return switch (point.status) {
      MissionPointStatus.completed => Colors.grey,
      MissionPointStatus.onSite => Colors.orange,
      MissionPointStatus.enRoute => theme.colorScheme.primary,
      MissionPointStatus.pending =>
        point == startingPoint ? theme.colorScheme.tertiary : theme.colorScheme.secondary,
    };
  }
}