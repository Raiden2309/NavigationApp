import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import '../services/places_service.dart';

class EditorResult {
  const EditorResult(this.label, this.location, this.address, this.dwellTime);

  final String label;
  final GeoPoint location;
  final String? address;
  final Duration dwellTime;
}

class DestinationEditor extends StatefulWidget {
  const DestinationEditor({super.key, required this.point, required this.places, required this.near});

  final MissionPoint? point;
  final PlacesService places;
  final GeoPoint near;

  @override
  State<DestinationEditor> createState() => DestinationEditorState();
}

class DestinationEditorState extends State<DestinationEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _search = TextEditingController();
  late final TextEditingController _label =
      TextEditingController(text: widget.point?.label ?? 'New destination');
  late final TextEditingController _dwell = TextEditingController(
      text: '${(widget.point?.dwellTime ?? const Duration(minutes: 15)).inMinutes}');

  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  String? _searchError;
  String _query = '';
  String? _searchedQuery;

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

  String _describe(Object error) => switch (error) {
        PlacesException() => 'Place search is unavailable right now.',
        _ => '$error',
      };

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
              const SizedBox(height: 8),
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
              EditorResult(
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
