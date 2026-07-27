import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../models/geo.dart';
import 'mission_clock.dart';

/// A single fix from the device's geolocation provider.
class OperatorPosition {
  const OperatorPosition({
    required this.point,
    required this.speedMetersPerSecond,
    required this.headingDegrees,
    required this.timestamp,
  });

  final GeoPoint point;
  final double speedMetersPerSecond;
  final double headingDegrees;
  final DateTime timestamp;
}

/// Live position feed for the operator's device.
abstract class LocationService {
  Stream<OperatorPosition> get positions;

  OperatorPosition? get lastPosition;

  Future<void> start();

  Future<void> stop();
}

/// Tracks the operator with the platform geolocation API (GPS on mobile, the
/// browser geolocation API on web).
class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    this.distanceFilterMeters = 10,
    this.accuracy = LocationAccuracy.high,
  });

  /// Minimum movement before a new fix is emitted; keeps a parked vehicle from
  /// flooding the mission engine with jitter.
  final int distanceFilterMeters;

  final LocationAccuracy accuracy;

  final StreamController<OperatorPosition> _controller =
      StreamController<OperatorPosition>.broadcast();
  StreamSubscription<Position>? _subscription;
  OperatorPosition? _last;

  @override
  Stream<OperatorPosition> get positions => _controller.stream;

  @override
  OperatorPosition? get lastPosition => _last;

  @override
  Future<void> start() async {
    if (_subscription != null) return;
    await _ensurePermission();
    _emit(await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: accuracy),
    ));
    _subscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen(_emit, onError: _controller.addError);
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailableException('Location services are turned off');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationUnavailableException('Location permission denied');
    }
  }

  void _emit(Position position) {
    _last = OperatorPosition(
      point: GeoPoint(position.latitude, position.longitude),
      speedMetersPerSecond: position.speed,
      headingDegrees: position.heading,
      timestamp: position.timestamp,
    );
    _controller.add(_last!);
  }

  void dispose() {
    unawaited(stop());
    _controller.close();
  }
}

class LocationUnavailableException implements Exception {
  const LocationUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'LocationUnavailableException: $message';
}

/// Drives a fake operator along the planned route so the app can be exercised
/// without a device or an API key.
class SimulatedLocationService implements LocationService {
  SimulatedLocationService({
    required GeoPoint initialPosition,
    MissionClock? clock,
    this.speedKmh = 40,
    this.tickInterval = const Duration(milliseconds: 250),
    this.gpsNoiseMeters = 6,
    int seed = 11,
  })  : _clock = clock ?? const SystemClock(),
        _random = math.Random(seed) {
    _lastPosition = OperatorPosition(
      point: initialPosition,
      speedMetersPerSecond: 0,
      headingDegrees: 0,
      timestamp: _clock.now(),
    );
    _truePosition = initialPosition;
  }

  final MissionClock _clock;
  final double speedKmh;
  final Duration tickInterval;
  final double gpsNoiseMeters;
  final math.Random _random;
  final StreamController<OperatorPosition> _controller =
      StreamController<OperatorPosition>.broadcast();

  Timer? _timer;
  DateTime? _lastTick;
  List<GeoPoint> _path = const [];
  double _travelled = 0;
  bool _moving = false;
  late GeoPoint _truePosition;
  OperatorPosition? _lastPosition;

  @override
  Stream<OperatorPosition> get positions => _controller.stream;

  @override
  OperatorPosition? get lastPosition => _lastPosition;

  /// True position without GPS noise, used by the map to draw a stable marker.
  GeoPoint get truePosition => _truePosition;

  bool get isMoving => _moving;

  @override
  Future<void> start() async {
    _lastTick = _clock.now();
    _timer ??= Timer.periodic(tickInterval, (_) => _tick());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _moving = false;
  }

  /// Puts the simulated operator on [path], keeping it parked until [resume].
  void followPath(List<GeoPoint> path) {
    _path = path;
    _travelled = path.isEmpty ? 0 : distanceAlongPath(path, _truePosition);
  }

  void pause() => _moving = false;

  void resume() {
    _lastTick = _clock.now();
    _moving = true;
  }

  void _tick() {
    final now = _clock.now();
    final last = _lastTick ?? now;
    _lastTick = now;
    if (!_moving || _path.length < 2) {
      _emit(_truePosition, 0, _lastPosition?.headingDegrees ?? 0, now);
      return;
    }
    final elapsed = now.difference(last).inMicroseconds / Duration.microsecondsPerSecond;
    final speedMps = speedKmh * 1000 / 3600;
    final total = polylineLength(_path);
    _travelled = math.min(total, _travelled + speedMps * elapsed);
    final next = pointAlongPath(_path, _travelled);
    final heading = _truePosition.bearingTo(next);
    _truePosition = next;
    if (_travelled >= total) _moving = false;
    _emit(next, _moving ? speedMps : 0, heading, now);
  }

  void _emit(GeoPoint point, double speed, double heading, DateTime timestamp) {
    final noisy = _withNoise(point);
    final position = OperatorPosition(
      point: noisy,
      speedMetersPerSecond: speed,
      headingDegrees: heading,
      timestamp: timestamp,
    );
    _lastPosition = position;
    if (!_controller.isClosed) _controller.add(position);
  }

  GeoPoint _withNoise(GeoPoint point) {
    if (gpsNoiseMeters <= 0) return point;
    final radius = _random.nextDouble() * gpsNoiseMeters;
    final angle = _random.nextDouble() * 2 * math.pi;
    const metersPerDegree = 111320.0;
    final dLat = radius * math.sin(angle) / metersPerDegree;
    final dLng = radius *
        math.cos(angle) /
        (metersPerDegree * math.cos(point.latitude * math.pi / 180));
    return GeoPoint(point.latitude + dLat, point.longitude + dLng);
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
