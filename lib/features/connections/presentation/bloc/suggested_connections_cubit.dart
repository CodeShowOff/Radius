import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/connection_service.dart';
import 'suggested_connections_state.dart';

class SuggestedConnectionsCubit extends Cubit<SuggestedConnectionsState> {
  final ConnectionService _connectionService;

  SuggestedConnectionsCubit(this._connectionService)
      : super(SuggestedConnectionsInitial());

  Future<void> loadSuggestions(String userId) async {
    try {
      emit(SuggestedConnectionsLoading());
      final suggestions = await _connectionService.getSuggestedConnections(userId);
      emit(SuggestedConnectionsLoaded(suggestions));
    } catch (e) {
      emit(SuggestedConnectionsError('Failed to load suggestions: $e'));
    }
  }
}
