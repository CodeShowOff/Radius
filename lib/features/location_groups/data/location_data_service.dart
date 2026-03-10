import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/entities/country.dart';

/// Location data service that loads country and city data from bundled JSON asset.
///
/// Data is loaded lazily on first access and cached in memory.
/// The JSON format expected: [{"name": "CountryName", "cities": ["City1", "City2", ...]}]
class LocationDataService {
  static LocationDataService? _instance;

  LocationDataService._();

  factory LocationDataService() {
    return _instance ??= LocationDataService._();
  }

  List<Country>? _countries;
  Map<String, List<String>>? _citiesByCountry;
  bool _loaded = false;

  /// Ensures data is loaded from the JSON asset.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final jsonString = await rootBundle.loadString('assets/locations.json');
    final List<dynamic> data = json.decode(jsonString) as List<dynamic>;

    final countries = <Country>[];
    final citiesMap = <String, List<String>>{};

    for (final entry in data) {
      final map = entry as Map<String, dynamic>;
      final name = map['name'] as String;
      final cities = (map['cities'] as List<dynamic>).cast<String>();
      countries.add(Country(name: name));
      citiesMap[name] = cities..sort();
    }

    countries.sort((a, b) => a.name.compareTo(b.name));
    _countries = countries;
    _citiesByCountry = citiesMap;
    _loaded = true;
  }

  /// Get all available countries, sorted by name.
  /// Must call [ensureLoaded] before using this.
  List<Country> getCountries() {
    return _countries ?? [];
  }

  /// Get a country by its name.
  Country? getCountryByName(String name) {
    try {
      return _countries?.firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Get all cities for a country, sorted alphabetically.
  List<String> getCitiesForCountry(String countryName) {
    return _citiesByCountry?[countryName] ?? [];
  }

  /// Search countries by name (case-insensitive partial match).
  List<Country> searchCountries(String query) {
    if (query.isEmpty) return getCountries();
    final lowerQuery = query.toLowerCase();
    return (_countries ?? [])
        .where((c) => c.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Search cities by name within a country.
  List<String> searchCities(String countryName, String query) {
    if (query.isEmpty) return getCitiesForCountry(countryName);
    final lowerQuery = query.toLowerCase();
    return getCitiesForCountry(countryName)
        .where((c) => c.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Finds the best matching country name from locations.json.
  ///
  /// Returns the canonical country name if found, or `null`.
  String? findMatchingCountry(String detectedCountry) {
    if (detectedCountry.isEmpty) return null;
    final lower = detectedCountry.toLowerCase();
    for (final c in _countries ?? <Country>[]) {
      if (c.name.toLowerCase() == lower) return c.name;
    }
    // Partial / contains match
    for (final c in _countries ?? <Country>[]) {
      if (c.name.toLowerCase().contains(lower) ||
          lower.contains(c.name.toLowerCase())) {
        return c.name;
      }
    }
    return null;
  }

  /// Finds the best matching city name from locations.json for a given country.
  ///
  /// Tries exact match first, then partial/contains match.
  /// Returns the canonical city name if found, or `null`.
  String? findMatchingCity(String countryName, String detectedCity) {
    if (detectedCity.isEmpty) return null;
    final cities = getCitiesForCountry(countryName);
    if (cities.isEmpty) return null;

    final lower = detectedCity.toLowerCase();

    // Exact match (case-insensitive)
    for (final city in cities) {
      if (city.toLowerCase() == lower) return city;
    }

    // Partial match — detected city contains a known city name or vice versa
    for (final city in cities) {
      if (city.toLowerCase().contains(lower) ||
          lower.contains(city.toLowerCase())) {
        return city;
      }
    }

    return null;
  }
}
