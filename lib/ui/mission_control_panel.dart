import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import '../services/mission_engine.dart';
import 'formatting.dart';

/// Mission operator tools: add, move, retime or drop any destination after
/// Point A. Every edit re-optimizes the remaining route immediately.
class MissionControlPanel extends StatelessWidget {
  const MissionControlPanel({super.key, required this.engine});

  final MissionEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Tap the map to drop a new destination. '
                'Point A is fixed; the visiting order for the rest is optimized automatically.'),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const CircleAvatar(child: Text('A')),
          title: Text(engine.startingPoint.label),
          subtitle: Text('${engine.startingPoint.location} · starting point'),
        ),
        const Divider(),
        for (final point in engine.destinations)
          _DestinationTile(engine: engine, point: point),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openEditor(context, engine, null),
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Add destination'),
        ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.engine, required this.point});

  final MissionEngine engine;
  final MissionPoint point;

  @override
  Widget build(BuildContext context) {
    final locked = point.isCompleted || point.status == MissionPointStatus.onSite;
    final sequence = engine.routeOrder.indexOf(point);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: point.isCompleted ? Colors.grey : null,
        child: Text(sequence >= 0 ? '${sequence + 1}' : '✓'),
      ),
      title: Text(point.label),
      subtitle: Text('${point.location} · ${formatDuration(point.dwellTime)} on site'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: locked ? 'Stop is in progress or done' : 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: locked ? null : () => _openEditor(context, engine, point),
          ),
          IconButton(
            tooltip: locked ? 'Stop is in progress or done' : 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: locked ? null : () => engine.removeDestination(point.id),
          ),
        ],
      ),
    );
  }
}

Future<void> _openEditor(BuildContext context, MissionEngine engine, MissionPoint? point) async {
  final result = await showDialog<_EditorResult>(
    context: context,
    builder: (context) => _DestinationEditor(point: point, fallback: engine.startingPoint.location),
  );
  if (result == null) return;
  if (point == null) {
    await engine.addDestination(MissionPoint(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      label: result.label,
      location: result.location,
      dwellTime: result.dwellTime,
    ));
  } else {
    await engine.updateDestination(
      point.id,
      label: result.label,
      location: result.location,
      dwellTime: result.dwellTime,
    );
  }
}

class _EditorResult {
  const _EditorResult(this.label, this.location, this.dwellTime);

  final String label;
  final GeoPoint location;
  final Duration dwellTime;
}

class _DestinationEditor extends StatefulWidget {
  const _DestinationEditor({required this.point, required this.fallback});

  final MissionPoint? point;
  final GeoPoint fallback;

  @override
  State<_DestinationEditor> createState() => _DestinationEditorState();
}

class _DestinationEditorState extends State<_DestinationEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label =
      TextEditingController(text: widget.point?.label ?? 'New destination');
  late final TextEditingController _lat = TextEditingController(
      text: (widget.point?.location ?? widget.fallback).latitude.toStringAsFixed(5));
  late final TextEditingController _lng = TextEditingController(
      text: (widget.point?.location ?? widget.fallback).longitude.toStringAsFixed(5));
  late final TextEditingController _dwell = TextEditingController(
      text: '${(widget.point?.dwellTime ?? defaultDwellTime).inMinutes}');

  @override
  void dispose() {
    _label.dispose();
    _lat.dispose();
    _lng.dispose();
    _dwell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.point == null ? 'Add destination' : 'Edit ${widget.point!.label}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
              validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _lat,
              decoration: const InputDecoration(labelText: 'Latitude'),
              validator: (value) => _validateRange(value, -90, 90),
            ),
            TextFormField(
              controller: _lng,
              decoration: const InputDecoration(labelText: 'Longitude'),
              validator: (value) => _validateRange(value, -180, 180),
            ),
            TextFormField(
              controller: _dwell,
              decoration: const InputDecoration(labelText: 'On-site minutes'),
              validator: (value) => _validateRange(value, 0, 600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              _EditorResult(
                _label.text.trim(),
                GeoPoint(double.parse(_lat.text), double.parse(_lng.text)),
                Duration(minutes: int.parse(_dwell.text)),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String? _validateRange(String? value, double min, double max) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null) return 'Enter a number';
    if (parsed < min || parsed > max) return 'Must be between $min and $max';
    return null;
  }
}
