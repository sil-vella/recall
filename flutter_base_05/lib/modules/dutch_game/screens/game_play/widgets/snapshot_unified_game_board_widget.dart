import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import 'circular_timer_widget.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = true;

/// Snapshot replica of UnifiedGameBoardWidget
/// Reads from passed oldState instead of StateManager
/// This shows the state as it was before the action update
class SnapshotUnifiedGameBoardWidget extends StatelessWidget {
  final Map<String, dynamic> oldState;
  
  const SnapshotUnifiedGameBoardWidget({
    Key? key,
    required this.oldState,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (LOGGING_SWITCH) {
      final logger = Logger();
      logger.info('📸 SnapshotWidget: Building snapshot with old state (${oldState.keys.length} keys)');
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Opponents Panel Section
            Expanded(
              child: _buildOpponentsPanel(),
            ),
            
            const SizedBox(height: 32),
            
            // Game Board Section
            _buildGameBoard(),
            
            const SizedBox(height: 16),
            
            // My Hand Section
            _buildMyHand(),
          ],
        );
      },
    );
  }
  
  // ========== Build Methods (replicas that read from oldState) ==========
  
  Widget _buildOpponentsPanel() {
    final currentGameId = oldState['currentGameId']?.toString() ?? '';
    final games = oldState['games'] as Map<String, dynamic>? ?? {};
    
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return const SizedBox.shrink();
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final allPlayers = gameState['players'] as List<dynamic>? ?? [];
    
    // Get current user ID
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Filter out current player
    final opponents = allPlayers.where((player) => 
      player is Map<String, dynamic> && player['id']?.toString() != currentUserId
    ).toList();
    
    if (opponents.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return ListView.builder(
      shrinkWrap: true,
      itemCount: opponents.length,
      itemBuilder: (context, index) {
        final opponent = opponents[index] as Map<String, dynamic>;
        return _buildOpponentCard(opponent);
      },
    );
  }
  
  Widget _buildOpponentCard(Map<String, dynamic> opponent) {
    final opponentName = opponent['name']?.toString() ?? 'Unknown';
    final hand = opponent['hand'] as List<dynamic>? ?? [];
    final handCount = hand.length;
    final status = opponent['status']?.toString() ?? 'unknown';
    final score = opponent['score'] ?? 0;
    final points = opponent['points'] ?? 0;
    
    // Get current player from oldState
    final currentGameId = oldState['currentGameId']?.toString() ?? '';
    final games = oldState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    final isCurrentPlayer = currentPlayer?['id']?.toString() == opponent['id']?.toString();
    
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: AppPadding.smallPadding.top,
        horizontal: AppPadding.defaultPadding.left,
      ),
      padding: AppPadding.defaultPadding,
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackgroundColor,
        borderRadius: AppBorderRadius.mediumRadius,
        border: isCurrentPlayer
            ? Border.all(color: AppColors.accentColor, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                opponentName,
                style: AppTextStyles.headingSmall(),
              ),
              PlayerStatusChip(
                playerId: opponent['id']?.toString() ?? '',
                customStatus: status,
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Cards: $handCount | Score: $score | Points: $points',
            style: AppTextStyles.bodySmall(),
          ),
          SizedBox(height: 8),
          // Show hand cards (face down)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(handCount, (index) {
              final cardData = index < hand.length ? hand[index] as Map<String, dynamic>? : null;
              return SizedBox(
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: CardWidget(
                  card: cardData != null 
                      ? CardModel.fromMap(cardData)
                      : CardModel(
                          cardId: 'snapshot_${opponent['id']}_card_$index',
                          rank: '?',
                          suit: '?',
                          points: 0,
                        ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forOpponent(),
                  showBack: true,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGameBoard() {
    final currentGameId = oldState['currentGameId']?.toString() ?? '';
    final games = oldState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final matchPot = gameState['match_pot'] as int? ?? 0;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDrawPile(drawPile),
          _buildMatchPot(matchPot),
          _buildDiscardPile(discardPile),
        ],
      ),
    );
  }
  
  Widget _buildDrawPile(List<dynamic> drawPile) {
    final drawPileCount = drawPile.length;
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    if (drawPileCount == 0) {
      return SizedBox(width: cardDimensions.width, height: cardDimensions.height);
    }
    
    // Show top 5 cards (or all if less than 5) with opacity 1.0 for tracking
    final cardsToShow = drawPile.length > 5 ? drawPile.sublist(drawPile.length - 5) : drawPile;
    
    return Stack(
      clipBehavior: Clip.none,
      children: cardsToShow.asMap().entries.map((entry) {
        final index = entry.key;
        final card = entry.value as Map<String, dynamic>;
        return Positioned(
          left: index * 2.0,
          top: index * 2.0,
          child: Opacity(
            opacity: 1.0, // Full opacity for top cards to ensure tracking
            child: SizedBox(
              width: cardDimensions.width,
              height: cardDimensions.height,
              child: CardWidget(
                card: CardModel.fromMap(card),
                dimensions: cardDimensions,
                config: CardDisplayConfig.forDrawPile(),
                showBack: true,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildDiscardPile(List<dynamic> discardPile) {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    if (discardPile.isEmpty) {
      return SizedBox(width: cardDimensions.width, height: cardDimensions.height);
    }
    
    // Show top 5 cards (or all if less than 5) with opacity 1.0 for tracking
    final cardsToShow = discardPile.length > 5 
        ? discardPile.sublist(discardPile.length - 5) 
        : discardPile;
    
    return Stack(
      clipBehavior: Clip.none,
      children: cardsToShow.asMap().entries.map((entry) {
        final index = entry.key;
        final card = entry.value as Map<String, dynamic>;
        return Positioned(
          left: index * 2.0,
          top: index * 2.0,
          child: Opacity(
            opacity: 1.0, // Full opacity for top cards to ensure tracking
            child: SizedBox(
              width: cardDimensions.width,
              height: cardDimensions.height,
              child: CardWidget(
                card: CardModel.fromMap(card),
                dimensions: cardDimensions,
                config: CardDisplayConfig.forDiscardPile(),
                showBack: false,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildMatchPot(int matchPot) {
    return Container(
      padding: AppPadding.defaultPadding,
      margin: EdgeInsets.symmetric(horizontal: AppPadding.defaultPadding.left),
      decoration: BoxDecoration(
        color: AppColors.accentColor.withOpacity(0.1),
        borderRadius: AppBorderRadius.mediumRadius,
        border: Border.all(color: AppColors.accentColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Match Pot',
            style: AppTextStyles.bodyMedium().copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$matchPot',
            style: AppTextStyles.headingMedium(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMyHand() {
    final myHand = oldState['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    final selectedIndex = myHand['selectedIndex'] ?? -1;
    final playerStatus = _getCurrentUserStatus();
    
    final currentGameId = oldState['currentGameId']?.toString() ?? '';
    final games = oldState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get timer config
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => 
      MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)
    ) ?? <String, int>{};
    
    int? turnTimeLimit;
    if (playerStatus != null && playerStatus.isNotEmpty) {
      switch (playerStatus) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 30;
          break;
        case 'drawing_card':
          turnTimeLimit = timerConfig['drawing_card'] ?? 30;
          break;
        case 'playing_card':
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        default:
          turnTimeLimit = timerConfig['default'] ?? 30;
      }
    }
    
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    return Container(
      padding: AppPadding.defaultPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status chip and timer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (playerStatus != null && playerStatus != 'unknown')
                PlayerStatusChip(
                  playerId: currentUserId,
                  customStatus: playerStatus,
                ),
              if (turnTimeLimit != null && playerStatus != null && playerStatus != 'waiting') ...[
                const SizedBox(width: 6),
                CircularTimerWidget(
                  durationSeconds: turnTimeLimit,
                  size: 28.0,
                  color: AppColors.accentColor,
                  backgroundColor: AppColors.surfaceVariant,
                ),
              ],
            ],
          ),
          SizedBox(height: 8),
          // Cards
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: cards.asMap().entries.map((entry) {
              final index = entry.key;
              final card = entry.value;
              final isSelected = index == selectedIndex;
              
              final cardModel = card is Map<String, dynamic> 
                  ? CardModel.fromMap(card)
                  : CardModel(
                      cardId: 'snapshot_myhand_card_$index',
                      rank: '?',
                      suit: '?',
                      points: 0,
                    );
              
              return Container(
                decoration: isSelected
                    ? BoxDecoration(
                        border: Border.all(
                          color: AppColors.accentColor,
                          width: 3,
                        ),
                        borderRadius: AppBorderRadius.smallRadius,
                      )
                    : null,
                padding: isSelected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                child: CardWidget(
                  card: cardModel,
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forMyHand(),
                  showBack: false,
                  isSelected: isSelected,
                  // No onTap or onLongPress - snapshot is read-only
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  String? _getCurrentUserStatus() {
    final currentGameId = oldState['currentGameId']?.toString() ?? '';
    final games = oldState['games'] as Map<String, dynamic>? ?? {};
    
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return null;
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    if (currentUserId.isEmpty) {
      return null;
    }
    
    for (final player in players) {
      if (player is Map<String, dynamic> && player['id']?.toString() == currentUserId) {
        return player['status']?.toString();
      }
    }
    return null;
  }
}
