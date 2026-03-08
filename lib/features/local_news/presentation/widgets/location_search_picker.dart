import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/geocoding_service.dart';
import '../../domain/entities/news_location.dart';

/// A search-based location picker that uses forward + reverse geocoding
/// to provide location suggestions as the user types.
///
/// Uses platform-native geocoding (no API key required).
/// The user must select one of the suggestions instead of free typing.
class LocationSearchPicker extends StatefulWidget {
  /// The geocoding service used for location search.
  final GeocodingService geocodingService;

  /// Called when the user selects a location from the suggestions.
  final void Function(NewsLocation location) onLocationSelected;

  const LocationSearchPicker({
    super.key,
    required this.geocodingService,
    required this.onLocationSelected,
  });

  @override
  State<LocationSearchPicker> createState() => _LocationSearchPickerState();
}

class _LocationSearchPickerState extends State<LocationSearchPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<NewsLocation> _suggestions = [];
  bool _isSearching = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().length < 2) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 600), () {
      _search(query.trim());
    });
  }

  Future<void> _search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;

    final results = await widget.geocodingService.searchLocations(query);

    if (mounted && _lastQuery == query) {
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search field
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Search for a city or area...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _suggestions = [];
                            _lastQuery = '';
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          autofocus: true,
        ),

        const SizedBox(height: 8),

        // Hint text
        if (_suggestions.isEmpty && !_isSearching && _lastQuery.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Text(
              'Type a city name like "Agra", "Mumbai", "Delhi"',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        // Suggestions list
        if (_suggestions.isNotEmpty)
          ..._suggestions.map(
            (location) => _SuggestionTile(
              location: location,
              onTap: () => widget.onLocationSelected(location),
            ),
          ),

        // No results message
        if (!_isSearching &&
            _suggestions.isEmpty &&
            _controller.text.length >= 2 &&
            _lastQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.location_off_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'No locations found',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Try a different city or area name.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Suggestion tile
// ---------------------------------------------------------------------------
class _SuggestionTile extends StatelessWidget {
  final NewsLocation location;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.location,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: Icon(
          Icons.location_on_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          location.shortDisplayString,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          _buildSubtitle(location),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  String _buildSubtitle(NewsLocation location) {
    final parts = <String>[];
    if (location.locality.isNotEmpty && location.locality != location.district) {
      parts.add(location.locality);
    }
    parts.add(location.country);
    return parts.join(', ');
  }
}
