import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/country.dart';
import '../../domain/entities/location_group.dart';
import '../bloc/location_group_bloc.dart';
import '../widgets/location_selector.dart';

/// Multi-step page for creating a new location group.
class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  int _currentStep = 0;
  Country? _selectedCountry;
  String? _selectedCity;
  GroupVisibility _visibility = GroupVisibility.public;
  DateTime? _lastCreateAttempt;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canProceedStep0 =>
      _nameController.text.trim().length >= 3 &&
      _nameController.text.trim().length <= 50;

  bool get _canProceedStep1 =>
      _selectedCountry != null && _selectedCity != null;

  bool get _canCreate => _canProceedStep0 && _canProceedStep1;

  void _onStepContinue() {
    if (_currentStep == 0 && _canProceedStep0) {
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1 && _canProceedStep1) {
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      _createGroup();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _createGroup() {
    if (!_canCreate) return;

    // Rate limiting: prevent rapid group creation (minimum 2 seconds between attempts)
    if (_lastCreateAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastCreateAttempt!);
      if (timeSinceLastAttempt.inSeconds < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait a moment before creating another group'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to create a group')),
      );
      return;
    }

    _lastCreateAttempt = DateTime.now();

    context.read<LocationGroupBloc>().add(CreateGroup(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          countryName: _selectedCountry!.name,
          cityName: _selectedCity!,
          creatorUserId: authState.user.id,
          creatorUserName: authState.user.displayName,
          creatorUserPhotoUrl: authState.user.avatarUrl,
          visibility: _visibility,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<LocationGroupBloc, LocationGroupState>(
      listener: (context, state) {
        if (state.createdGroup != null) {
          // Navigate to the created group
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Group "${state.createdGroup!.name}" created!'),
              backgroundColor: theme.colorScheme.primary,
            ),
          );
          
          // Navigate to group detail or back
          context.pushReplacement(
            Routes.locationGroupDetailWith(state.createdGroup!.id),
          );
        } else if (state.hasError && state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: theme.colorScheme.error,
            ),
          );
          context.read<LocationGroupBloc>().add(const ClearGroupError());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Create Group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: BlocBuilder<LocationGroupBloc, LocationGroupState>(
          builder: (context, state) {
            return Form(
              key: _formKey,
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: state.isLoading ? null : _onStepContinue,
                onStepCancel: state.isLoading ? null : _onStepCancel,
                onStepTapped: state.isLoading ? null : (index) {
                  // Allow going back to previous steps
                  if (index < _currentStep) {
                    setState(() => _currentStep = index);
                  }
                },
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        FilledButton(
                          onPressed: state.isLoading
                              ? null
                              : _currentStep == 0
                                  ? (_canProceedStep0 ? details.onStepContinue : null)
                                  : _currentStep == 1
                                      ? (_canProceedStep1 ? details.onStepContinue : null)
                                      : (_canCreate ? details.onStepContinue : null),
                          child: state.status == GroupBlocStatus.creating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_currentStep == 2 ? 'Create Group' : 'Continue'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: state.isLoading ? null : details.onStepCancel,
                          child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
                        ),
                      ],
                    ),
                  );
                },
                steps: [
                  // Step 1: Group Details
                  Step(
                    title: const Text('Group Details'),
                    subtitle: const Text('Name and description'),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0
                        ? StepState.complete
                        : StepState.indexed,
                    content: _buildDetailsStep(theme),
                  ),

                  // Step 2: Location
                  Step(
                    title: const Text('Location'),
                    subtitle: const Text('Where is this group based?'),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1
                        ? StepState.complete
                        : _currentStep == 1
                            ? StepState.indexed
                            : StepState.disabled,
                    content: _buildLocationStep(theme),
                  ),

                  // Step 3: Settings
                  Step(
                    title: const Text('Settings'),
                    subtitle: const Text('Visibility and access'),
                    isActive: _currentStep >= 2,
                    state: _currentStep == 2
                        ? StepState.indexed
                        : StepState.disabled,
                    content: _buildSettingsStep(theme),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetailsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Card(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Groups are discoverable by location. Choose your name carefully.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Name field
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Group Name *',
            hintText: 'e.g., Startup Founders, Book Club',
            helperText: '3-50 characters',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            counterText: '${_nameController.text.length}/50',
          ),
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a group name';
            }
            if (value.trim().length < 3) {
              return 'Name must be at least 3 characters';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Description field
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'What is this group about?',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  Widget _buildLocationStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Card(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your group will be discoverable to users browsing this location.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        LocationSelector(
          selectedCountryName: _selectedCountry?.name,
          selectedCityName: _selectedCity,
          onCountryChanged: (country) {
            setState(() {
              _selectedCountry = country;
              _selectedCity = null;
            });
          },
          onCityChanged: (city) {
            setState(() {
              _selectedCity = city;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSettingsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Who can join?',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),

        // Public option
        _VisibilityOption(
          title: 'Open',
          description: 'Anyone can join instantly',
          icon: Icons.public,
          isSelected: _visibility == GroupVisibility.public,
          onTap: () => setState(() => _visibility = GroupVisibility.public),
        ),

        const SizedBox(height: 8),

        // Request-to-join option
        _VisibilityOption(
          title: 'Approval Required',
          description: 'Admins approve join requests',
          icon: Icons.lock_outline,
          isSelected: _visibility == GroupVisibility.requestToJoin,
          onTap: () => setState(() => _visibility = GroupVisibility.requestToJoin),
        ),

        const SizedBox(height: 24),

        // Summary
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  label: 'Name',
                  value: _nameController.text.trim(),
                ),
                if (_descriptionController.text.trim().isNotEmpty)
                  _SummaryRow(
                    label: 'Description',
                    value: _descriptionController.text.trim(),
                  ),
                _SummaryRow(
                  label: 'Location',
                  value: _selectedCountry != null && _selectedCity != null
                      ? '$_selectedCity, ${_selectedCountry!.name}'
                      : 'Not selected',
                ),
                _SummaryRow(
                  label: 'Visibility',
                  value: _visibility == GroupVisibility.public
                      ? 'Open to all'
                      : 'Approval required',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _VisibilityOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
