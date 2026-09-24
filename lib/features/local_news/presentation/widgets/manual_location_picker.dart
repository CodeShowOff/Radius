import 'package:flutter/material.dart';

import '../../../location_groups/data/location_data_service.dart';
import '../../../location_groups/domain/entities/country.dart';

/// Widget for manually picking a country and city for local news.
///
/// Reuses the [LocationDataService] from the location_groups feature
/// for country/city data. When both selections are made, it fires
/// [onLocationSelected] with the country name and city name.
class ManualLocationPicker extends StatefulWidget {
  /// Called when both country and city are selected.
  final void Function(String country, String city) onLocationSelected;

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
  List<String> _cities = [];

  Country? _selectedCountry;
  String? _selectedCity;

  String _countrySearch = '';
  String _citySearch = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _locationService.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _countries = _locationService.getCountries();
      _loading = false;
    });
  }

  void _onCountrySelected(Country country) {
    setState(() {
      _selectedCountry = country;
      _selectedCity = null;
      _citySearch = '';
      _cities = _locationService.getCitiesForCountry(country.name);
    });
  }

  void _onCitySelected(String city) {
    setState(() {
      _selectedCity = city;
    });

    if (_selectedCountry != null) {
      widget.onLocationSelected(_selectedCountry!.name, city);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredCountries = _countrySearch.isEmpty
        ? _countries
        : _locationService.searchCountries(_countrySearch);
    final filteredCities = _citySearch.isEmpty
        ? _cities
        : _locationService.searchCities(
            _selectedCountry?.name ?? '',
            _citySearch,
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

        // City field
        _PickerField(
          label: 'City',
          hint: _selectedCountry == null
              ? 'Select a country first'
              : 'Select a city',
          value: _selectedCity,
          enabled: _selectedCountry != null,
          onTap: () => _showSelectionSheet<String>(
            context: context,
            title: 'Select City',
            items: filteredCities,
            searchHint: 'Search cities...',
            searchQuery: _citySearch,
            onSearchChanged: (q) => setState(() => _citySearch = q),
            itemLabel: (s) => s,
            onSelected: _onCitySelected,
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
// Picker field â€” styled tappable field
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
// Selection bottom sheet â€” search + list
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
