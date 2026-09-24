part of 'create_news_post_bloc.dart';

/// Base class for create news post events.
abstract class CreateNewsPostEvent extends Equatable {
  const CreateNewsPostEvent();

  @override
  List<Object?> get props => [];
}

/// User picked media files (images/videos) to add.
class CreateNewsPostMediaAdded extends CreateNewsPostEvent {
  final List<File> files;

  const CreateNewsPostMediaAdded(this.files);

  @override
  List<Object?> get props => [files];
}

/// User removed a media item by index.
class CreateNewsPostMediaRemoved extends CreateNewsPostEvent {
  final int index;

  const CreateNewsPostMediaRemoved(this.index);

  @override
  List<Object?> get props => [index];
}

/// User changed the post text/caption.
class CreateNewsPostTextChanged extends CreateNewsPostEvent {
  final String text;

  const CreateNewsPostTextChanged(this.text);

  @override
  List<Object?> get props => [text];
}

/// User tapped the submit button â€” triggers optimize → upload → create.
class CreateNewsPostSubmitted extends CreateNewsPostEvent {
  const CreateNewsPostSubmitted();
}
