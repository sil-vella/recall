import 'package:equatable/equatable.dart';

abstract class GameEvent extends Equatable {
  const GameEvent();

  @override
  List<Object?> get props => [];
}

class InitializeGameEvent extends GameEvent {
  const InitializeGameEvent();
}

class UpdateStatePart extends GameEvent {
  final String part;
  final Map<String, dynamic> updates;

  const UpdateStatePart(this.part, this.updates);

  @override
  List<Object?> get props => [part, updates];
}

class SetGameId extends GameEvent {
  final String id;

  const SetGameId(this.id);

  @override
  List<Object?> get props => [id];
}

class SetMessageAnimation extends GameEvent {
  final Map<String, dynamic> data;

  const SetMessageAnimation(this.data);

  @override
  List<Object?> get props => [data];
}
