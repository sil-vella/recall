import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../../../widgets/card_back_widget.dart';

/// Widget to display other players (opponents)
/// 
/// This widget subscribes to the opponentsPanel state slice and displays:
/// - List of all opponent players
/// - Small card-like elements showing number of cards in their hand
/// - Player names and status
/// - Clickable cards for special power interactions (queen_peek, jack_swap)
/// - No card details (handled by backend for security)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class OpponentsPanelWidget extends StatefulWidget {
  static final Logger _log = Logger();
  
  const OpponentsPanelWidget({Key? key}) : super(key: key);

  @override
  State<OpponentsPanelWidget> createState() => _OpponentsPanelWidgetState();
}

class _OpponentsPanelWidgetState extends State<OpponentsPanelWidget> {
  static final Logger _log = Logger();
  
  // Internal state to store clicked card information
  String? _clickedCardId;

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
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        _log.info('🎮 OpponentsPanelWidget: opponents=${otherPlayers.length}, currentTurnIndex=$currentTurnIndex, gamePhase=$gamePhase, playerStatus=$playerStatus');
        
        return _buildOpponentsPanel(
          opponents: otherPlayers,
          currentTurnIndex: currentTurnIndex,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          playerStatus: playerStatus,
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
    required String playerStatus,
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
              ],
            ),
            const SizedBox(height: 16),
            
            // Opponents display
            if (opponents.isEmpty)
              _buildEmptyOpponents()
            else
              _buildOpponentsGrid(opponents, currentTurnIndex, isGameActive, playerStatus),
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
  Widget _buildOpponentsGrid(List<dynamic> opponents, int currentTurnIndex, bool isGameActive, String playerStatus) {
    // Get current player information from state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayer = recallGameState['currentPlayer']?.toString() ?? '';
    final currentPlayerStatus = recallGameState['currentPlayerStatus']?.toString() ?? 'unknown';
    
    return Column(
      children: opponents.asMap().entries.map((entry) {
        final index = entry.key;
        final player = entry.value as Map<String, dynamic>;
        final playerId = player['id']?.toString() ?? '';
        final isCurrentTurn = index == currentTurnIndex;
        final isCurrentPlayer = playerId == currentPlayer;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildOpponentCard(player, isCurrentTurn, isGameActive, isCurrentPlayer, currentPlayerStatus),
        );
      }).toList(),
    );
  }

  /// Build individual opponent card
  Widget _buildOpponentCard(Map<String, dynamic> player, bool isCurrentTurn, bool isGameActive, bool isCurrentPlayer, String currentPlayerStatus) {
    final playerName = player['name']?.toString() ?? 'Unknown Player';
    final hand = player['hand'] as List<dynamic>? ?? [];
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player name, turn indicator, and status
          Row(
            children: [
              Expanded(
                child: Text(
                  playerName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isCurrentTurn ? Colors.yellow.shade800 : Colors.black87,
                  ),
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
          
          // Player status indicator (only show for current player)
          if (isCurrentPlayer && currentPlayerStatus != 'unknown') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                _buildStatusChip(currentPlayerStatus),
              ],
            ),
          ],
          const SizedBox(height: 8),
          
          // Cards display - horizontal layout like my hand
          if (hand.isNotEmpty)
            _buildCardsRow(hand)
          else
            _buildEmptyHand(),
        ],
      ),
    );
  }

  /// Build cards row - horizontal layout like my hand
  Widget _buildCardsRow(List<dynamic> cards) {
    return Container(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index] as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _buildCardWidget(card),
          );
        },
      ),
    );
  }

  /// Build individual card widget for opponents using the new CardWidget system
  Widget _buildCardWidget(Map<String, dynamic> card) {
    // Convert to CardModel
    final cardModel = CardModel.fromMap(card);
    
    // Check if this card is currently selected
    final cardId = card['cardId']?.toString();
    final isSelected = cardId != null && _clickedCardId == cardId;
    
    // Update the card model with selection state
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    return CardWidget(
      card: updatedCardModel,
      size: CardSize.small,
      isSelectable: true,
      isSelected: isSelected,
      onTap: () => _handleCardClick(card),
    );
  }

  /// Build empty hand state
  Widget _buildEmptyHand() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 20,
              color: Colors.grey,
            ),
            SizedBox(height: 4),
            Text(
              'No cards',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }



  /// Get the currently clicked card ID (for external access)
  String? getClickedCardId() {
    return _clickedCardId;
  }

  /// Clear the clicked card ID (for resetting state)
  void clearClickedCardId() {
    setState(() {
      _clickedCardId = null;
    });
  }

  /// Handle card click for special power interactions
  void _handleCardClick(Map<String, dynamic> card) {
    // Get current player status from state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
    
    _log.info('🎯 Card clicked: ${card['cardId']}, current player status: $currentPlayerStatus');
    
    // Check if current player can interact with cards (queen_peek or jack_swap status)
    if (currentPlayerStatus == 'queen_peek' || currentPlayerStatus == 'jack_swap') {
      final cardId = card['cardId']?.toString();
      if (cardId != null) {
        setState(() {
          _clickedCardId = cardId;
        });
        
        _log.info('✅ Card ID stored: $cardId (status: $currentPlayerStatus)');
        
        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentPlayerStatus == 'queen_peek' 
                ? 'Card selected for Queen peek: ${card['rank']} of ${card['suit']}'
                : 'Card selected for Jack swap: ${card['rank']} of ${card['suit']}'
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        _log.warning('⚠️ Card clicked but no cardId found: $card');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Card information incomplete'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Show invalid action feedback
      _log.info('❌ Invalid card click action: status=$currentPlayerStatus');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Build status chip for player status
  Widget _buildStatusChip(String status) {
    Color chipColor;
    String chipText;
    IconData chipIcon;

    switch (status) {
      case 'waiting':
        chipColor = Colors.grey;
        chipText = 'Waiting';
        chipIcon = Icons.schedule;
        break;
      case 'ready':
        chipColor = Colors.blue;
        chipText = 'Ready';
        chipIcon = Icons.check_circle;
        break;
      case 'drawing_card':
        chipColor = Colors.orange;
        chipText = 'Drawing';
        chipIcon = Icons.draw;
        break;
      case 'playing_card':
        chipColor = Colors.green;
        chipText = 'Playing';
        chipIcon = Icons.play_arrow;
        break;
      case 'same_rank_window':
        chipColor = Colors.purple;
        chipText = 'Same Rank';
        chipIcon = Icons.flash_on;
        break;
      case 'queen_peek':
        chipColor = Colors.pink;
        chipText = 'Queen Peek';
        chipIcon = Icons.visibility;
        break;
      case 'jack_swap':
        chipColor = Colors.indigo;
        chipText = 'Jack Swap';
        chipIcon = Icons.swap_horiz;
        break;
      case 'finished':
        chipColor = Colors.red;
        chipText = 'Finished';
        chipIcon = Icons.stop;
        break;
      default:
        chipColor = Colors.grey;
        chipText = 'Unknown';
        chipIcon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            chipIcon,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            chipText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

}
