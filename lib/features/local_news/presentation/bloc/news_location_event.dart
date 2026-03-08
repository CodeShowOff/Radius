part of 'news_location_bloc.dart';

/// Base class for news location events.
abstract class NewsLocationEvent extends Equatable {
  const NewsLocationEvent();

  @override
  List<Object?> get props => [];
}

/// Check if the user already has a saved news location.
class NewsLocationCheckRequested extends NewsLocationEvent {
  final String userId;

  const NewsLocationCheckRequested({required this.userId});

  @override
  List<Object?> get props => [userId];
}

/// User chose to detect location via GPS.
class NewsLocationGpsRequested extends NewsLocationEvent {
  const NewsLocationGpsRequested();
}

/// User selected a location manually (from search or dropdown).
class NewsLocationManualSelected extends NewsLocationEvent {
  final String district;
  final String city;
  final String country;
  final double latitude;
  final double longitude;
  final String locality;

  const NewsLocationManualSelected({
    required this.district,
    required this.city,
    required this.country,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.locality = '',
  });

  @override
  List<Object?> get props =>
      [district, city, country, latitude, longitude, locality];
}

/// User confirmed and wants to save the detected/selected location.
class NewsLocationSaveRequested extends NewsLocationEvent {
  final String userId;

  const NewsLocationSaveRequested({required this.userId});

  @override
  List<Object?> get props => [userId];
}

/// User wants to change their saved location (reset to setup).
class NewsLocationChangeRequested extends NewsLocationEvent {
  const NewsLocationChangeRequested();
}
