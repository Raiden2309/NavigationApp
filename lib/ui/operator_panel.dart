import 'package:flutter/material.dart';

import '../models/mission.dart';
import '../services/mission_engine.dart';
import 'formatting.dart';

/// What the operator sees on the road: next stop, live ETAs and the on-site
/// countdown.
class OperatorPanel extends StatelessWidget {
  const OperatorPanel({super.key, required this.engine});

  final MissionEngine engine;

  @override
  Widget build(BuildContext context) {
    final now = engine.clock.now();
    final etas = engine.etas;
    final completion = engine.missionCompletionEta;
    final current = etas.isEmpty ? null : etas.first;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MissionSummary(
          completion: completion,
          now: now,
          remainingDistance: engine.remainingDistanceMeters,
          stopsLeft: etas.length,
          driveTime: engine.remainingDriveTime,
          trafficDelay: engine.remainingTrafficDelay,
          routeMissing: engine.routeOrder.isEmpty && engine.lastError != null,
          reoptimizedAt: engine.status == MissionStatus.planning ? null : engine.lastReoptimizedAt,
          reorderedStops: engine.lastReoptimizeChangedOrder,
          reoptimizeSaving: engine.lastReoptimizeSaving,
        ),
        const SizedBox(height: 12),
        if (current != null) _NextStopCard(engine: engine, eta: current, now: now),
        const SizedBox(height: 12),
        _Controls(engine: engine),
        const SizedBox(height: 20),
        Text('Route', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _StartTile(point: engine.startingPoint),
        for (var i = 0; i < etas.length; i++)
          _StopTile(eta: etas[i], sequence: i + 1, now: now),
        for (final point in engine.destinations.where((p) => p.isCompleted))
          _CompletedTile(point: point),
        if (engine.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Live data issue: ${engine.lastError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _MissionSummary extends StatelessWidget {
  const _MissionSummary({
    required this.completion,
    required this.now,
    required this.remainingDistance,
    required this.stopsLeft,
    required this.driveTime,
    required this.trafficDelay,
    required this.routeMissing,
    required this.reoptimizedAt,
    required this.reorderedStops,
    required this.reoptimizeSaving,
  });

  final DateTime? completion;
  final DateTime now;
  final double remainingDistance;
  final int stopsLeft;
  final Duration driveTime;
  final Duration trafficDelay;

  /// The last routing request failed, so there is no plan to show yet.
  final bool routeMissing;

  /// When the remaining route was last re-quoted against live traffic.
  final DateTime? reoptimizedAt;
  final bool reorderedStops;
  final Duration reoptimizeSaving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mission completion ETA', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              completion != null
                  ? formatClockTime(completion!)
                  : routeMissing
                      ? 'No route'
                      : 'Mission complete',
              style: theme.textTheme.headlineMedium,
            ),
            if (completion != null)
              Text('in ${formatDuration(completion!.difference(now))}',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('$stopsLeft stop(s) left · ${formatDistance(remainingDistance)} · '
                '${formatDuration(driveTime)} driving'),
            if (trafficDelay > Duration.zero)
              Row(
                children: [
                  const Icon(Icons.traffic, size: 16),
                  const SizedBox(width: 4),
                  Expanded(child: Text('${formatDuration(trafficDelay)} of that is traffic')),
                ],
              ),
            if (reoptimizedAt != null)
              Row(
                children: [
                  const Icon(Icons.autorenew, size: 16),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_reoptimizeLabel(reoptimizedAt!))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _reoptimizeLabel(DateTime at) {
    final checked = 'Traffic re-checked ${formatClockTime(at)}';
    if (reorderedStops) return '$checked · stops re-ordered';
    if (reoptimizeSaving.abs() < const Duration(minutes: 1)) return '$checked · route unchanged';
    final minutes = reoptimizeSaving.inMinutes;
    return minutes > 0 ? '$checked · ETA ${minutes}m earlier' : '$checked · ETA ${-minutes}m later';
  }
}

class _NextStopCard extends StatelessWidget {
  const _NextStopCard({required this.engine, required this.eta, required this.now});

  final MissionEngine engine;
  final StopEta eta;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSite = engine.status == MissionStatus.onSite;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(onSite ? 'On site at' : 'Next stop', style: theme.textTheme.labelLarge),
            Text(eta.point.label, style: theme.textTheme.titleLarge),
            if (eta.point.address != null)
              Text(eta.point.address!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (onSite) ...[
              Text('Task time left: ${formatDuration(eta.point.remainingDwell(now))}',
                  style: theme.textTheme.bodyLarge),
              LinearProgressIndicator(
                value: 1 -
                    eta.point.remainingDwell(now).inMilliseconds /
                        eta.point.dwellTime.inMilliseconds,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: engine.completeCurrentStop,
                icon: const Icon(Icons.check),
                label: const Text('Tasks complete — depart now'),
              ),
            ] else ...[
              Text('Arriving ${formatClockTime(eta.arrival)} '
                  '(${formatDuration(eta.arrival.difference(now))})'),
              Text('${formatDistance(eta.distanceMeters)} away'),
              Text('Departing ${formatClockTime(eta.departure)} after '
                  '${formatDuration(eta.point.dwellTime)} of tasks'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.engine});

  final MissionEngine engine;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        if (engine.status == MissionStatus.planning)
          FilledButton.icon(
            onPressed: engine.routeOrder.isEmpty ? null : engine.start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start mission'),
          ),
        if (engine.status == MissionStatus.enRoute) ...[
          OutlinedButton.icon(
            onPressed: engine.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
          OutlinedButton.icon(
            onPressed: engine.resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
        ],
      ],
    );
  }
}

class _StartTile extends StatelessWidget {
  const _StartTile({required this.point});

  final MissionPoint point;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const CircleAvatar(child: Text('A')),
      title: Text(point.label),
      subtitle: Text(point.address == null ? 'Starting point' : 'Starting point · ${point.address}'),
      trailing: point.completedAt == null
          ? null
          : Text('Departed ${formatClockTime(point.completedAt!)}'),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.eta, required this.sequence, required this.now});

  final StopEta eta;
  final int sequence;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final onSite = eta.point.status == MissionPointStatus.onSite;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: onSite ? Colors.orange : null,
        child: Text('$sequence'),
      ),
      title: Text(eta.point.label),
      subtitle: Text('ETA ${formatClockTime(eta.arrival)} · '
          'depart ${formatClockTime(eta.departure)} · '
          '${formatDistance(eta.distanceMeters)}'),
      trailing: Text(formatDuration(eta.arrival.difference(now))),
    );
  }
}

class _CompletedTile extends StatelessWidget {
  const _CompletedTile({required this.point});

  final MissionPoint point;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const CircleAvatar(
        backgroundColor: Colors.grey,
        child: Icon(Icons.check, size: 18, color: Colors.white),
      ),
      title: Text(point.label, style: const TextStyle(decoration: TextDecoration.lineThrough)),
      subtitle: point.arrivedAt == null
          ? null
          : Text('Arrived ${formatClockTime(point.arrivedAt!)} · '
              'departed ${point.completedAt == null ? '—' : formatClockTime(point.completedAt!)}'),
    );
  }
}
