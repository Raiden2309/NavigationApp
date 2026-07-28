import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import '../services/mission_engine.dart';
import '../services/places_service.dart';
import 'formatting.dart';

/// Mission operator tools: add, re-prioritize, retime or drop any destination
/// after Point A. Every edit re-plans the remaining route immediately.
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
        // Mission finalized notification + actions
        if (engine.isMissionFinalized)
          Card(
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!engine.isMissionVerified)
                        FilledButton.icon(
                          onPressed: () => _verifyMission(context),
                          icon: const Icon(Icons.verified),
                          label: const Text('Verify Mission'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.green),
                        ),
                      if (engine.isMissionVerified)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            avatar: const Icon(Icons.check_circle, size: 18, color: Colors.green),
                            label: const Text('Verified'),
                            backgroundColor: Colors.green.withValues(alpha: 0.1),
                          ),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _contactOperator(context),
                        icon: const Icon(Icons.phone),
                        label: const Text('Contact Operator'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        // Mission metadata card
        if (engine.title.isNotEmpty || engine.missionNumber.isNotEmpty)
          Card(
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
          ),
        // Instruction card — hidden when finalized (read-only)
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
        // Optimize switch — disabled when finalized
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
        // Add destination — hidden when finalized
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

  void _verifyMission(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Mission?'),
        content: const Text(
          'Confirm that all proof has been reviewed and the mission is verified as complete.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      engine.verifyMission();
    }
  }

  void _contactOperator(BuildContext context) async {
    final method = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Contact Operator'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'call'),
            child: const Row(
              children: [
                Icon(Icons.phone, size: 20),
                SizedBox(width: 12),
                Text('Call operator'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'message'),
            child: const Row(
              children: [
                Icon(Icons.message, size: 20),
                SizedBox(width: 12),
                Text('Send message'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'email'),
            child: const Row(
              children: [
                Icon(Icons.email, size: 20),
                SizedBox(width: 12),
                Text('Send email'),
              ],
            ),
          ),
        ],
      ),
    );
    if (method != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Operator contacted via $method'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
      builder: (context) => _ProofDialog(point: point),
    );
  }
}

class _ProofDialog extends StatelessWidget {
  const _ProofDialog({required this.point});

  final MissionPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Proof — ${point.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stop location — show address, fall back to coordinates
              _ProofRow(
                icon: Icons.place,
                label: 'Stop location',
                value: point.address ??
                    '${point.location.latitude.toStringAsFixed(6)}, ${point.location.longitude.toStringAsFixed(6)}',
              ),
              if (point.arrivedAt != null)
                _ProofRow(
                  icon: Icons.location_on,
                  label: 'Arrived',
                  value: formatClockTime(point.arrivedAt!),
                ),
              if (point.checkedIn)
                _ProofRow(
                  icon: Icons.fingerprint,
                  label: 'Checked in',
                  value: formatClockTime(point.checkedInAt!),
                ),
              if (point.completedAt != null)
                _ProofRow(
                  icon: Icons.check_circle,
                  label: 'Completed',
                  value: formatClockTime(point.completedAt!),
                ),
              if (point.proofs.isEmpty && !point.checkedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No proof captured yet.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                ),
              for (final proof in point.proofs) ...[
                const Divider(),
                switch (proof.type) {
                  ProofType.checkin => _ProofRow(
                      icon: Icons.fingerprint,
                      label: 'Check-in',
                      value: formatClockTime(proof.capturedAt),
                    ),
                  ProofType.photo => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProofRow(
                          icon: Icons.camera_alt,
                          label: 'Photo',
                          value: proof.fileUrl ?? 'unknown',
                        ),
                        if (proof.location != null)
                          _ProofRow(
                            icon: Icons.gps_fixed,
                            label: 'GPS',
                            value:
                                '${proof.location!.latitude.toStringAsFixed(6)}, ${proof.location!.longitude.toStringAsFixed(6)}',
                          ),
                      ],
                    ),
                  ProofType.note => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProofRow(
                          icon: Icons.note,
                          label: 'Note',
                          value: formatClockTime(proof.capturedAt),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '"${proof.note}"',
                          style:
                              theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                        ),
                        if (proof.location != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _ProofRow(
                              icon: Icons.gps_fixed,
                              label: 'GPS',
                              value:
                                  '${proof.location!.latitude.toStringAsFixed(6)}, ${proof.location!.longitude.toStringAsFixed(6)}',
                            ),
                          ),
                      ],
                    ),
                },
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _ProofRow extends StatelessWidget {
  const _ProofRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

Future<void> _openEditor(
  BuildContext context,
  MissionEngine engine,
  PlacesService places,
  MissionPoint? point,
) async {
  final result = await showDialog<_EditorResult>(
    context: context,
    builder: (context) => _DestinationEditor(
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

class _EditorResult {
  const _EditorResult(this.label, this.location, this.address, this.dwellTime);

  final String label;
  final GeoPoint location;
  final String? address;
  final Duration dwellTime;
}

class _DestinationEditor extends StatefulWidget {
  const _DestinationEditor({required this.point, required this.places, required this.near});

  final MissionPoint? point;
  final PlacesService places;
  final GeoPoint near;

  @override
  State<_DestinationEditor> createState() => _DestinationEditorState();
}

class _DestinationEditorState extends State<_DestinationEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _search = TextEditingController();
  late final TextEditingController _label =
      TextEditingController(text: widget.point?.label ?? 'New destination');
  late final TextEditingController _dwell = TextEditingController(
      text: '${(widget.point?.dwellTime ?? defaultDwellTime).inMinutes}');

  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  String? _searchError;
  String _query = '';
  String? _searchedQuery;

  /// Guards against a slow earlier request overwriting the newest results.
  int _searchGeneration = 0;
  late GeoPoint _location = widget.point?.location ?? widget.near;
  late String? _address = widget.point?.address;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _label.dispose();
    _dwell.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() => _query = query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_searchGeneration;
    if (query.trim().length < minSearchLength) {
      setState(() {
        _suggestions = const [];
        _searchedQuery = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await widget.places.search(query, near: widget.near);
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _suggestions = results;
          _searchedQuery = query;
        });
      }
    } catch (error) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searchError = _describe(error));
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  /// Google's errors are JSON blobs; the operator only needs the gist.
  String _describe(Object error) => switch (error) {
        PlacesException() => 'Place search is unavailable right now.',
        _ => '$error',
      };

  /// Why the suggestion list is empty, if it is.
  String? get _emptyStateMessage {
    if (_searching || _suggestions.isNotEmpty || _searchError != null) return null;
    final query = _query.trim();
    if (query.isEmpty) return null;
    if (query.length < minSearchLength) {
      return 'Keep typing — at least $minSearchLength characters.';
    }
    return _searchedQuery == null ? null : 'No places match "$_searchedQuery".';
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    try {
      final place = await widget.places.resolve(suggestion);
      if (place == null || !mounted) return;
      _searchGeneration++;
      setState(() {
        _query = place.name;
        _searchedQuery = null;
        _location = place.location;
        _address = place.address;
        _label.text = place.name;
        _suggestions = const [];
        _search.text = place.name;
      });
    } catch (error) {
      if (mounted) setState(() => _searchError = _describe(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.point == null ? 'Add destination' : 'Edit ${widget.point!.label}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Search a place or address',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
                onChanged: _onQueryChanged,
              ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_searchError!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              if (_emptyStateMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_emptyStateMessage!, style: theme.textTheme.bodySmall),
                ),
              if (_suggestions.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final suggestion in _suggestions)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(suggestion.title),
                          subtitle:
                              suggestion.subtitle.isEmpty ? null : Text(suggestion.subtitle),
                          onTap: () => _select(suggestion),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              Text(_address ?? 'Coordinates: $_location', style: theme.textTheme.bodySmall),
              TextFormField(
                controller: _dwell,
                decoration: const InputDecoration(labelText: 'On-site minutes'),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return 'Enter a whole number of minutes';
                  if (parsed < 0 || parsed > 600) return 'Must be between 0 and 600';
                  return null;
                },
              ),
            ],
          ),
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
                _location,
                _address,
                Duration(minutes: int.parse(_dwell.text)),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
