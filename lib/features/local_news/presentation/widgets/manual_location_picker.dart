import 'package:flutter/material.dart';

import '../../../location_groups/data/location_data_service.dart';
import '../../../location_groups/domain/entities/country.dart';
import '../../../location_groups/domain/entities/state_region.dart';

/// Widget for manually picking a country and state/region for local news.
///
/// Reuses the [LocationDataService] from the location_groups feature
/// for country/state data. When both selections are made, it fires
/// [onLocationSelected] with the country name and state name.
class ManualLocationPicker extends StatefulWidget {
  /// Called when both country and state are selected.
  final void Function(String country, String state) onLocationSelected;

  const ManualLocationPicker({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<ManualLocationPicker> createState() => _ManualLocationPickerState();
}

class _ManualLocationPickerState extends State<ManualLocationPicker> {
  final _locationService = LocationDataService();

  List<Country> _countries = [];
  List<StateRegion> _states = [];

  Country? _selectedCountry;
  StateRegion? _selectedState;

  String _countrySearch = '';
  String _stateSearch = '';

  @override
  void initState() {
    super.initState();
    _countries = _locationService.getCountries();
  }

  void _onCountrySelected(Country country) {
    setState(() {
      _selectedCountry = country;
      _selectedState = null;
      _stateSearch = '';
      _states = _locationService.getStatesForCountry(country.code);

      // Countries without states — auto-select first entry
      if (!country.hasStates && _states.isNotEmpty) {
        _selectedState = _states.first;
        widget.onLocationSelected(country.name, _states.first.name);
      }
    });
  }

  void _onStateSelected(StateRegion state) {
    setState(() {
      _selectedState = state;
    });

    if (_selectedCountry != null) {
      widget.onLocationSelected(_selectedCountry!.name, state.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredCountries = _countrySearch.isEmpty
        ? _countries
        : _locationService.searchCountries(_countrySearch);
    final filteredStates = _stateSearch.isEmpty
        ? _states
        : _locationService.searchStates(
            _selectedCountry?.code ?? '',
            _stateSearch,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Country field
        _PickerField(
          label: 'Country',
          hint: 'Select a country',
          value: _selectedCountry?.name,
          onTap: () => _showSelectionSheet<Country>(
            context: context,
            title: 'Select Country',
            items: filteredCountries,
            searchHint: 'Search countries...',
            searchQuery: _countrySearch,
            onSearchChanged: (q) => setState(() => _countrySearch = q),
            itemLabel: (c) => c.name,
            onSelected: _onCountrySelected,
          ),
        ),
        const SizedBox(height: 16),

        // State field
        _PickerField(
          label: 'State / Region',
          hint: _selectedCountry == null
              ? 'Select a country first'
              : 'Select a state',
          value: _selectedState?.name,
          enabled: _selectedCountry != null && _selectedCountry!.hasStates,
          onTap: () => _showSelectionSheet<StateRegion>(
            context: context,
            title: 'Select State / Region',
            items: filteredStates,
            searchHint: 'Search states...',
            searchQuery: _stateSearch,
            onSearchChanged: (q) => setState(() => _stateSearch = q),
            itemLabel: (s) => s.name,
            onSelected: _onStateSelected,
          ),
        ),

        // Info text for countries listed nationally
        if (_selectedCountry != null && !_selectedCountry!.hasStates)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'News in ${_selectedCountry!.name} is listed nationally.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  /// Shows a bottom-sheet list for selecting an item.
  void _showSelectionSheet<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String searchHint,
    required String searchQuery,
    required ValueChanged<String> onSearchChanged,
    required String Function(T) itemLabel,
    required ValueChanged<T> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _SelectionSheet<T>(
          title: title,
          items: items,
          searchHint: searchHint,
          itemLabel: itemLabel,
          onSelected: (item) {
            Navigator.of(sheetContext).pop();
            onSelected(item);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Picker field — styled tappable field
// ---------------------------------------------------------------------------
class _PickerField extends StatelessWidget {
  final String label;
  final String hint;
  final String? value;
  final bool enabled;
  final VoidCallback? onTap;

  const _PickerField({
    required this.label,
    required this.hint,
    this.value,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: enabled
                    ? theme.colorScheme.outline
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: value != null
                        ? theme.textTheme.bodyLarge
                        : theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Selection bottom sheet — search + list
// ---------------------------------------------------------------------------
class _SelectionSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String searchHint;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.searchHint,
    required this.itemLabel,
    required this.onSelected,
  });

  @override
  State<_SelectionSheet<T>> createState() => _SelectionSheetState<T>();
}

class _SelectionSheetState<T> extends State<_SelectionSheet<T>> {
  String _query = '';

  List<T> get _filtered {
    if (_query.isEmpty) return widget.items;
    final lower = _query.toLowerCase();
    return widget.items
        .where((item) => widget.itemLabel(item).toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),

            const SizedBox(height: 8),

            // List
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No results found',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          title: Text(widget.itemLabel(item)),
                          onTap: () => widget.onSelected(item),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
