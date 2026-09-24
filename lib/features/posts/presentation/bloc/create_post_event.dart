part of 'create_post_bloc.dart';

/// Base class for create post events.
abstract class CreatePostEvent extends Equatable {
  const CreatePostEvent();

  @override
  List<Object?> get props => [];
}

/// User picked media files (images/videos) to add.
class CreatePostMediaAdded extends CreatePostEvent {
  final List<File> files;

  const CreatePostMediaAdded(this.files);

  @override
  List<Object?> get props => [files];
}

/// User removed a media item by index.
class CreatePostMediaRemoved extends CreatePostEvent {
  final int index;

  const CreatePostMediaRemoved(this.index);

  @override
  List<Object?> get props => [index];
}

/// User changed the post text/caption.
class CreatePostTextChanged extends CreatePostEvent {
  final String text;

  const CreatePostTextChanged(this.text);

  @override
  List<Object?> get props => [text];
}

/// User changed the visibility setting.
class CreatePostVisibilityChanged extends CreatePostEvent {
  final PostVisibility visibility;

  const CreatePostVisibilityChanged(this.visibility);

  @override
  List<Object?> get props => [visibility];
}

/// User submitted the post for creation.
class CreatePostSubmitted extends CreatePostEvent {
  const CreatePostSubmitted();
}
