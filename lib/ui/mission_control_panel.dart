import 'package:flutter/material.dart';

import '../models/mission.dart';
import '../services/mission_engine.dart';
import '../services/places_service.dart';
import 'destination_editor.dart';
import 'formatting.dart';
import 'proof_dialog.dart';

class MissionControlPanel extends StatefulWidget {
  const MissionControlPanel({super.key, required this.engine, required this.places});

  final MissionEngine engine;
  final PlacesService places;

  @override
  State<MissionControlPanel> createState() => _MissionControlPanelState();
}

class _MissionControlPanelState extends State<MissionControlPanel> {
  MissionEngine get engine => widget.engine;
  PlacesService get places => widget.places;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (engine.isMissionFinalized)
          _MissionFinalizedCard(engine: engine),
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
        for (final point in engine.destinations)
          _DestinationTile(engine: engine, places: places, point: point),
        if (!engine.isMissionFinalized) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openEditor(context, engine, places, null),
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
  const _DestinationTile({required this.engine, required this.places, required this.point});

  final MissionEngine engine;
  final PlacesService places;
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
      title: Text(point.label),
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
          if (!readOnly && !engine.optimizeOrder) ...[
            IconButton(
              tooltip: 'Higher priority',
              icon: const Icon(Icons.arrow_upward),
              onPressed: locked ? null : () => engine.moveDestination(point.id, -1),
            ),
            IconButton(
              tooltip: 'Lower priority',
              icon: const Icon(Icons.arrow_downward),
              onPressed: locked ? null : () => engine.moveDestination(point.id, 1),
            ),
          ],
          if (!readOnly) ...[
            IconButton(
              tooltip: locked ? 'Stop is in progress or done' : 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: locked ? null : () => _openEditor(context, engine, places, point),
            ),
            IconButton(
              tooltip: locked ? 'Stop is in progress or done' : 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: locked ? null : () => engine.removeDestination(point.id),
            ),
          ],
        ],
      ),
    );
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
  MissionPoint? point,
) async {
  final result = await showDialog<EditorResult>(
    context: context,
    builder: (context) => DestinationEditor(
      point: point,
      places: places,
      near: engine.operatorPosition ?? engine.startingPoint.location,
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
    ));
  } else {
    await engine.updateDestination(
      point.id,
      label: result.label,
      location: result.location,
      address: result.address,
      dwellTime: result.dwellTime,
    );
  }
}
