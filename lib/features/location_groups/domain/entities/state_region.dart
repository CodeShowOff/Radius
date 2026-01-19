import 'package:equatable/equatable.dart';

/// Entity representing a state/region within a country.
/// Uses ISO-3166-2 subdivision codes where applicable.
class StateRegion extends Equatable {
  /// Unique identifier (ISO-3166-2 code or custom, e.g., "US-CA", "IN-MH")
  final String code;

  /// Display name of the state/region
  final String name;

  /// Parent country code (ISO-3166-1 alpha-2)
  final String countryCode;

  const StateRegion({
    required this.code,
    required this.name,
    required this.countryCode,
  });

  /// Special state for countries without subdivisions
  static StateRegion national(String countryCode) => StateRegion(
        code: '$countryCode-NATIONAL',
        name: 'National',
        countryCode: countryCode,
      );

  /// Check if this is a "national" catch-all state
  bool get isNational => code.endsWith('-NATIONAL');

  @override
  List<Object?> get props => [code, name, countryCode];

  @override
  String toString() => 'StateRegion(code: $code, name: $name)';
}
