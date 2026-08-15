import 'package:equatable/equatable.dart';

sealed class SuggestedConnectionsState extends Equatable {
  const SuggestedConnectionsState();

  @override
  List<Object?> get props => [];
}

class SuggestedConnectionsInitial extends SuggestedConnectionsState {}

class SuggestedConnectionsLoading extends SuggestedConnectionsState {}

class SuggestedConnectionsLoaded extends SuggestedConnectionsState {
  final List<Map<String, dynamic>> suggestions;

  const SuggestedConnectionsLoaded(this.suggestions);

  @override
  List<Object?> get props => [suggestions];
}

class SuggestedConnectionsError extends SuggestedConnectionsState {
  final String message;

  const SuggestedConnectionsError(this.message);

  @override
  List<Object?> get props => [message];
}
