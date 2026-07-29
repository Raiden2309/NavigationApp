import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/mission.dart';
import '../services/kod_lokasi_service.dart';
import '../services/places_service.dart';

class EditorResult {
  const EditorResult(this.label, this.location, this.address, this.dwellTime, this.kodLokasi);

  final String label;
  final GeoPoint location;
  final String? address;
  final Duration dwellTime;
  final String? kodLokasi;
}

class DestinationEditor extends StatefulWidget {
  const DestinationEditor({
    super.key,
    required this.point,
    required this.places,
    required this.near,
    this.kodLokasi,
  });

  final MissionPoint? point;
  final PlacesService places;
  final GeoPoint near;
  final KodLokasiService? kodLokasi;

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
  late final TextEditingController _kodLokasiCtrl =
      TextEditingController(text: widget.point?.kodLokasi ?? '');

  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  String? _searchError;
  String _query = '';
  String? _searchedQuery;

  Timer? _kodLokasiDebounce;
  bool _resolvingKodLokasi = false;
  String? _kodLokasiError;
  int _kodLokasiGeneration = 0;
  bool _autoPopulatingKodLokasi = false;

  int _searchGeneration = 0;
  late GeoPoint _location = widget.point?.location ?? widget.near;
  late String? _address = widget.point?.address;
  late String? _resolvedKodLokasi = widget.point?.kodLokasi;

  @override
  void dispose() {
    _debounce?.cancel();
    _kodLokasiDebounce?.cancel();
    _search.dispose();
    _label.dispose();
    _dwell.dispose();
    _kodLokasiCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() => _query = query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final gen = ++_searchGeneration;
    if (query.trim().length < minSearchLength) {
      _setStateSearch(gen, () {
        _suggestions = const [];
        _searchedQuery = null;
        _searching = false;
      });
      return;
    }
    _setStateSearch(gen, () {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await widget.places.search(query, near: widget.near);
      _setStateSearch(gen, () {
        _suggestions = results;
        _searchedQuery = query;
      });
    } catch (error) {
      _setStateSearch(gen, () => _searchError = _describe(error));
    } finally {
      _setStateSearch(gen, () => _searching = false);
    }
  }

  void _setStateSearch(int gen, VoidCallback fn) {
    if (mounted && gen == _searchGeneration) setState(fn);
  }

  void _setStateKodLokasi(int gen, VoidCallback fn) {
    if (mounted && gen == _kodLokasiGeneration) setState(fn);
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

      final kodLokasi = widget.kodLokasi;
      if (kodLokasi != null) {
        try {
          final result = await kodLokasi.search(place.location);
          if (mounted && result != null) {
            _kodLokasiDebounce?.cancel();
            _autoPopulatingKodLokasi = true;
            _kodLokasiCtrl.text = result.kodLokasi;
            setState(() {
              _resolvedKodLokasi = result.kodLokasi;
            });
          }
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) setState(() => _searchError = _describe(error));
    }
  }

  void _onKodLokasiChanged(String value) {
    if (_autoPopulatingKodLokasi) {
      _autoPopulatingKodLokasi = false;
      return;
    }
    _kodLokasiDebounce?.cancel();
    _kodLokasiDebounce = Timer(const Duration(milliseconds: 600), () => _resolveKodLokasi());
  }

  Future<void> _resolveKodLokasi() async {
    final code = _kodLokasiCtrl.text.trim();
    if (code.isEmpty) return;
    final service = widget.kodLokasi;
    if (service == null) return;

    final gen = ++_kodLokasiGeneration;
    _setStateKodLokasi(gen, () {
      _resolvingKodLokasi = true;
      _kodLokasiError = null;
    });

    try {
      final result = await service.reverse(code);
      if (!mounted || gen != _kodLokasiGeneration) return;
      if (result == null) {
        _setStateKodLokasi(gen, () => _kodLokasiError = 'Code not found');
        return;
      }

      final loc = result.location;
      final districtAddress = result.alamat;
      _setStateKodLokasi(gen, () {
        _resolvedKodLokasi = result.kodLokasi;
        _location = loc ?? _location;
        _address = districtAddress ?? _address;
        _search.text = districtAddress ?? _address ?? '';
        _query = districtAddress ?? '';
        _searchedQuery = null;
        _suggestions = const [];
        if (districtAddress != null && _label.text == code) {
          _label.text = districtAddress;
        }
        _kodLokasiError = null;
        _resolvingKodLokasi = false;
      });

      if (loc != null) {
        await _reverseGeocode(loc, districtAddress, gen);
      }
    } catch (_) {
      _setStateKodLokasi(gen, () {
        _kodLokasiError = 'Lookup failed';
        _resolvingKodLokasi = false;
      });
    }
  }

  Future<void> _reverseGeocode(
      GeoPoint loc, String? districtAddress, int gen) async {
    try {
      final place = await widget.places.reverseGeocode(loc);
      if (place == null) return;
      _setStateKodLokasi(gen, () {
        _address = place.address;
        _search.text = place.name;
        _query = place.name;
        if (_label.text == districtAddress) {
          _label.text = place.name;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasKodLokasi = widget.kodLokasi != null;
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
              if (hasKodLokasi) ...[
                TextField(
                  controller: _kodLokasiCtrl,
                  decoration: InputDecoration(
                    labelText: 'KodLokasi Code',
                    hintText: 'e.g. SBKK.1.1',
                    prefixIcon: const Icon(Icons.grid_on),
                    suffixIcon: _resolvingKodLokasi
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  onChanged: _onKodLokasiChanged,
                ),
                if (_kodLokasiError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_kodLokasiError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
              ],
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
                _resolvedKodLokasi,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
