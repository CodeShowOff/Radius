/// Predefined radius options for help discovery.
enum HelpRadius {
  /// 10 meters - very close proximity
  meters10(10, '10 meters'),

  /// 50 meters - nearby
  meters50(50, '50 meters'),

  /// 100 meters - extended range
  meters100(100, '100 meters');

  final int meters;
  final String displayName;

  const HelpRadius(this.meters, this.displayName);

  /// Convert radius in meters to approximate degrees for geospatial queries.
  /// 1 degree of latitude ≈ 111,139 meters.
  double get degreesLatitude => meters / 111139.0;

  /// Longitude degrees vary by latitude, but for simplicity we use the same approximation.
  /// This is acceptable for small distances.
  double get degreesLongitude => meters / 111139.0;

  static HelpRadius fromMeters(int meters) {
    switch (meters) {
      case 10:
        return HelpRadius.meters10;
      case 50:
        return HelpRadius.meters50;
      case 100:
        return HelpRadius.meters100;
      default:
        return HelpRadius.meters50;
    }
  }
}
