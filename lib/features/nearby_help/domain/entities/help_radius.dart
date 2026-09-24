/// Predefined radius options for help discovery.
enum HelpRadius {
  /// 50 meters - very close proximity
  meters50(50, '50m'),

  /// 100 meters - nearby
  meters100(100, '100m'),

  /// 500 meters - extended range
  meters500(500, '500m'),

  /// 1 kilometer - wide area
  kilometers1(1000, '1km'),

  /// 2 kilometers - very wide area
  kilometers2(2000, '2km');

  final int meters;
  final String displayName;

  const HelpRadius(this.meters, this.displayName);

  /// Convert radius in meters to approximate degrees for geospatial queries.
  /// 1 degree of latitude â‰ˆ 111,139 meters.
  double get degreesLatitude => meters / 111139.0;

  /// Longitude degrees vary by latitude, but for simplicity we use the same approximation.
  /// This is acceptable for small distances.
  double get degreesLongitude => meters / 111139.0;

  static HelpRadius fromMeters(int meters) {
    switch (meters) {
      case 50:
        return HelpRadius.meters50;
      case 100:
        return HelpRadius.meters100;
      case 500:
        return HelpRadius.meters500;
      case 1000:
        return HelpRadius.kilometers1;
      case 2000:
        return HelpRadius.kilometers2;
      default:
        return HelpRadius.meters100;
    }
  }
}
