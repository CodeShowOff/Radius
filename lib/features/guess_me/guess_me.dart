/// GuessMe feature - Anonymous game-based chat with nearby users.
///
/// This feature allows users to:
/// - Get matched anonymously with nearby users
/// - Chat for up to 1 hour without knowing identities
/// - Use a "Guess Check" to verify if they know who the other person is
/// - Earn badges based on correct guesses
library;

// Domain entities
export 'domain/entities/guess_me_session.dart';
export 'domain/entities/guess_me_stats.dart';

// Data layer
export 'data/models/guess_me_models.dart';
export 'data/models/guess_me_stats_model.dart';
export 'data/guess_me_service.dart';

// Presentation
export 'presentation/bloc/guess_me_bloc.dart';
export 'presentation/pages/guess_me_lobby_page.dart';
export 'presentation/pages/guess_me_game_page.dart';
export 'presentation/widgets/guess_me_badge_widget.dart';
