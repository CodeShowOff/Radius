import 'package:equatable/equatable.dart';

/// Entity representing a country for location-scoped groups.
/// Data sourced from bundled locations.json asset.
class Country extends Equatable {
  /// Display name of the country (also used as the unique identifier)
  final String name;

  const Country({
    required this.name,
  });

  @override
  List<Object?> get props => [name];

  @override
  String toString() => 'Country(name: $name)';
}
