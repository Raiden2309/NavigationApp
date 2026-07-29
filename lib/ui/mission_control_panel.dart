import 'package:flutter/material.dart';

import '../models/mission.dart';
import '../services/kod_lokasi_service.dart';
import '../services/mission_engine.dart';
import '../services/places_service.dart';
import 'destination_editor.dart';
import 'formatting.dart';
import 'proof_dialog.dart';

class MissionControlPanel extends StatefulWidget {
  const MissionControlPanel({super.key, required this.engine, required this.places, this.kodLokasi});

  final MissionEngine engine;
  final PlacesService places;
  final KodLokasiService? kodLokasi;

  @override
  State<MissionControlPanel> createState() => _MissionControlPanelState();
}

class _MissionControlPanelState extends State<MissionControlPanel> {
  MissionEngine get engine => widget.engine;
  PlacesService get places => widget.places;

  List<MissionPoint> get _sortedDestinations {
    final routeOrder = engine.routeOrder;
    final sorted = List<MissionPoint>.from(engine.destinations)
      ..sort((a, b) {
        final ia = routeOrder.indexOf(a);
        final ib = routeOrder.indexOf(b);
        if (ia == -1 && ib == -1) return 0;
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (engine.isMissionFinalized)
          _MissionFinalizedCard(engine: engine),
        if (engine.hasRouteDeviationNotification)
          _DeviationNotificationCard(engine: engine),
        if (engine.title.isNotEmpty || engine.missionNumber.isNotEmpty)
          _MissionMetadataCard(engine: engine, theme: theme),
        if (!engine.isMissionFinalized)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(engine.optimizeOrder
                  ? 'Search for a place or tap the map to drop a destination. Point A is fixed; '
                      'the rest are re-ordered for the fastest route.'
                  : 'Search for a place or tap the map to drop a destination. Point A is fixed; '
                      'the rest are served in this order, so a new customer queues last.'),
            ),
          ),
        SwitchListTile(
          title: const Text('Optimize visiting order'),
          subtitle: Text(engine.optimizeOrder
              ? 'Stops are re-ordered for the shortest drive'
              : 'Stops keep their customer priority order'),
          value: engine.optimizeOrder,
          onChanged: engine.isMissionFinalized ? null : (value) => engine.setOptimizeOrder(value),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const CircleAvatar(child: Text('A')),
          title: Text(engine.startingPoint.label),
          subtitle: Text(engine.startingPoint.address ?? '${engine.startingPoint.location}'),
        ),
        const Divider(),
        for (final point in _sortedDestinations)
          _DestinationTile(engine: engine, places: places, kodLokasi: widget.kodLokasi, point: point),
        if (!engine.isMissionFinalized) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openEditor(context, engine, places, widget.kodLokasi, null),
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Add destination'),
          ),
        ],
      ],
    );
  }

}

class _MissionFinalizedCard extends StatelessWidget {
  const _MissionFinalizedCard({required this.engine});

  final MissionEngine engine;

  void _confirmVerifyMission(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Mission?'),
        content: const Text(
            'Review all proof and confirm this mission is complete.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Verify')),
        ],
      ),
    );
    if (confirmed == true) {
      engine.verifyMission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: engine.isMissionVerified
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.purple.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  engine.isMissionVerified ? Icons.verified : Icons.notifications_active,
                  color: engine.isMissionVerified ? Colors.green : Colors.purple,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engine.isMissionVerified ? 'Mission Verified' : 'Mission Completed',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: engine.isMissionVerified
                              ? Colors.green.shade700
                              : Colors.purple.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        engine.isMissionVerified
                            ? 'Verified at ${formatClockTime(engine.missionVerifiedAt!)}'
                            : 'Operator finalized at ${formatClockTime(engine.missionCompletedAt!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!engine.isMissionVerified) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _confirmVerifyMission(context),
                icon: const Icon(Icons.verified),
                label: const Text('Verify Mission'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviationNotificationCard extends StatelessWidget {
  const _DeviationNotificationCard({required this.engine});

  final MissionEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.amber.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                engine.routeDeviationMessage ?? 'Driver has deviated from the planned route.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close),
              onPressed: () => engine.dismissRouteDeviationNotification(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionMetadataCard extends StatelessWidget {
  const _MissionMetadataCard({required this.engine, required this.theme});

  final MissionEngine engine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (engine.title.isNotEmpty)
              Text(engine.title, style: theme.textTheme.titleMedium),
            if (engine.missionNumber.isNotEmpty)
              Text('Mission #${engine.missionNumber}',
                  style: theme.textTheme.bodySmall),
            if (engine.instructions != null &&
                engine.instructions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(engine.instructions!,
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.engine, required this.places, this.kodLokasi, required this.point});

  final MissionEngine engine;
  final PlacesService places;
  final KodLokasiService? kodLokasi;
  final MissionPoint point;

  @override
  Widget build(BuildContext context) {
    final locked = point.isCompleted || point.status == MissionPointStatus.onSite;
    final readOnly = engine.isMissionFinalized;
    final sequence = engine.routeOrder.indexOf(point);
    final hasProofs = point.proofs.isNotEmpty || point.checkedIn;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: point.isCompleted ? Colors.grey : null,
        child: Text(sequence >= 0 ? '${sequence + 1}' : '✓'),
      ),
      title: Row(
        children: [
          Expanded(child: Text(point.label)),
          if (point.priority != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'P${point.priority}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber),
              ),
            ),
          if (point.kodLokasi != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                point.kodLokasi!,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.teal),
              ),
            ),
        ],
      ),
      subtitle: Text('${point.address ?? point.location} · '
          '${formatDuration(point.dwellTime)} on site'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasProofs)
            IconButton(
              tooltip: 'View proof',
              icon: const Icon(Icons.visibility),
              onPressed: () => _showProof(context, point),
            ),
          if (!readOnly)
            PopupMenuButton<String>(
              tooltip: locked ? 'Stop is in progress or done' : 'Options',
              icon: const Icon(Icons.more_vert),
              enabled: !locked,
              onSelected: (value) => _onMenuSelected(context, value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'priority',
                  enabled: false,
                  child: Text(
                    'Priority',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
                _priorityMenuItem(1, '1 — Highest'),
                _priorityMenuItem(2, '2 — Medium'),
                _priorityMenuItem(3, '3 — Low'),
                _priorityMenuItem(null, 'None (optimized)'),
              ],
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _priorityMenuItem(int? level, String label) {
    final selected = point.priority == level;
    return PopupMenuItem(
      value: 'priority_$level',
      child: Row(
        children: [
          if (selected)
            const Icon(Icons.check, size: 16)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  void _onMenuSelected(BuildContext context, String value) {
    if (value == 'edit') {
      _openEditor(context, engine, places, kodLokasi, point);
    } else if (value == 'remove') {
      engine.removeDestination(point.id);
    } else if (value.startsWith('priority_')) {
      final levelStr = value.substring('priority_'.length);
      final level = int.tryParse(levelStr);
      engine.updateDestination(point.id, priority: level);
    }
  }

  void _showProof(BuildContext context, MissionPoint point) {
    showDialog(
      context: context,
      builder: (context) => ProofDialog(point: point),
    );
  }
}

Future<void> _openEditor(
  BuildContext context,
  MissionEngine engine,
  PlacesService places,
  KodLokasiService? kodLokasi,
  MissionPoint? point,
) async {
  final result = await showDialog<EditorResult>(
    context: context,
    builder: (context) => DestinationEditor(
      point: point,
      places: places,
      near: engine.operatorPosition ?? engine.startingPoint.location,
      kodLokasi: kodLokasi,
    ),
  );
  if (result == null) return;
  if (point == null) {
    await engine.addDestination(MissionPoint(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      label: result.label,
      location: result.location,
      address: result.address,
      dwellTime: result.dwellTime,
      kodLokasi: result.kodLokasi,
    ));
  } else {
    await engine.updateDestination(
      point.id,
      label: result.label,
      location: result.location,
      address: result.address,
      dwellTime: result.dwellTime,
      kodLokasi: result.kodLokasi,
    );
  }
}
