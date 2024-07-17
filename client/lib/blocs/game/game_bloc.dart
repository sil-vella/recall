import 'package:flutter_bloc/flutter_bloc.dart';
import 'game_event.dart';
import 'game_state.dart';

class GameBloc extends Bloc<GameEvent, GameState> {
  GameBloc() : super(InitialGameState()) {
    on<InitializeGameEvent>((event, emit) {
      // Handle initialization logic here if needed
      emit(InitialGameState());
    });

    on<UpdateStatePart>((event, emit) {
      switch (event.part) {
        case 'preGameState':
          emit(state.copyWith(
              preGameState: {...state.preGameState, ...event.updates}));
          break;
        case 'preGameState.gameData':
          final updatedGameData = {
            ...state.preGameState['gameData'],
            ...event.updates,
          };
          emit(state.copyWith(preGameState: {
            ...state.preGameState,
            'gameData': updatedGameData,
          }));
          break;
        case 'preGameState.playerData':
          final updatedPlayerData = {
            ...state.preGameState['playerData'],
            ...event.updates,
          };
          emit(state.copyWith(preGameState: {
            ...state.preGameState,
            'playerData': updatedPlayerData,
          }));
          break;
        case 'activeGamePlayState':
          emit(state.copyWith(activeGamePlayState: {
            ...state.activeGamePlayState,
            ...event.updates
          }));
          break;
        case 'userSection':
          emit(state.copyWith(userSection: {...state.userSection, ...event.updates}));
          break;
        case 'callWindow':
          emit(state.copyWith(callWindow: {...state.callWindow, ...event.updates}));
          break;
        default:
          break;
      }
    });

    on<SetGameId>((event, emit) {
      emit(state.copyWith(gameId: event.id));
    });

    on<SetMessageAnimation>((event, emit) {
      emit(state.copyWith(messageAnimation: event.data));
    });
  }
}
