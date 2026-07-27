import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';

/// Maps geographic coordinates onto the canvas with an equirectangular
/// projection fitted to the mission bounds.
class MapProjection {
  MapProjection({required this.bounds, required this.size, this.padding = 36});

  final ({double minLat, double maxLat, double minLng, double maxLng}) bounds;
  final Size size;
  final double padding;

  double get _cosLat =>
      math.cos((bounds.minLat + bounds.maxLat) / 2 * math.pi / 180).abs().clamp(0.01, 1.0);

  double get _scale {
    final spanX = math.max((bounds.maxLng - bounds.minLng) * _cosLat, 1e-6);
    final spanY = math.max(bounds.maxLat - bounds.minLat, 1e-6);
    return math.min(
      (size.width - padding * 2) / spanX,
      (size.height - padding * 2) / spanY,
    );
  }

  Offset toScreen(GeoPoint point) {
    final centerLat = (bounds.minLat + bounds.maxLat) / 2;
    final centerLng = (bounds.minLng + bounds.maxLng) / 2;
    final dx = (point.longitude - centerLng) * _cosLat * _scale;
    final dy = (point.latitude - centerLat) * _scale;
    return Offset(size.width / 2 + dx, size.height / 2 - dy);
  }

  GeoPoint toGeo(Offset offset) {
    final centerLat = (bounds.minLat + bounds.maxLat) / 2;
    final centerLng = (bounds.minLng + bounds.maxLng) / 2;
    final dx = offset.dx - size.width / 2;
    final dy = size.height / 2 - offset.dy;
    return GeoPoint(centerLat + dy / _scale, centerLng + dx / (_scale * _cosLat));
  }
}

({double minLat, double maxLat, double minLng, double maxLng}) boundsOf(List<GeoPoint> points) {
  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;
  for (final point in points) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLng = math.min(minLng, point.longitude);
    maxLng = math.max(maxLng, point.longitude);
  }
  final latPad = math.max((maxLat - minLat) * 0.15, 0.002);
  final lngPad = math.max((maxLng - minLng) * 0.15, 0.002);
  return (
    minLat: minLat - latPad,
    maxLat: maxLat + latPad,
    minLng: minLng - lngPad,
    maxLng: maxLng + lngPad,
  );
}

/// Lightweight stand-in for the Google Maps widget: it draws the optimized
/// polyline, the stops and the live operator marker without needing an API key.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.startingPoint,
    required this.stops,
    required this.routeOrder,
    required this.polyline,
    this.operatorPosition,
    this.onMapTap,
  });

  final MissionPoint startingPoint;
  final List<MissionPoint> stops;
  final List<MissionPoint> routeOrder;
  final List<GeoPoint> polyline;
  final GeoPoint? operatorPosition;
  final ValueChanged<GeoPoint>? onMapTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final all = <GeoPoint>[
          startingPoint.location,
          for (final stop in stops) stop.location,
          ...polyline,
          ?operatorPosition,
        ];
        final projection = MapProjection(bounds: boundsOf(all), size: size);
        return GestureDetector(
          onTapUp: onMapTap == null
              ? null
              : (details) => onMapTap!(projection.toGeo(details.localPosition)),
          child: CustomPaint(
            size: size,
            painter: _RoutePainter(
              projection: projection,
              startingPoint: startingPoint,
              stops: stops,
              routeOrder: routeOrder,
              polyline: polyline,
              operatorPosition: operatorPosition,
              theme: Theme.of(context),
            ),
          ),
        );
      },
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.projection,
    required this.startingPoint,
    required this.stops,
    required this.routeOrder,
    required this.polyline,
    required this.operatorPosition,
    required this.theme,
  });

  final MapProjection projection;
  final MissionPoint startingPoint;
  final List<MissionPoint> stops;
  final List<MissionPoint> routeOrder;
  final List<GeoPoint> polyline;
  final GeoPoint? operatorPosition;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
    _paintPath(canvas, polyline, theme.colorScheme.primary.withValues(alpha: 0.85), 6);

    _paintStop(canvas, startingPoint, 'A', theme.colorScheme.tertiary, null);
    for (final stop in stops) {
      final sequence = routeOrder.indexOf(stop);
      final color = switch (stop.status) {
        MissionPointStatus.completed => Colors.grey,
        MissionPointStatus.onSite => Colors.orange,
        MissionPointStatus.enRoute => theme.colorScheme.primary,
        MissionPointStatus.pending => theme.colorScheme.secondary,
      };
      _paintStop(canvas, stop, stop.label.characters.first.toUpperCase(), color,
          sequence >= 0 ? sequence + 1 : null);
    }

    final operator = operatorPosition;
    if (operator != null) {
      final center = projection.toScreen(operator);
      canvas.drawCircle(center, 14, Paint()..color = Colors.blue.withValues(alpha: 0.2));
      canvas.drawCircle(center, 7, Paint()..color = Colors.blue);
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEFF3F1));
    final grid = Paint()
      ..color = const Color(0xFFDDE4E1)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  void _paintPath(Canvas canvas, List<GeoPoint> points, Color color, double width) {
    if (points.length < 2) return;
    final path = Path()..moveTo(
        projection.toScreen(points.first).dx, projection.toScreen(points.first).dy);
    for (final point in points.skip(1)) {
      final offset = projection.toScreen(point);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintStop(Canvas canvas, MissionPoint stop, String glyph, Color color, int? sequence) {
    final center = projection.toScreen(stop.location);
    canvas.drawCircle(center, 15, Paint()..color = color);
    canvas.drawCircle(
      center,
      15,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _paintText(canvas, glyph, center, const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold));
    if (sequence != null) {
      final badge = center + const Offset(14, -14);
      canvas.drawCircle(badge, 9, Paint()..color = Colors.black87);
      _paintText(canvas, '$sequence', badge,
          const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold));
    }
    _paintText(
      canvas,
      stop.label,
      center + const Offset(0, 26),
      TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
    );
  }

  void _paintText(Canvas canvas, String text, Offset center, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => true;
}
