part of 'profile_bloc.dart';

/// Base class for all profile states.
abstract class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

/// Initial state before profile is loaded.
class ProfileInitial extends ProfileState {}

/// State while profile is loading.
class ProfileLoading extends ProfileState {}

/// State when profile is successfully loaded.
class ProfileLoaded extends ProfileState {
  final Profile profile;

  const ProfileLoaded(this.profile);

  @override
  List<Object?> get props => [profile];
}

/// State while profile is being saved.
class ProfileSaving extends ProfileState {
  final Profile profile;

  const ProfileSaving(this.profile);

  @override
  List<Object?> get props => [profile];
}

/// State after profile is successfully saved.
class ProfileSaved extends ProfileState {
  final Profile profile;

  const ProfileSaved(this.profile);

  @override
  List<Object?> get props => [profile];
}

/// State when a profile error occurs.
class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
