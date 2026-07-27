import 'dart:math' as math;

/// Time-of-day congestion model used by [MockDirectionsService] to imitate the
/// `duration_in_traffic` that the Directions API returns for a departure time.
///
/// Weekday traffic peaks around the morning and evening rush hours; weekends
/// stay close to free flow.
class TrafficProfile {
  const TrafficProfile({
    this.morningPeak = const Duration(hours: 8, minutes: 15),
    this.eveningPeak = const Duration(hours: 18),
    this.morningPeakMultiplier = 1.7,
    this.eveningPeakMultiplier = 1.9,
    this.peakWidth = const Duration(minutes: 75),
    this.nightMultiplier = 0.85,
    this.weekendMultiplier = 1.1,
  });

  final Duration morningPeak;
  final Duration eveningPeak;
  final double morningPeakMultiplier;
  final double eveningPeakMultiplier;

  /// Standard deviation of the bell curve around each peak.
  final Duration peakWidth;

  final double nightMultiplier;
  final double weekendMultiplier;

  /// Travel time multiplier over free flow at [time].
  double multiplierAt(DateTime time) {
    final base = _isNight(time) ? nightMultiplier : 1.0;
    if (time.weekday == DateTime.saturday || time.weekday == DateTime.sunday) {
      return _isNight(time) ? base : weekendMultiplier;
    }
    final peak = math.max(
      _bell(time, morningPeak, morningPeakMultiplier),
      _bell(time, eveningPeak, eveningPeakMultiplier),
    );
    return base + (peak - 1);
  }

  bool _isNight(DateTime time) => time.hour >= 22 || time.hour < 6;

  double _bell(DateTime time, Duration peak, double peakMultiplier) {
    final minutesFromPeak =
        (Duration(hours: time.hour, minutes: time.minute).inMinutes - peak.inMinutes).abs();
    final sigma = peakWidth.inMinutes;
    final falloff = math.exp(-math.pow(minutesFromPeak / sigma, 2) / 2);
    return 1 + (peakMultiplier - 1) * falloff;
  }
}
