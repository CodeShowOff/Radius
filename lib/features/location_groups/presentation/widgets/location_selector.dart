import 'package:flutter/material.dart';

import '../../data/location_data_service.dart';
import '../../domain/entities/country.dart';

/// Widget for selecting a Country and City combination.
///
/// Loads location data asynchronously from the bundled JSON asset.
/// City selection is disabled until a country is selected.
class LocationSelector extends StatefulWidget {
  /// Currently selected country name
  final String? selectedCountryName;

  /// Currently selected city name
  final String? selectedCityName;

  /// Called when country changes
  final ValueChanged<Country?>? onCountryChanged;

  /// Called when city changes
  final ValueChanged<String?>? onCityChanged;

  /// Called when both country and city are selected (for convenience)
  final void Function(Country country, String city)? onLocationSelected;

  /// Whether to show search in dropdowns
  final bool searchable;

  /// Label for country field
  final String countryLabel;

  /// Label for city field
  final String cityLabel;

  /// Hint text for country field
  final String countryHint;

  /// Hint text for city field
  final String cityHint;

  const LocationSelector({
    super.key,
    this.selectedCountryName,
    this.selectedCityName,
    this.onCountryChanged,
    this.onCityChanged,
    this.onLocationSelected,
    this.searchable = true,
    this.countryLabel = 'Country',
    this.cityLabel = 'City',
    this.countryHint = 'Select a country',
    this.cityHint = 'Select a city',
  });

  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  final _locationService = LocationDataService();

  Country? _selectedCountry;
  String? _selectedCity;
  List<Country> _countries = [];
  List<String> _cities = [];
  bool _loading = true;

  String _countrySearchQuery = '';
  String _citySearchQuery = '';

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

      // Initialize from passed values
      if (widget.selectedCountryName != null) {
        _selectedCountry = _locationService.getCountryByName(widget.selectedCountryName!);
        if (_selectedCountry != null) {
          _cities = _locationService.getCitiesForCountry(_selectedCountry!.name);
          if (widget.selectedCityName != null) {
            _selectedCity = _cities.contains(widget.selectedCityName!)
                ? widget.selectedCityName
                : null;
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(LocationSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedCountryName != oldWidget.selectedCountryName) {
      setState(() {
        if (widget.selectedCountryName != null) {
          _selectedCountry = _locationService.getCountryByName(widget.selectedCountryName!);
          if (_selectedCountry != null) {
            _cities = _locationService.getCitiesForCountry(_selectedCountry!.name);
          }
        } else {
          _selectedCountry = null;
          _cities = [];
        }
      });
    }

    if (widget.selectedCityName != oldWidget.selectedCityName) {
      setState(() {
        _selectedCity = widget.selectedCityName;
      });
    }
  }

  void _onCountrySelected(Country? country) {
    setState(() {
      _selectedCountry = country;
      _selectedCity = null;
      _citySearchQuery = '';

      if (country != null) {
        _cities = _locationService.getCitiesForCountry(country.name);
      } else {
        _cities = [];
      }
    });

    widget.onCountryChanged?.call(country);
    widget.onCityChanged?.call(null);
  }

  void _onCitySelected(String? city) {
    setState(() {
      _selectedCity = city;
    });

    widget.onCityChanged?.call(city);

    if (_selectedCountry != null && city != null) {
      widget.onLocationSelected?.call(_selectedCountry!, city);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredCountries = _countrySearchQuery.isEmpty
        ? _countries
        : _locationService.searchCountries(_countrySearchQuery);

    final filteredCities = _citySearchQuery.isEmpty
        ? _cities
        : _locationService.searchCities(
            _selectedCountry?.name ?? '',
            _citySearchQuery,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Country selector
        _SelectionField<Country>(
          label: widget.countryLabel,
          hint: widget.countryHint,
          value: _selectedCountry,
          items: filteredCountries,
          searchable: widget.searchable,
          searchHint: 'Search countries...',
          searchQuery: _countrySearchQuery,
          onSearchChanged: (query) {
            setState(() {
              _countrySearchQuery = query;
            });
          },
          itemBuilder: (country) => Text(country.name),
          selectedBuilder: (country) => Text(country.name),
          itemSearchText: (country) => country.name,
          onSelected: _onCountrySelected,
        ),

        const SizedBox(height: 16),

        // City selector
        _SelectionField<String>(
          label: widget.cityLabel,
          hint: widget.cityHint,
          value: _selectedCity,
          items: filteredCities,
          enabled: _selectedCountry != null,
          searchable: widget.searchable && _cities.length > 10,
          searchHint: 'Search cities...',
          searchQuery: _citySearchQuery,
          onSearchChanged: (query) {
            setState(() {
              _citySearchQuery = query;
            });
          },
          itemBuilder: (city) => Text(city),
          selectedBuilder: (city) => Text(city),
          itemSearchText: (city) => city,
          onSelected: _onCitySelected,
          emptyMessage: _selectedCountry == null
              ? 'Please select a country first'
              : _cities.isEmpty
                  ? 'No cities available'
                  : null,
        ),
      ],
    );
  }
}

/// Generic selection field with dropdown and search support.
class _SelectionField<T> extends StatelessWidget {
  final String label;
  final String hint;
  final T? value;
  final List<T> items;
  final bool enabled;
  final bool searchable;
  final String searchHint;
  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final Widget Function(T) itemBuilder;
  final Widget Function(T) selectedBuilder;
  final String Function(T) itemSearchText;
  final ValueChanged<T?> onSelected;
  final String? emptyMessage;

  const _SelectionField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    this.enabled = true,
    this.searchable = false,
    this.searchHint = 'Search...',
    this.searchQuery = '',
    this.onSearchChanged,
    required this.itemBuilder,
    required this.selectedBuilder,
    required this.itemSearchText,
    required this.onSelected,
    this.emptyMessage,
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
          onTap: enabled
              ? () => _showSelectionSheet(context)
              : null,
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
              color: enabled
                  ? null
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                Expanded(
                  child: value != null
                      ? selectedBuilder(value as T)
                      : Text(
                          emptyMessage ?? hint,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SelectionSheet<T>(
        title: label,
        items: items,
        selectedValue: value,
        searchable: searchable,
        searchHint: searchHint,
        itemBuilder: itemBuilder,
        itemSearchText: itemSearchText,
        onSelected: (item) {
          Navigator.pop(context);
          onSelected(item);
        },
      ),
    );
  }
}

/// Bottom sheet for selecting items with optional search.
class _SelectionSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final T? selectedValue;
  final bool searchable;
  final String searchHint;
  final Widget Function(T) itemBuilder;
  final String Function(T) itemSearchText; // Function to extract searchable text
  final ValueChanged<T?> onSelected;

  const _SelectionSheet({
    required this.title,
    required this.items,
    this.selectedValue,
    this.searchable = false,
    this.searchHint = 'Search...',
    required this.itemBuilder,
    required this.itemSearchText,
    required this.onSelected,
  });

  @override
  State<_SelectionSheet<T>> createState() => _SelectionSheetState<T>();
}

class _SelectionSheetState<T> extends State<_SelectionSheet<T>> {
  final _searchController = TextEditingController();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredItems = widget.items.where((item) {
          final text = widget.itemSearchText(item).toLowerCase();
          return text.contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Search field
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
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
                  onChanged: _onSearchChanged,
                ),
              ),

            if (widget.searchable) const SizedBox(height: 8),

            // Items list
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        'No items found',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final isSelected = item == widget.selectedValue;

                        return ListTile(
                          title: widget.itemBuilder(item),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          selected: isSelected,
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
