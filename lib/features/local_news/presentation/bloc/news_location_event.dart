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

/// User selected a location manually (from country/city picker).
class NewsLocationManualSelected extends NewsLocationEvent {
  final String city;
  final String country;

  const NewsLocationManualSelected({
    required this.city,
    required this.country,
  });

  @override
  List<Object?> get props => [city, country];
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
