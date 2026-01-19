import 'package:equatable/equatable.dart';

/// Entity representing a country for location-scoped groups.
/// Uses ISO-3166-1 alpha-2 codes for standardization.
class Country extends Equatable {
  /// ISO-3166-1 alpha-2 code (e.g., "US", "IN", "GB")
  final String code;

  /// Display name of the country
  final String name;

  /// Whether this country has states/regions
  final bool hasStates;

  const Country({
    required this.code,
    required this.name,
    this.hasStates = true,
  });

  @override
  List<Object?> get props => [code, name, hasStates];

  @override
  String toString() => 'Country(code: $code, name: $name)';
}
