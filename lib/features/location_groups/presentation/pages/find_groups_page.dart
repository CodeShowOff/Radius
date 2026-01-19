import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../data/location_group_service.dart';
import '../../domain/entities/country.dart';
import '../../domain/entities/state_region.dart';
import '../bloc/location_group_bloc.dart';
import '../widgets/group_card.dart';
import '../widgets/location_selector.dart';

/// Page for browsing and discovering location-based groups.
class FindGroupsPage extends StatefulWidget {
  const FindGroupsPage({super.key});

  @override
  State<FindGroupsPage> createState() => _FindGroupsPageState();
}

class _FindGroupsPageState extends State<FindGroupsPage> {
  Country? _selectedCountry;
  StateRegion? _selectedState;
  bool _showLocationSelector = true;
  GroupSortOption _sortBy = GroupSortOption.mostActive;

  @override
  void initState() {
    super.initState();
    // Could load last selected location from preferences here
  }

  void _onLocationSelected(Country country, StateRegion state) {
    setState(() {
      _selectedCountry = country;
      _selectedState = state;
      _showLocationSelector = false;
    });

    // Load groups for this location
    context.read<LocationGroupBloc>().add(LoadGroupsForLocation(
          countryCode: country.code,
          stateCode: state.code,
          sortBy: _sortBy,
        ));
  }

  void _onSortChanged(GroupSortOption option) {
    setState(() => _sortBy = option);
    if (_selectedCountry != null && _selectedState != null) {
      context.read<LocationGroupBloc>().add(ChangeSortOption(sortBy: option));
    }
  }

  void _changeLocation() {
    setState(() {
      _showLocationSelector = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Groups'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.createLocationGroup),
            icon: const Icon(Icons.add),
            tooltip: 'Create Group',
          ),
        ],
      ),
      body: _showLocationSelector
          ? _buildLocationSelector(theme)
          : _buildGroupList(theme),
    );
  }

  Widget _buildLocationSelector(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            'Find Groups by Location',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a country and state to discover groups in that area.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 24),

          // Location selector
          LocationSelector(
            selectedCountryCode: _selectedCountry?.code,
            selectedStateCode: _selectedState?.code,
            onCountryChanged: (country) {
              setState(() {
                _selectedCountry = country;
                _selectedState = null;
              });
            },
            onStateChanged: (state) {
              setState(() {
                _selectedState = state;
              });
            },
            onLocationSelected: _onLocationSelected,
          ),

          const SizedBox(height: 24),

          // Search button
          FilledButton.icon(
            onPressed: _selectedCountry != null && _selectedState != null
                ? () => _onLocationSelected(_selectedCountry!, _selectedState!)
                : null,
            icon: const Icon(Icons.search),
            label: const Text('Find Groups'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 32),

          // Recently browsed (could add later)
          // _buildRecentLocations(theme),
        ],
      ),
    );
  }

  Widget _buildGroupList(ThemeData theme) {
    return Column(
      children: [
        // Location header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.location_on,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedState?.name ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _selectedCountry?.name ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _changeLocation,
                icon: const Icon(Icons.edit_location_outlined, size: 18),
                label: const Text('Change'),
              ),
            ],
          ),
        ),

        // Sort options
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'Sort by:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: 'Active',
                isSelected: _sortBy == GroupSortOption.mostActive,
                onTap: () => _onSortChanged(GroupSortOption.mostActive),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: 'Newest',
                isSelected: _sortBy == GroupSortOption.newest,
                onTap: () => _onSortChanged(GroupSortOption.newest),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: 'Members',
                isSelected: _sortBy == GroupSortOption.mostMembers,
                onTap: () => _onSortChanged(GroupSortOption.mostMembers),
              ),
            ],
          ),
        ),

        // Groups list
        Expanded(
          child: BlocBuilder<LocationGroupBloc, LocationGroupState>(
            builder: (context, state) {
              if (state.status == GroupBlocStatus.loading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state.locationGroups.isEmpty) {
                return _buildEmptyState(theme);
              }

              return RefreshIndicator(
                onRefresh: () async {
                  if (_selectedCountry != null && _selectedState != null) {
                    context.read<LocationGroupBloc>().add(LoadGroupsForLocation(
                          countryCode: _selectedCountry!.code,
                          stateCode: _selectedState!.code,
                          sortBy: _sortBy,
                        ));
                    // Wait a bit for the stream to update
                    await Future.delayed(const Duration(milliseconds: 500));
                  }
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.locationGroups.length,
                  itemBuilder: (context, index) {
                    final group = state.locationGroups[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GroupCard(
                        group: group,
                        onTap: () => context.push(
                          Routes.locationGroupDetailWith(group.id),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No groups found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to create a group in ${_selectedState?.name}!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push(Routes.createLocationGroup),
              icon: const Icon(Icons.add),
              label: const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
