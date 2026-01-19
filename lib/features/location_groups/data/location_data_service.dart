import '../domain/entities/country.dart';
import '../domain/entities/state_region.dart';

/// Static location data service providing ISO-3166 compliant country and state data.
/// 
/// This class provides a curated list of countries and their subdivisions
/// for the location-scoped group feature. Uses ISO-3166-1 for countries
/// and ISO-3166-2 for subdivisions where applicable.
class LocationDataService {
  static LocationDataService? _instance;
  
  LocationDataService._();
  
  factory LocationDataService() {
    return _instance ??= LocationDataService._();
  }

  /// Get all available countries, sorted by name.
  List<Country> getCountries() {
    final countries = _countries.toList();
    countries.sort((a, b) => a.name.compareTo(b.name));
    return countries;
  }

  /// Get a country by its ISO code.
  Country? getCountryByCode(String code) {
    try {
      return _countries.firstWhere((c) => c.code == code);
    } catch (_) {
      return null;
    }
  }

  /// Get all states/regions for a country, sorted by name.
  List<StateRegion> getStatesForCountry(String countryCode) {
    final states = _states.where((s) => s.countryCode == countryCode).toList();
    states.sort((a, b) {
      // Put "National" at the top
      if (a.isNational) return -1;
      if (b.isNational) return 1;
      return a.name.compareTo(b.name);
    });
    return states;
  }

  /// Get a state by its code.
  StateRegion? getStateByCode(String code) {
    try {
      return _states.firstWhere((s) => s.code == code);
    } catch (_) {
      return null;
    }
  }

  /// Search countries by name (case-insensitive partial match).
  List<Country> searchCountries(String query) {
    if (query.isEmpty) return getCountries();
    final lowerQuery = query.toLowerCase();
    return _countries
        .where((c) => c.name.toLowerCase().contains(lowerQuery))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Search states by name within a country.
  List<StateRegion> searchStates(String countryCode, String query) {
    if (query.isEmpty) return getStatesForCountry(countryCode);
    final lowerQuery = query.toLowerCase();
    return _states
        .where((s) =>
            s.countryCode == countryCode &&
            s.name.toLowerCase().contains(lowerQuery))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  // ==================== STATIC DATA ====================

  /// List of supported countries (ISO-3166-1).
  static const List<Country> _countries = [
    // North America
    Country(code: 'US', name: 'United States', hasStates: true),
    Country(code: 'CA', name: 'Canada', hasStates: true),
    Country(code: 'MX', name: 'Mexico', hasStates: true),

    // Europe
    Country(code: 'GB', name: 'United Kingdom', hasStates: true),
    Country(code: 'DE', name: 'Germany', hasStates: true),
    Country(code: 'FR', name: 'France', hasStates: true),
    Country(code: 'IT', name: 'Italy', hasStates: true),
    Country(code: 'ES', name: 'Spain', hasStates: true),
    Country(code: 'NL', name: 'Netherlands', hasStates: true),
    Country(code: 'BE', name: 'Belgium', hasStates: true),
    Country(code: 'PT', name: 'Portugal', hasStates: true),
    Country(code: 'AT', name: 'Austria', hasStates: true),
    Country(code: 'CH', name: 'Switzerland', hasStates: true),
    Country(code: 'SE', name: 'Sweden', hasStates: true),
    Country(code: 'NO', name: 'Norway', hasStates: true),
    Country(code: 'DK', name: 'Denmark', hasStates: true),
    Country(code: 'FI', name: 'Finland', hasStates: true),
    Country(code: 'IE', name: 'Ireland', hasStates: true),
    Country(code: 'PL', name: 'Poland', hasStates: true),
    Country(code: 'CZ', name: 'Czech Republic', hasStates: true),
    Country(code: 'RO', name: 'Romania', hasStates: true),
    Country(code: 'GR', name: 'Greece', hasStates: true),
    Country(code: 'HU', name: 'Hungary', hasStates: true),

    // Asia
    Country(code: 'IN', name: 'India', hasStates: true),
    Country(code: 'CN', name: 'China', hasStates: true),
    Country(code: 'JP', name: 'Japan', hasStates: true),
    Country(code: 'KR', name: 'South Korea', hasStates: true),
    Country(code: 'ID', name: 'Indonesia', hasStates: true),
    Country(code: 'TH', name: 'Thailand', hasStates: true),
    Country(code: 'VN', name: 'Vietnam', hasStates: true),
    Country(code: 'PH', name: 'Philippines', hasStates: true),
    Country(code: 'MY', name: 'Malaysia', hasStates: true),
    Country(code: 'SG', name: 'Singapore', hasStates: false), // City-state
    Country(code: 'PK', name: 'Pakistan', hasStates: true),
    Country(code: 'BD', name: 'Bangladesh', hasStates: true),
    Country(code: 'AE', name: 'United Arab Emirates', hasStates: true),
    Country(code: 'SA', name: 'Saudi Arabia', hasStates: true),
    Country(code: 'IL', name: 'Israel', hasStates: true),
    Country(code: 'TR', name: 'Turkey', hasStates: true),

    // Oceania
    Country(code: 'AU', name: 'Australia', hasStates: true),
    Country(code: 'NZ', name: 'New Zealand', hasStates: true),

    // South America
    Country(code: 'BR', name: 'Brazil', hasStates: true),
    Country(code: 'AR', name: 'Argentina', hasStates: true),
    Country(code: 'CO', name: 'Colombia', hasStates: true),
    Country(code: 'CL', name: 'Chile', hasStates: true),
    Country(code: 'PE', name: 'Peru', hasStates: true),
    Country(code: 'VE', name: 'Venezuela', hasStates: true),

    // Africa
    Country(code: 'ZA', name: 'South Africa', hasStates: true),
    Country(code: 'NG', name: 'Nigeria', hasStates: true),
    Country(code: 'EG', name: 'Egypt', hasStates: true),
    Country(code: 'KE', name: 'Kenya', hasStates: true),
    Country(code: 'MA', name: 'Morocco', hasStates: true),
    Country(code: 'GH', name: 'Ghana', hasStates: true),
    Country(code: 'ET', name: 'Ethiopia', hasStates: true),
  ];

  /// List of states/regions (ISO-3166-2 and custom).
  static const List<StateRegion> _states = [
    // ==================== UNITED STATES ====================
    StateRegion(code: 'US-AL', name: 'Alabama', countryCode: 'US'),
    StateRegion(code: 'US-AK', name: 'Alaska', countryCode: 'US'),
    StateRegion(code: 'US-AZ', name: 'Arizona', countryCode: 'US'),
    StateRegion(code: 'US-AR', name: 'Arkansas', countryCode: 'US'),
    StateRegion(code: 'US-CA', name: 'California', countryCode: 'US'),
    StateRegion(code: 'US-CO', name: 'Colorado', countryCode: 'US'),
    StateRegion(code: 'US-CT', name: 'Connecticut', countryCode: 'US'),
    StateRegion(code: 'US-DE', name: 'Delaware', countryCode: 'US'),
    StateRegion(code: 'US-FL', name: 'Florida', countryCode: 'US'),
    StateRegion(code: 'US-GA', name: 'Georgia', countryCode: 'US'),
    StateRegion(code: 'US-HI', name: 'Hawaii', countryCode: 'US'),
    StateRegion(code: 'US-ID', name: 'Idaho', countryCode: 'US'),
    StateRegion(code: 'US-IL', name: 'Illinois', countryCode: 'US'),
    StateRegion(code: 'US-IN', name: 'Indiana', countryCode: 'US'),
    StateRegion(code: 'US-IA', name: 'Iowa', countryCode: 'US'),
    StateRegion(code: 'US-KS', name: 'Kansas', countryCode: 'US'),
    StateRegion(code: 'US-KY', name: 'Kentucky', countryCode: 'US'),
    StateRegion(code: 'US-LA', name: 'Louisiana', countryCode: 'US'),
    StateRegion(code: 'US-ME', name: 'Maine', countryCode: 'US'),
    StateRegion(code: 'US-MD', name: 'Maryland', countryCode: 'US'),
    StateRegion(code: 'US-MA', name: 'Massachusetts', countryCode: 'US'),
    StateRegion(code: 'US-MI', name: 'Michigan', countryCode: 'US'),
    StateRegion(code: 'US-MN', name: 'Minnesota', countryCode: 'US'),
    StateRegion(code: 'US-MS', name: 'Mississippi', countryCode: 'US'),
    StateRegion(code: 'US-MO', name: 'Missouri', countryCode: 'US'),
    StateRegion(code: 'US-MT', name: 'Montana', countryCode: 'US'),
    StateRegion(code: 'US-NE', name: 'Nebraska', countryCode: 'US'),
    StateRegion(code: 'US-NV', name: 'Nevada', countryCode: 'US'),
    StateRegion(code: 'US-NH', name: 'New Hampshire', countryCode: 'US'),
    StateRegion(code: 'US-NJ', name: 'New Jersey', countryCode: 'US'),
    StateRegion(code: 'US-NM', name: 'New Mexico', countryCode: 'US'),
    StateRegion(code: 'US-NY', name: 'New York', countryCode: 'US'),
    StateRegion(code: 'US-NC', name: 'North Carolina', countryCode: 'US'),
    StateRegion(code: 'US-ND', name: 'North Dakota', countryCode: 'US'),
    StateRegion(code: 'US-OH', name: 'Ohio', countryCode: 'US'),
    StateRegion(code: 'US-OK', name: 'Oklahoma', countryCode: 'US'),
    StateRegion(code: 'US-OR', name: 'Oregon', countryCode: 'US'),
    StateRegion(code: 'US-PA', name: 'Pennsylvania', countryCode: 'US'),
    StateRegion(code: 'US-RI', name: 'Rhode Island', countryCode: 'US'),
    StateRegion(code: 'US-SC', name: 'South Carolina', countryCode: 'US'),
    StateRegion(code: 'US-SD', name: 'South Dakota', countryCode: 'US'),
    StateRegion(code: 'US-TN', name: 'Tennessee', countryCode: 'US'),
    StateRegion(code: 'US-TX', name: 'Texas', countryCode: 'US'),
    StateRegion(code: 'US-UT', name: 'Utah', countryCode: 'US'),
    StateRegion(code: 'US-VT', name: 'Vermont', countryCode: 'US'),
    StateRegion(code: 'US-VA', name: 'Virginia', countryCode: 'US'),
    StateRegion(code: 'US-WA', name: 'Washington', countryCode: 'US'),
    StateRegion(code: 'US-WV', name: 'West Virginia', countryCode: 'US'),
    StateRegion(code: 'US-WI', name: 'Wisconsin', countryCode: 'US'),
    StateRegion(code: 'US-WY', name: 'Wyoming', countryCode: 'US'),
    StateRegion(code: 'US-DC', name: 'District of Columbia', countryCode: 'US'),

    // ==================== CANADA ====================
    StateRegion(code: 'CA-AB', name: 'Alberta', countryCode: 'CA'),
    StateRegion(code: 'CA-BC', name: 'British Columbia', countryCode: 'CA'),
    StateRegion(code: 'CA-MB', name: 'Manitoba', countryCode: 'CA'),
    StateRegion(code: 'CA-NB', name: 'New Brunswick', countryCode: 'CA'),
    StateRegion(code: 'CA-NL', name: 'Newfoundland and Labrador', countryCode: 'CA'),
    StateRegion(code: 'CA-NS', name: 'Nova Scotia', countryCode: 'CA'),
    StateRegion(code: 'CA-ON', name: 'Ontario', countryCode: 'CA'),
    StateRegion(code: 'CA-PE', name: 'Prince Edward Island', countryCode: 'CA'),
    StateRegion(code: 'CA-QC', name: 'Quebec', countryCode: 'CA'),
    StateRegion(code: 'CA-SK', name: 'Saskatchewan', countryCode: 'CA'),
    StateRegion(code: 'CA-NT', name: 'Northwest Territories', countryCode: 'CA'),
    StateRegion(code: 'CA-NU', name: 'Nunavut', countryCode: 'CA'),
    StateRegion(code: 'CA-YT', name: 'Yukon', countryCode: 'CA'),

    // ==================== UNITED KINGDOM ====================
    StateRegion(code: 'GB-ENG', name: 'England', countryCode: 'GB'),
    StateRegion(code: 'GB-SCT', name: 'Scotland', countryCode: 'GB'),
    StateRegion(code: 'GB-WLS', name: 'Wales', countryCode: 'GB'),
    StateRegion(code: 'GB-NIR', name: 'Northern Ireland', countryCode: 'GB'),

    // ==================== AUSTRALIA ====================
    StateRegion(code: 'AU-NSW', name: 'New South Wales', countryCode: 'AU'),
    StateRegion(code: 'AU-VIC', name: 'Victoria', countryCode: 'AU'),
    StateRegion(code: 'AU-QLD', name: 'Queensland', countryCode: 'AU'),
    StateRegion(code: 'AU-WA', name: 'Western Australia', countryCode: 'AU'),
    StateRegion(code: 'AU-SA', name: 'South Australia', countryCode: 'AU'),
    StateRegion(code: 'AU-TAS', name: 'Tasmania', countryCode: 'AU'),
    StateRegion(code: 'AU-ACT', name: 'Australian Capital Territory', countryCode: 'AU'),
    StateRegion(code: 'AU-NT', name: 'Northern Territory', countryCode: 'AU'),

    // ==================== INDIA ====================
    StateRegion(code: 'IN-AN', name: 'Andaman and Nicobar Islands', countryCode: 'IN'),
    StateRegion(code: 'IN-AP', name: 'Andhra Pradesh', countryCode: 'IN'),
    StateRegion(code: 'IN-AR', name: 'Arunachal Pradesh', countryCode: 'IN'),
    StateRegion(code: 'IN-AS', name: 'Assam', countryCode: 'IN'),
    StateRegion(code: 'IN-BR', name: 'Bihar', countryCode: 'IN'),
    StateRegion(code: 'IN-CH', name: 'Chandigarh', countryCode: 'IN'),
    StateRegion(code: 'IN-CT', name: 'Chhattisgarh', countryCode: 'IN'),
    StateRegion(code: 'IN-DL', name: 'Delhi', countryCode: 'IN'),
    StateRegion(code: 'IN-GA', name: 'Goa', countryCode: 'IN'),
    StateRegion(code: 'IN-GJ', name: 'Gujarat', countryCode: 'IN'),
    StateRegion(code: 'IN-HR', name: 'Haryana', countryCode: 'IN'),
    StateRegion(code: 'IN-HP', name: 'Himachal Pradesh', countryCode: 'IN'),
    StateRegion(code: 'IN-JK', name: 'Jammu and Kashmir', countryCode: 'IN'),
    StateRegion(code: 'IN-JH', name: 'Jharkhand', countryCode: 'IN'),
    StateRegion(code: 'IN-KA', name: 'Karnataka', countryCode: 'IN'),
    StateRegion(code: 'IN-KL', name: 'Kerala', countryCode: 'IN'),
    StateRegion(code: 'IN-LA', name: 'Ladakh', countryCode: 'IN'),
    StateRegion(code: 'IN-MP', name: 'Madhya Pradesh', countryCode: 'IN'),
    StateRegion(code: 'IN-MH', name: 'Maharashtra', countryCode: 'IN'),
    StateRegion(code: 'IN-MN', name: 'Manipur', countryCode: 'IN'),
    StateRegion(code: 'IN-ML', name: 'Meghalaya', countryCode: 'IN'),
    StateRegion(code: 'IN-MZ', name: 'Mizoram', countryCode: 'IN'),
    StateRegion(code: 'IN-NL', name: 'Nagaland', countryCode: 'IN'),
    StateRegion(code: 'IN-OR', name: 'Odisha', countryCode: 'IN'),
    StateRegion(code: 'IN-PY', name: 'Puducherry', countryCode: 'IN'),
    StateRegion(code: 'IN-PB', name: 'Punjab', countryCode: 'IN'),
    StateRegion(code: 'IN-RJ', name: 'Rajasthan', countryCode: 'IN'),
    StateRegion(code: 'IN-SK', name: 'Sikkim', countryCode: 'IN'),
    StateRegion(code: 'IN-TN', name: 'Tamil Nadu', countryCode: 'IN'),
    StateRegion(code: 'IN-TG', name: 'Telangana', countryCode: 'IN'),
    StateRegion(code: 'IN-TR', name: 'Tripura', countryCode: 'IN'),
    StateRegion(code: 'IN-UP', name: 'Uttar Pradesh', countryCode: 'IN'),
    StateRegion(code: 'IN-UT', name: 'Uttarakhand', countryCode: 'IN'),
    StateRegion(code: 'IN-WB', name: 'West Bengal', countryCode: 'IN'),

    // ==================== GERMANY ====================
    StateRegion(code: 'DE-BW', name: 'Baden-Württemberg', countryCode: 'DE'),
    StateRegion(code: 'DE-BY', name: 'Bavaria', countryCode: 'DE'),
    StateRegion(code: 'DE-BE', name: 'Berlin', countryCode: 'DE'),
    StateRegion(code: 'DE-BB', name: 'Brandenburg', countryCode: 'DE'),
    StateRegion(code: 'DE-HB', name: 'Bremen', countryCode: 'DE'),
    StateRegion(code: 'DE-HH', name: 'Hamburg', countryCode: 'DE'),
    StateRegion(code: 'DE-HE', name: 'Hesse', countryCode: 'DE'),
    StateRegion(code: 'DE-NI', name: 'Lower Saxony', countryCode: 'DE'),
    StateRegion(code: 'DE-MV', name: 'Mecklenburg-Vorpommern', countryCode: 'DE'),
    StateRegion(code: 'DE-NW', name: 'North Rhine-Westphalia', countryCode: 'DE'),
    StateRegion(code: 'DE-RP', name: 'Rhineland-Palatinate', countryCode: 'DE'),
    StateRegion(code: 'DE-SL', name: 'Saarland', countryCode: 'DE'),
    StateRegion(code: 'DE-SN', name: 'Saxony', countryCode: 'DE'),
    StateRegion(code: 'DE-ST', name: 'Saxony-Anhalt', countryCode: 'DE'),
    StateRegion(code: 'DE-SH', name: 'Schleswig-Holstein', countryCode: 'DE'),
    StateRegion(code: 'DE-TH', name: 'Thuringia', countryCode: 'DE'),

    // ==================== BRAZIL ====================
    StateRegion(code: 'BR-AC', name: 'Acre', countryCode: 'BR'),
    StateRegion(code: 'BR-AL', name: 'Alagoas', countryCode: 'BR'),
    StateRegion(code: 'BR-AP', name: 'Amapá', countryCode: 'BR'),
    StateRegion(code: 'BR-AM', name: 'Amazonas', countryCode: 'BR'),
    StateRegion(code: 'BR-BA', name: 'Bahia', countryCode: 'BR'),
    StateRegion(code: 'BR-CE', name: 'Ceará', countryCode: 'BR'),
    StateRegion(code: 'BR-DF', name: 'Distrito Federal', countryCode: 'BR'),
    StateRegion(code: 'BR-ES', name: 'Espírito Santo', countryCode: 'BR'),
    StateRegion(code: 'BR-GO', name: 'Goiás', countryCode: 'BR'),
    StateRegion(code: 'BR-MA', name: 'Maranhão', countryCode: 'BR'),
    StateRegion(code: 'BR-MT', name: 'Mato Grosso', countryCode: 'BR'),
    StateRegion(code: 'BR-MS', name: 'Mato Grosso do Sul', countryCode: 'BR'),
    StateRegion(code: 'BR-MG', name: 'Minas Gerais', countryCode: 'BR'),
    StateRegion(code: 'BR-PA', name: 'Pará', countryCode: 'BR'),
    StateRegion(code: 'BR-PB', name: 'Paraíba', countryCode: 'BR'),
    StateRegion(code: 'BR-PR', name: 'Paraná', countryCode: 'BR'),
    StateRegion(code: 'BR-PE', name: 'Pernambuco', countryCode: 'BR'),
    StateRegion(code: 'BR-PI', name: 'Piauí', countryCode: 'BR'),
    StateRegion(code: 'BR-RJ', name: 'Rio de Janeiro', countryCode: 'BR'),
    StateRegion(code: 'BR-RN', name: 'Rio Grande do Norte', countryCode: 'BR'),
    StateRegion(code: 'BR-RS', name: 'Rio Grande do Sul', countryCode: 'BR'),
    StateRegion(code: 'BR-RO', name: 'Rondônia', countryCode: 'BR'),
    StateRegion(code: 'BR-RR', name: 'Roraima', countryCode: 'BR'),
    StateRegion(code: 'BR-SC', name: 'Santa Catarina', countryCode: 'BR'),
    StateRegion(code: 'BR-SP', name: 'São Paulo', countryCode: 'BR'),
    StateRegion(code: 'BR-SE', name: 'Sergipe', countryCode: 'BR'),
    StateRegion(code: 'BR-TO', name: 'Tocantins', countryCode: 'BR'),

    // ==================== JAPAN ====================
    StateRegion(code: 'JP-01', name: 'Hokkaido', countryCode: 'JP'),
    StateRegion(code: 'JP-02', name: 'Aomori', countryCode: 'JP'),
    StateRegion(code: 'JP-13', name: 'Tokyo', countryCode: 'JP'),
    StateRegion(code: 'JP-14', name: 'Kanagawa', countryCode: 'JP'),
    StateRegion(code: 'JP-23', name: 'Aichi', countryCode: 'JP'),
    StateRegion(code: 'JP-26', name: 'Kyoto', countryCode: 'JP'),
    StateRegion(code: 'JP-27', name: 'Osaka', countryCode: 'JP'),
    StateRegion(code: 'JP-28', name: 'Hyogo', countryCode: 'JP'),
    StateRegion(code: 'JP-40', name: 'Fukuoka', countryCode: 'JP'),
    StateRegion(code: 'JP-47', name: 'Okinawa', countryCode: 'JP'),

    // ==================== MEXICO ====================
    StateRegion(code: 'MX-AGU', name: 'Aguascalientes', countryCode: 'MX'),
    StateRegion(code: 'MX-BCN', name: 'Baja California', countryCode: 'MX'),
    StateRegion(code: 'MX-BCS', name: 'Baja California Sur', countryCode: 'MX'),
    StateRegion(code: 'MX-CMX', name: 'Ciudad de México', countryCode: 'MX'),
    StateRegion(code: 'MX-GUA', name: 'Guanajuato', countryCode: 'MX'),
    StateRegion(code: 'MX-JAL', name: 'Jalisco', countryCode: 'MX'),
    StateRegion(code: 'MX-MEX', name: 'México', countryCode: 'MX'),
    StateRegion(code: 'MX-NLE', name: 'Nuevo León', countryCode: 'MX'),
    StateRegion(code: 'MX-QUE', name: 'Querétaro', countryCode: 'MX'),
    StateRegion(code: 'MX-YUC', name: 'Yucatán', countryCode: 'MX'),

    // ==================== FRANCE ====================
    StateRegion(code: 'FR-IDF', name: 'Île-de-France', countryCode: 'FR'),
    StateRegion(code: 'FR-ARA', name: 'Auvergne-Rhône-Alpes', countryCode: 'FR'),
    StateRegion(code: 'FR-NAQ', name: 'Nouvelle-Aquitaine', countryCode: 'FR'),
    StateRegion(code: 'FR-OCC', name: 'Occitanie', countryCode: 'FR'),
    StateRegion(code: 'FR-PAC', name: "Provence-Alpes-Côte d'Azur", countryCode: 'FR'),
    StateRegion(code: 'FR-BRE', name: 'Brittany', countryCode: 'FR'),
    StateRegion(code: 'FR-NOR', name: 'Normandy', countryCode: 'FR'),
    StateRegion(code: 'FR-HDF', name: 'Hauts-de-France', countryCode: 'FR'),
    StateRegion(code: 'FR-GES', name: 'Grand Est', countryCode: 'FR'),
    StateRegion(code: 'FR-PDL', name: 'Pays de la Loire', countryCode: 'FR'),

    // ==================== SPAIN ====================
    StateRegion(code: 'ES-MD', name: 'Madrid', countryCode: 'ES'),
    StateRegion(code: 'ES-CT', name: 'Catalonia', countryCode: 'ES'),
    StateRegion(code: 'ES-AN', name: 'Andalusia', countryCode: 'ES'),
    StateRegion(code: 'ES-VC', name: 'Valencia', countryCode: 'ES'),
    StateRegion(code: 'ES-GA', name: 'Galicia', countryCode: 'ES'),
    StateRegion(code: 'ES-PV', name: 'Basque Country', countryCode: 'ES'),
    StateRegion(code: 'ES-CL', name: 'Castile and León', countryCode: 'ES'),
    StateRegion(code: 'ES-CM', name: 'Castilla-La Mancha', countryCode: 'ES'),
    StateRegion(code: 'ES-CN', name: 'Canary Islands', countryCode: 'ES'),
    StateRegion(code: 'ES-IB', name: 'Balearic Islands', countryCode: 'ES'),

    // ==================== ITALY ====================
    StateRegion(code: 'IT-25', name: 'Lombardy', countryCode: 'IT'),
    StateRegion(code: 'IT-62', name: 'Lazio', countryCode: 'IT'),
    StateRegion(code: 'IT-72', name: 'Campania', countryCode: 'IT'),
    StateRegion(code: 'IT-82', name: 'Sicily', countryCode: 'IT'),
    StateRegion(code: 'IT-21', name: 'Piedmont', countryCode: 'IT'),
    StateRegion(code: 'IT-45', name: 'Emilia-Romagna', countryCode: 'IT'),
    StateRegion(code: 'IT-34', name: 'Veneto', countryCode: 'IT'),
    StateRegion(code: 'IT-52', name: 'Tuscany', countryCode: 'IT'),
    StateRegion(code: 'IT-75', name: 'Apulia', countryCode: 'IT'),
    StateRegion(code: 'IT-78', name: 'Calabria', countryCode: 'IT'),

    // ==================== CHINA ====================
    StateRegion(code: 'CN-BJ', name: 'Beijing', countryCode: 'CN'),
    StateRegion(code: 'CN-SH', name: 'Shanghai', countryCode: 'CN'),
    StateRegion(code: 'CN-GD', name: 'Guangdong', countryCode: 'CN'),
    StateRegion(code: 'CN-JS', name: 'Jiangsu', countryCode: 'CN'),
    StateRegion(code: 'CN-ZJ', name: 'Zhejiang', countryCode: 'CN'),
    StateRegion(code: 'CN-SC', name: 'Sichuan', countryCode: 'CN'),
    StateRegion(code: 'CN-HB', name: 'Hubei', countryCode: 'CN'),
    StateRegion(code: 'CN-HN', name: 'Hunan', countryCode: 'CN'),
    StateRegion(code: 'CN-SD', name: 'Shandong', countryCode: 'CN'),
    StateRegion(code: 'CN-FJ', name: 'Fujian', countryCode: 'CN'),

    // ==================== SOUTH KOREA ====================
    StateRegion(code: 'KR-11', name: 'Seoul', countryCode: 'KR'),
    StateRegion(code: 'KR-26', name: 'Busan', countryCode: 'KR'),
    StateRegion(code: 'KR-28', name: 'Incheon', countryCode: 'KR'),
    StateRegion(code: 'KR-41', name: 'Gyeonggi', countryCode: 'KR'),
    StateRegion(code: 'KR-48', name: 'South Gyeongsang', countryCode: 'KR'),

    // ==================== SINGAPORE (City-State) ====================
    StateRegion(code: 'SG-NATIONAL', name: 'National', countryCode: 'SG'),

    // ==================== UAE ====================
    StateRegion(code: 'AE-DU', name: 'Dubai', countryCode: 'AE'),
    StateRegion(code: 'AE-AZ', name: 'Abu Dhabi', countryCode: 'AE'),
    StateRegion(code: 'AE-SH', name: 'Sharjah', countryCode: 'AE'),
    StateRegion(code: 'AE-AJ', name: 'Ajman', countryCode: 'AE'),
    StateRegion(code: 'AE-FU', name: 'Fujairah', countryCode: 'AE'),
    StateRegion(code: 'AE-RK', name: 'Ras al-Khaimah', countryCode: 'AE'),
    StateRegion(code: 'AE-UQ', name: 'Umm al-Quwain', countryCode: 'AE'),

    // ==================== SOUTH AFRICA ====================
    StateRegion(code: 'ZA-GP', name: 'Gauteng', countryCode: 'ZA'),
    StateRegion(code: 'ZA-WC', name: 'Western Cape', countryCode: 'ZA'),
    StateRegion(code: 'ZA-KZN', name: 'KwaZulu-Natal', countryCode: 'ZA'),
    StateRegion(code: 'ZA-EC', name: 'Eastern Cape', countryCode: 'ZA'),
    StateRegion(code: 'ZA-FS', name: 'Free State', countryCode: 'ZA'),
    StateRegion(code: 'ZA-LP', name: 'Limpopo', countryCode: 'ZA'),
    StateRegion(code: 'ZA-MP', name: 'Mpumalanga', countryCode: 'ZA'),
    StateRegion(code: 'ZA-NC', name: 'Northern Cape', countryCode: 'ZA'),
    StateRegion(code: 'ZA-NW', name: 'North West', countryCode: 'ZA'),

    // ==================== NEW ZEALAND ====================
    StateRegion(code: 'NZ-AUK', name: 'Auckland', countryCode: 'NZ'),
    StateRegion(code: 'NZ-WGN', name: 'Wellington', countryCode: 'NZ'),
    StateRegion(code: 'NZ-CAN', name: 'Canterbury', countryCode: 'NZ'),
    StateRegion(code: 'NZ-WKO', name: 'Waikato', countryCode: 'NZ'),
    StateRegion(code: 'NZ-OTA', name: 'Otago', countryCode: 'NZ'),

    // ==================== COUNTRIES WITHOUT STATES (Use National) ====================
    // These are added dynamically when needed via StateRegion.national()

    // ==================== OTHER COUNTRIES - BASIC REGIONS ====================
    // Netherlands
    StateRegion(code: 'NL-NH', name: 'North Holland', countryCode: 'NL'),
    StateRegion(code: 'NL-ZH', name: 'South Holland', countryCode: 'NL'),
    StateRegion(code: 'NL-NB', name: 'North Brabant', countryCode: 'NL'),
    StateRegion(code: 'NL-GE', name: 'Gelderland', countryCode: 'NL'),
    StateRegion(code: 'NL-UT', name: 'Utrecht', countryCode: 'NL'),

    // Belgium
    StateRegion(code: 'BE-BRU', name: 'Brussels', countryCode: 'BE'),
    StateRegion(code: 'BE-VLG', name: 'Flanders', countryCode: 'BE'),
    StateRegion(code: 'BE-WAL', name: 'Wallonia', countryCode: 'BE'),

    // Switzerland
    StateRegion(code: 'CH-ZH', name: 'Zürich', countryCode: 'CH'),
    StateRegion(code: 'CH-BE', name: 'Bern', countryCode: 'CH'),
    StateRegion(code: 'CH-GE', name: 'Geneva', countryCode: 'CH'),
    StateRegion(code: 'CH-VD', name: 'Vaud', countryCode: 'CH'),
    StateRegion(code: 'CH-BS', name: 'Basel-Stadt', countryCode: 'CH'),

    // Ireland
    StateRegion(code: 'IE-D', name: 'Dublin', countryCode: 'IE'),
    StateRegion(code: 'IE-C', name: 'Cork', countryCode: 'IE'),
    StateRegion(code: 'IE-G', name: 'Galway', countryCode: 'IE'),
    StateRegion(code: 'IE-L', name: 'Leinster', countryCode: 'IE'),
    StateRegion(code: 'IE-M', name: 'Munster', countryCode: 'IE'),

    // Austria
    StateRegion(code: 'AT-9', name: 'Vienna', countryCode: 'AT'),
    StateRegion(code: 'AT-6', name: 'Styria', countryCode: 'AT'),
    StateRegion(code: 'AT-4', name: 'Upper Austria', countryCode: 'AT'),
    StateRegion(code: 'AT-3', name: 'Lower Austria', countryCode: 'AT'),
    StateRegion(code: 'AT-5', name: 'Salzburg', countryCode: 'AT'),
    StateRegion(code: 'AT-7', name: 'Tyrol', countryCode: 'AT'),

    // Poland
    StateRegion(code: 'PL-14', name: 'Mazovia', countryCode: 'PL'),
    StateRegion(code: 'PL-12', name: 'Lesser Poland', countryCode: 'PL'),
    StateRegion(code: 'PL-30', name: 'Greater Poland', countryCode: 'PL'),
    StateRegion(code: 'PL-04', name: 'Lower Silesia', countryCode: 'PL'),
    StateRegion(code: 'PL-24', name: 'Silesia', countryCode: 'PL'),

    // Turkey
    StateRegion(code: 'TR-34', name: 'Istanbul', countryCode: 'TR'),
    StateRegion(code: 'TR-06', name: 'Ankara', countryCode: 'TR'),
    StateRegion(code: 'TR-35', name: 'Izmir', countryCode: 'TR'),
    StateRegion(code: 'TR-07', name: 'Antalya', countryCode: 'TR'),
    StateRegion(code: 'TR-16', name: 'Bursa', countryCode: 'TR'),

    // Israel
    StateRegion(code: 'IL-TA', name: 'Tel Aviv', countryCode: 'IL'),
    StateRegion(code: 'IL-JM', name: 'Jerusalem', countryCode: 'IL'),
    StateRegion(code: 'IL-HA', name: 'Haifa', countryCode: 'IL'),
    StateRegion(code: 'IL-M', name: 'Central', countryCode: 'IL'),
    StateRegion(code: 'IL-Z', name: 'Northern', countryCode: 'IL'),

    // Argentina
    StateRegion(code: 'AR-C', name: 'Buenos Aires City', countryCode: 'AR'),
    StateRegion(code: 'AR-B', name: 'Buenos Aires Province', countryCode: 'AR'),
    StateRegion(code: 'AR-X', name: 'Córdoba', countryCode: 'AR'),
    StateRegion(code: 'AR-S', name: 'Santa Fe', countryCode: 'AR'),
    StateRegion(code: 'AR-M', name: 'Mendoza', countryCode: 'AR'),

    // Colombia
    StateRegion(code: 'CO-DC', name: 'Bogotá', countryCode: 'CO'),
    StateRegion(code: 'CO-ANT', name: 'Antioquia', countryCode: 'CO'),
    StateRegion(code: 'CO-VAC', name: 'Valle del Cauca', countryCode: 'CO'),
    StateRegion(code: 'CO-ATL', name: 'Atlántico', countryCode: 'CO'),
    StateRegion(code: 'CO-SAN', name: 'Santander', countryCode: 'CO'),

    // Chile
    StateRegion(code: 'CL-RM', name: 'Santiago Metropolitan', countryCode: 'CL'),
    StateRegion(code: 'CL-VS', name: 'Valparaíso', countryCode: 'CL'),
    StateRegion(code: 'CL-BI', name: 'Biobío', countryCode: 'CL'),
    StateRegion(code: 'CL-ML', name: 'Maule', countryCode: 'CL'),
    StateRegion(code: 'CL-AR', name: 'Araucanía', countryCode: 'CL'),

    // Peru  
    StateRegion(code: 'PE-LIM', name: 'Lima', countryCode: 'PE'),
    StateRegion(code: 'PE-AQP', name: 'Arequipa', countryCode: 'PE'),
    StateRegion(code: 'PE-LAL', name: 'La Libertad', countryCode: 'PE'),
    StateRegion(code: 'PE-CUS', name: 'Cusco', countryCode: 'PE'),
    StateRegion(code: 'PE-PIU', name: 'Piura', countryCode: 'PE'),

    // Indonesia
    StateRegion(code: 'ID-JK', name: 'Jakarta', countryCode: 'ID'),
    StateRegion(code: 'ID-JB', name: 'West Java', countryCode: 'ID'),
    StateRegion(code: 'ID-JT', name: 'Central Java', countryCode: 'ID'),
    StateRegion(code: 'ID-JI', name: 'East Java', countryCode: 'ID'),
    StateRegion(code: 'ID-BA', name: 'Bali', countryCode: 'ID'),

    // Thailand
    StateRegion(code: 'TH-10', name: 'Bangkok', countryCode: 'TH'),
    StateRegion(code: 'TH-50', name: 'Chiang Mai', countryCode: 'TH'),
    StateRegion(code: 'TH-83', name: 'Phuket', countryCode: 'TH'),
    StateRegion(code: 'TH-20', name: 'Chonburi', countryCode: 'TH'),
    StateRegion(code: 'TH-40', name: 'Khon Kaen', countryCode: 'TH'),

    // Vietnam
    StateRegion(code: 'VN-HN', name: 'Hanoi', countryCode: 'VN'),
    StateRegion(code: 'VN-SG', name: 'Ho Chi Minh City', countryCode: 'VN'),
    StateRegion(code: 'VN-DN', name: 'Da Nang', countryCode: 'VN'),
    StateRegion(code: 'VN-HP', name: 'Hai Phong', countryCode: 'VN'),
    StateRegion(code: 'VN-CT', name: 'Can Tho', countryCode: 'VN'),

    // Philippines
    StateRegion(code: 'PH-00', name: 'Metro Manila', countryCode: 'PH'),
    StateRegion(code: 'PH-CEB', name: 'Cebu', countryCode: 'PH'),
    StateRegion(code: 'PH-DAV', name: 'Davao', countryCode: 'PH'),
    StateRegion(code: 'PH-ILI', name: 'Iloilo', countryCode: 'PH'),
    StateRegion(code: 'PH-ZMB', name: 'Zamboanga', countryCode: 'PH'),

    // Malaysia
    StateRegion(code: 'MY-14', name: 'Kuala Lumpur', countryCode: 'MY'),
    StateRegion(code: 'MY-10', name: 'Selangor', countryCode: 'MY'),
    StateRegion(code: 'MY-07', name: 'Penang', countryCode: 'MY'),
    StateRegion(code: 'MY-01', name: 'Johor', countryCode: 'MY'),
    StateRegion(code: 'MY-12', name: 'Sabah', countryCode: 'MY'),

    // Pakistan
    StateRegion(code: 'PK-PB', name: 'Punjab', countryCode: 'PK'),
    StateRegion(code: 'PK-SD', name: 'Sindh', countryCode: 'PK'),
    StateRegion(code: 'PK-KP', name: 'Khyber Pakhtunkhwa', countryCode: 'PK'),
    StateRegion(code: 'PK-BA', name: 'Balochistan', countryCode: 'PK'),
    StateRegion(code: 'PK-IS', name: 'Islamabad', countryCode: 'PK'),

    // Bangladesh
    StateRegion(code: 'BD-A', name: 'Dhaka', countryCode: 'BD'),
    StateRegion(code: 'BD-B', name: 'Chittagong', countryCode: 'BD'),
    StateRegion(code: 'BD-C', name: 'Khulna', countryCode: 'BD'),
    StateRegion(code: 'BD-D', name: 'Rajshahi', countryCode: 'BD'),
    StateRegion(code: 'BD-E', name: 'Sylhet', countryCode: 'BD'),

    // Saudi Arabia
    StateRegion(code: 'SA-01', name: 'Riyadh', countryCode: 'SA'),
    StateRegion(code: 'SA-02', name: 'Makkah', countryCode: 'SA'),
    StateRegion(code: 'SA-04', name: 'Eastern Province', countryCode: 'SA'),
    StateRegion(code: 'SA-03', name: 'Madinah', countryCode: 'SA'),
    StateRegion(code: 'SA-14', name: 'Asir', countryCode: 'SA'),

    // Nigeria
    StateRegion(code: 'NG-LA', name: 'Lagos', countryCode: 'NG'),
    StateRegion(code: 'NG-FC', name: 'Abuja', countryCode: 'NG'),
    StateRegion(code: 'NG-KN', name: 'Kano', countryCode: 'NG'),
    StateRegion(code: 'NG-RI', name: 'Rivers', countryCode: 'NG'),
    StateRegion(code: 'NG-OY', name: 'Oyo', countryCode: 'NG'),

    // Egypt
    StateRegion(code: 'EG-C', name: 'Cairo', countryCode: 'EG'),
    StateRegion(code: 'EG-ALX', name: 'Alexandria', countryCode: 'EG'),
    StateRegion(code: 'EG-GZ', name: 'Giza', countryCode: 'EG'),
    StateRegion(code: 'EG-SHR', name: 'Sharqia', countryCode: 'EG'),
    StateRegion(code: 'EG-ASN', name: 'Aswan', countryCode: 'EG'),

    // Kenya
    StateRegion(code: 'KE-30', name: 'Nairobi', countryCode: 'KE'),
    StateRegion(code: 'KE-01', name: 'Mombasa', countryCode: 'KE'),
    StateRegion(code: 'KE-22', name: 'Kisumu', countryCode: 'KE'),
    StateRegion(code: 'KE-18', name: 'Nakuru', countryCode: 'KE'),
    StateRegion(code: 'KE-47', name: 'Nairobi County', countryCode: 'KE'),

    // Ghana
    StateRegion(code: 'GH-AA', name: 'Greater Accra', countryCode: 'GH'),
    StateRegion(code: 'GH-AH', name: 'Ashanti', countryCode: 'GH'),
    StateRegion(code: 'GH-WP', name: 'Western', countryCode: 'GH'),
    StateRegion(code: 'GH-EP', name: 'Eastern', countryCode: 'GH'),
    StateRegion(code: 'GH-CP', name: 'Central', countryCode: 'GH'),

    // Morocco
    StateRegion(code: 'MA-CAS', name: 'Casablanca-Settat', countryCode: 'MA'),
    StateRegion(code: 'MA-RAB', name: 'Rabat-Salé-Kénitra', countryCode: 'MA'),
    StateRegion(code: 'MA-MAR', name: 'Marrakech-Safi', countryCode: 'MA'),
    StateRegion(code: 'MA-FES', name: 'Fès-Meknès', countryCode: 'MA'),
    StateRegion(code: 'MA-TAN', name: 'Tanger-Tétouan-Al Hoceïma', countryCode: 'MA'),

    // Ethiopia
    StateRegion(code: 'ET-AA', name: 'Addis Ababa', countryCode: 'ET'),
    StateRegion(code: 'ET-OR', name: 'Oromia', countryCode: 'ET'),
    StateRegion(code: 'ET-AM', name: 'Amhara', countryCode: 'ET'),
    StateRegion(code: 'ET-SN', name: 'Southern Nations', countryCode: 'ET'),
    StateRegion(code: 'ET-TI', name: 'Tigray', countryCode: 'ET'),

    // Other Nordics
    StateRegion(code: 'SE-AB', name: 'Stockholm', countryCode: 'SE'),
    StateRegion(code: 'SE-O', name: 'Västra Götaland', countryCode: 'SE'),
    StateRegion(code: 'SE-M', name: 'Skåne', countryCode: 'SE'),
    StateRegion(code: 'NO-03', name: 'Oslo', countryCode: 'NO'),
    StateRegion(code: 'NO-46', name: 'Vestland', countryCode: 'NO'),
    StateRegion(code: 'NO-50', name: 'Trøndelag', countryCode: 'NO'),
    StateRegion(code: 'DK-84', name: 'Capital Region', countryCode: 'DK'),
    StateRegion(code: 'DK-82', name: 'Central Denmark', countryCode: 'DK'),
    StateRegion(code: 'DK-83', name: 'Southern Denmark', countryCode: 'DK'),
    StateRegion(code: 'FI-18', name: 'Uusimaa', countryCode: 'FI'),
    StateRegion(code: 'FI-06', name: 'Pirkanmaa', countryCode: 'FI'),
    StateRegion(code: 'FI-02', name: 'Southwest Finland', countryCode: 'FI'),

    // Eastern Europe
    StateRegion(code: 'CZ-10', name: 'Prague', countryCode: 'CZ'),
    StateRegion(code: 'CZ-64', name: 'South Moravian', countryCode: 'CZ'),
    StateRegion(code: 'CZ-20', name: 'Central Bohemia', countryCode: 'CZ'),
    StateRegion(code: 'RO-B', name: 'Bucharest', countryCode: 'RO'),
    StateRegion(code: 'RO-CJ', name: 'Cluj', countryCode: 'RO'),
    StateRegion(code: 'RO-TM', name: 'Timiș', countryCode: 'RO'),
    StateRegion(code: 'GR-A1', name: 'Attica', countryCode: 'GR'),
    StateRegion(code: 'GR-B', name: 'Central Macedonia', countryCode: 'GR'),
    StateRegion(code: 'GR-J', name: 'Crete', countryCode: 'GR'),
    StateRegion(code: 'HU-BU', name: 'Budapest', countryCode: 'HU'),
    StateRegion(code: 'HU-PE', name: 'Pest', countryCode: 'HU'),
    StateRegion(code: 'HU-CS', name: 'Csongrád-Csanád', countryCode: 'HU'),

    // Portugal
    StateRegion(code: 'PT-11', name: 'Lisbon', countryCode: 'PT'),
    StateRegion(code: 'PT-13', name: 'Porto', countryCode: 'PT'),
    StateRegion(code: 'PT-08', name: 'Faro', countryCode: 'PT'),
    StateRegion(code: 'PT-06', name: 'Coimbra', countryCode: 'PT'),
    StateRegion(code: 'PT-01', name: 'Aveiro', countryCode: 'PT'),

    // Venezuela
    StateRegion(code: 'VE-A', name: 'Capital District', countryCode: 'VE'),
    StateRegion(code: 'VE-M', name: 'Miranda', countryCode: 'VE'),
    StateRegion(code: 'VE-S', name: 'Zulia', countryCode: 'VE'),
    StateRegion(code: 'VE-G', name: 'Carabobo', countryCode: 'VE'),
    StateRegion(code: 'VE-K', name: 'Lara', countryCode: 'VE'),
  ];
}
