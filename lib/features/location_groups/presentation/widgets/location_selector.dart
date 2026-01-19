import 'package:flutter/material.dart';

import '../../data/location_data_service.dart';
import '../../domain/entities/country.dart';
import '../../domain/entities/state_region.dart';

/// Widget for selecting a Country and State combination.
///
/// Ensures state selection is disabled until country is selected,
/// and automatically handles countries without states.
class LocationSelector extends StatefulWidget {
  /// Currently selected country code
  final String? selectedCountryCode;

  /// Currently selected state code
  final String? selectedStateCode;

  /// Called when country changes
  final ValueChanged<Country?>? onCountryChanged;

  /// Called when state changes
  final ValueChanged<StateRegion?>? onStateChanged;

  /// Called when both country and state are selected (for convenience)
  final void Function(Country country, StateRegion state)? onLocationSelected;

  /// Whether to show search in dropdowns
  final bool searchable;

  /// Label for country field
  final String countryLabel;

  /// Label for state field
  final String stateLabel;

  /// Hint text for country field
  final String countryHint;

  /// Hint text for state field
  final String stateHint;

  const LocationSelector({
    super.key,
    this.selectedCountryCode,
    this.selectedStateCode,
    this.onCountryChanged,
    this.onStateChanged,
    this.onLocationSelected,
    this.searchable = true,
    this.countryLabel = 'Country',
    this.stateLabel = 'State / Region',
    this.countryHint = 'Select a country',
    this.stateHint = 'Select a state',
  });

  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  final _locationService = LocationDataService();

  Country? _selectedCountry;
  StateRegion? _selectedState;
  List<Country> _countries = [];
  List<StateRegion> _states = [];

  String _countrySearchQuery = '';
  String _stateSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _countries = _locationService.getCountries();

    // Initialize from passed values
    if (widget.selectedCountryCode != null) {
      _selectedCountry = _locationService.getCountryByCode(widget.selectedCountryCode!);
      if (_selectedCountry != null) {
        _states = _locationService.getStatesForCountry(_selectedCountry!.code);

        if (widget.selectedStateCode != null) {
          _selectedState = _locationService.getStateByCode(widget.selectedStateCode!);
        }
      }
    }
  }

  @override
  void didUpdateWidget(LocationSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update if external values change
    if (widget.selectedCountryCode != oldWidget.selectedCountryCode) {
      setState(() {
        if (widget.selectedCountryCode != null) {
          _selectedCountry = _locationService.getCountryByCode(widget.selectedCountryCode!);
          if (_selectedCountry != null) {
            _states = _locationService.getStatesForCountry(_selectedCountry!.code);
          }
        } else {
          _selectedCountry = null;
          _states = [];
        }
      });
    }

    if (widget.selectedStateCode != oldWidget.selectedStateCode) {
      setState(() {
        if (widget.selectedStateCode != null) {
          _selectedState = _locationService.getStateByCode(widget.selectedStateCode!);
        } else {
          _selectedState = null;
        }
      });
    }
  }

  void _onCountrySelected(Country? country) {
    setState(() {
      _selectedCountry = country;
      _selectedState = null;
      _stateSearchQuery = '';

      if (country != null) {
        _states = _locationService.getStatesForCountry(country.code);

        // For countries without states, auto-select "National"
        if (!country.hasStates && _states.isNotEmpty) {
          _selectedState = _states.first;
          widget.onStateChanged?.call(_selectedState);
          
          if (_selectedState != null) {
            widget.onLocationSelected?.call(country, _selectedState!);
          }
        }
      } else {
        _states = [];
      }
    });

    widget.onCountryChanged?.call(country);
  }

  void _onStateSelected(StateRegion? state) {
    setState(() {
      _selectedState = state;
    });

    widget.onStateChanged?.call(state);

    if (_selectedCountry != null && state != null) {
      widget.onLocationSelected?.call(_selectedCountry!, state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredCountries = _countrySearchQuery.isEmpty
        ? _countries
        : _locationService.searchCountries(_countrySearchQuery);

    final filteredStates = _stateSearchQuery.isEmpty
        ? _states
        : _locationService.searchStates(
            _selectedCountry?.code ?? '',
            _stateSearchQuery,
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

        // State selector
        _SelectionField<StateRegion>(
          label: widget.stateLabel,
          hint: widget.stateHint,
          value: _selectedState,
          items: filteredStates,
          enabled: _selectedCountry != null && _selectedCountry!.hasStates,
          searchable: widget.searchable && _states.length > 10,
          searchHint: 'Search states...',
          searchQuery: _stateSearchQuery,
          onSearchChanged: (query) {
            setState(() {
              _stateSearchQuery = query;
            });
          },
          itemBuilder: (state) => Text(state.name),
          selectedBuilder: (state) => Text(state.name),
          itemSearchText: (state) => state.name,
          onSelected: _onStateSelected,
          emptyMessage: _selectedCountry == null
              ? 'Please select a country first'
              : _states.isEmpty
                  ? 'No regions available'
                  : null,
        ),

        // Info text for countries without states
        if (_selectedCountry != null && !_selectedCountry!.hasStates)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Groups in ${_selectedCountry!.name} are listed nationally.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
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
