import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import '../services/mission_engine.dart';
import '../services/places_service.dart';
import 'formatting.dart';

/// Mission operator tools: add, move, retime or drop any destination after
/// Point A. Every edit re-optimizes the remaining route immediately.
class MissionControlPanel extends StatelessWidget {
  const MissionControlPanel({super.key, required this.engine, required this.places});

  final MissionEngine engine;
  final PlacesService places;

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
            child: Text('Search for a place or tap the map to drop a destination. '
                'Point A is fixed; the visiting order for the rest is optimized automatically.'),
          ),
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openEditor(context, engine, places, null),
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Add destination'),
        ),
      ],
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
    final sequence = engine.routeOrder.indexOf(point);
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
