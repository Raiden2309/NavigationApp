/// Clock used by the mission engine so simulated runs can be time-accelerated
/// while the production build stays on wall-clock time.
abstract class MissionClock {
  DateTime now();

  /// How many mission seconds pass per real second.
  double get timeScale;
}

class SystemClock implements MissionClock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  double get timeScale => 1;
}

/// Advances [timeScale] times faster than real time, so a 15 minute dwell can
/// be observed in seconds during a demo.
class ScaledClock implements MissionClock {
  ScaledClock({double timeScale = 60, DateTime? startTime})
      : _currentScale = timeScale,
        _virtualAnchor = startTime ?? DateTime.now(),
        _realAnchor = DateTime.now();

  double _currentScale;
  DateTime _virtualAnchor;
  DateTime _realAnchor;

  @override
  double get timeScale => _currentScale;

  set timeScale(double value) {
    _virtualAnchor = now();
    _realAnchor = DateTime.now();
    _currentScale = value;
  }

  @override
  DateTime now() {
    final elapsed = DateTime.now().difference(_realAnchor);
    return _virtualAnchor.add(
        Duration(microseconds: (elapsed.inMicroseconds * _currentScale).round()));
  }
}
