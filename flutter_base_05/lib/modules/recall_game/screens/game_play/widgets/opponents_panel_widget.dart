import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Widget to display other players (opponents)
/// 
/// This widget subscribes to the opponentsPanel state slice and displays:
/// - List of all opponent players
/// - Small card-like elements showing number of cards in their hand
/// - Player names and status
/// - No card details (handled by backend for security)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class OpponentsPanelWidget extends StatelessWidget {
  static final Logger _log = Logger();
  
  const OpponentsPanelWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get opponentsPanel state slice
        final opponentsPanel = recallGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
        final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
        final currentTurnIndex = opponentsPanel['currentTurnIndex'] ?? -1;
        
        // Get current user ID to filter out self from opponents
        final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
        final currentUserId = loginState['userId']?.toString() ?? '';
        
        // Filter out current player from opponents list
        final otherPlayers = opponents.where((player) => 
          player['id']?.toString() != currentUserId
        ).toList();
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        
        _log.info('🎮 OpponentsPanelWidget: opponents=${otherPlayers.length}, currentTurnIndex=$currentTurnIndex, gamePhase=$gamePhase');
        
        return _buildOpponentsPanel(
          opponents: otherPlayers,
          currentTurnIndex: currentTurnIndex,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
        );
      },
    );
  }

  /// Build the opponents panel widget
  Widget _buildOpponentsPanel({
    required List<dynamic> opponents,
    required int currentTurnIndex,
    required String gamePhase,
    required bool isGameActive,
  }) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Icon(Icons.people, color: Colors.purple),
                const SizedBox(width: 8),
                const Text(
                  'Opponents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${opponents.length} players',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Opponents display
            if (opponents.isEmpty)
              _buildEmptyOpponents()
            else
              _buildOpponentsGrid(opponents, currentTurnIndex, isGameActive),
          ],
        ),
      ),
    );
  }

  /// Build empty opponents state
  Widget _buildEmptyOpponents() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: 24,
              color: Colors.grey,
            ),
            SizedBox(height: 4),
            Text(
              'No other players',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the opponents grid
  Widget _buildOpponentsGrid(List<dynamic> opponents, int currentTurnIndex, bool isGameActive) {
    return Column(
      children: opponents.asMap().entries.map((entry) {
        final index = entry.key;
        final player = entry.value as Map<String, dynamic>;
        final isCurrentTurn = index == currentTurnIndex;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildOpponentCard(player, isCurrentTurn, isGameActive),
        );
      }).toList(),
    );
  }

  /// Build individual opponent card
  Widget _buildOpponentCard(Map<String, dynamic> player, bool isCurrentTurn, bool isGameActive) {
    final playerName = player['name']?.toString() ?? 'Unknown Player';
    final handSize = player['hand']?.length ?? 0;
    final visibleCards = player['visibleCards'] as List<dynamic>? ?? [];
    final visibleCount = visibleCards.length;
    final totalCards = handSize + visibleCount;
    final status = player['status']?.toString() ?? 'waiting';
    final score = player['score'] ?? 0;
    final hasCalledRecall = player['hasCalledRecall'] ?? false;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentTurn ? Colors.yellow.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrentTurn ? Colors.yellow.shade400 : Colors.grey.shade300,
          width: isCurrentTurn ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Player info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      playerName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isCurrentTurn ? Colors.yellow.shade800 : Colors.black87,
                      ),
                    ),
                    if (isCurrentTurn) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.play_arrow,
                        size: 16,
                        color: Colors.yellow.shade700,
                      ),
                    ],
                    if (hasCalledRecall) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.flag,
                        size: 16,
                        color: Colors.red,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Score: $score | Status: ${_formatStatus(status)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Cards display
          Row(
            children: [
              // Hand cards (small card-like elements)
              if (handSize > 0) ...[
                _buildSmallCardStack(handSize, 'Hand'),
                const SizedBox(width: 8),
              ],
              
              // Visible cards (small card-like elements)
              if (visibleCount > 0) ...[
                _buildSmallCardStack(visibleCount, 'Visible'),
                const SizedBox(width: 8),
              ],
              
              // Total cards indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Text(
                  '$totalCards total',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build small card stack representation
  Widget _buildSmallCardStack(int cardCount, String label) {
    return Column(
      children: [
        // Small card stack
        Container(
          width: 30,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.grey.shade400, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              cardCount.toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// Format player status for display
  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'waiting':
        return 'Waiting';
      case 'ready':
        return 'Ready';
      case 'playing':
        return 'Playing';
      case 'finished':
        return 'Finished';
      case 'disconnected':
        return 'Disconnected';
      default:
        return status;
    }
  }
}
