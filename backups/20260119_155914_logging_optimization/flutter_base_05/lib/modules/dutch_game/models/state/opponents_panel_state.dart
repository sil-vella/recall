import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import 'player_data.dart';

/// Immutable state for OpponentsPanel widget
@immutable
class OpponentsPanelState extends ImmutableState with EquatableMixin {
  final List<PlayerData> opponents;
  final String currentPlayerStatus;
  final PlayerData? currentPlayer;
  
  const OpponentsPanelState({
    required this.opponents,
    required this.currentPlayerStatus,
    this.currentPlayer,
  });
  
  @override
  OpponentsPanelState copyWith({
    List<PlayerData>? opponents,
    String? currentPlayerStatus,
    PlayerData? currentPlayer,
  }) {
    return OpponentsPanelState(
      opponents: opponents ?? this.opponents,
      currentPlayerStatus: currentPlayerStatus ?? this.currentPlayerStatus,
      currentPlayer: currentPlayer ?? this.currentPlayer,
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'opponents': opponents.map((p) => p.toJson()).toList(),
      'currentPlayerStatus': currentPlayerStatus,
      if (currentPlayer != null) 'currentPlayer': currentPlayer!.toJson(),
    };
  }
  
  factory OpponentsPanelState.fromJson(Map<String, dynamic> json) {
    final opponentsRaw = json['opponents'] as List<dynamic>? ?? [];
    final opponents = opponentsRaw.map((p) => PlayerData.fromJson(p as Map<String, dynamic>)).toList();
    
    final currentPlayerJson = json['currentPlayer'] as Map<String, dynamic>?;
    final currentPlayer = currentPlayerJson != null ? PlayerData.fromJson(currentPlayerJson) : null;
    
    return OpponentsPanelState(
      opponents: opponents,
      currentPlayerStatus: json['currentPlayerStatus'] as String? ?? 'waiting',
      currentPlayer: currentPlayer,
    );
  }
  
  @override
  List<Object?> get props => [opponents, currentPlayerStatus, currentPlayer];
  
  @override
  String toString() => 'OpponentsPanelState(${opponents.length} opponents)';
}

