import 'package:flutter/material.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';
import 'card_animation_manager.dart';

const bool LOGGING_SWITCH = false; // Enabled for animation replica debugging

/// Replica of UnifiedGameBoardWidget that reads from CardAnimationManager local state
/// Used for displaying animations while original widget updates with new computed state
/// This widget does NOT listen to StateManager - it reads from animation manager's local state
class UnifiedGameBoardWidgetReplica extends StatefulWidget {
  const UnifiedGameBoardWidgetReplica({Key? key}) : super(key: key);

  @override
  State<UnifiedGameBoardWidgetReplica> createState() => _UnifiedGameBoardWidgetReplicaState();
}

class _UnifiedGameBoardWidgetReplicaState extends State<UnifiedGameBoardWidgetReplica> with TickerProviderStateMixin {
  final Logger _logger = Logger();
  final CardAnimationManager _animationManager = CardAnimationManager.instance;
  
  // ========== Card Keys (for widget identification) ==========
  /// Map of cardId -> GlobalKey for all cards (reused across rebuilds)
  final Map<String, GlobalKey> _cardKeys = {};
  
  /// GlobalKey for myhand section
  final GlobalKey _myHandKey = GlobalKey(debugLabel: 'my_hand_section_replica');
  
  /// GlobalKey for game board section
  final GlobalKey _gameBoardKey = GlobalKey(debugLabel: 'game_board_section_replica');
  
  /// GlobalKey for draw pile section
  final GlobalKey _drawPileKey = GlobalKey(debugLabel: 'draw_pile_section_replica');
  
  /// GlobalKey for discard pile section
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'discard_pile_section_replica');

  @override
  void initState() {
    super.initState();
    if (LOGGING_SWITCH) {
        _logger.info('🎬 UnifiedGameBoardWidgetReplica: initState - registering section keys');
      
      }
    
    // Register section keys with animation manager
    _animationManager.registerSectionKey('myHand', _myHandKey);
    _animationManager.registerSectionKey('gameBoard', _gameBoardKey);
    _animationManager.registerSectionKey('drawPile', _drawPileKey);
    _animationManager.registerSectionKey('discardPile', _discardPileKey);
  }

  @override
  void dispose() {
    if (LOGGING_SWITCH) {
        _logger.info('🎬 UnifiedGameBoardWidgetReplica: dispose');
      
      }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read from animation manager's local state (not StateManager)
    final localState = _animationManager.localState;
    
    // Update cached bounds after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationManager.updateCachedBounds();
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 UnifiedGameBoardWidgetReplica: Updated cached bounds after build');
        
      }
    });
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same layout as original: Opponents spread evenly, Game Board above My Hand
        return Column(
          children: [
            // Opponents Panel Section - spread evenly vertically
            Expanded(
              child: _buildOpponentsPanel(localState),
            ),
            
            // Spacer above game board (doubled)
            const SizedBox(height: 32),
            
            // Game Board Section - Draw Pile, Match Pot, Discard Pile (just above My Hand)
            _buildGameBoard(localState),
            
            // Small spacer below game board
            const SizedBox(height: 16),
            
            // My Hand Section - at the bottom
            _buildMyHand(localState),
          ],
        );
      },
    );
  }
  
  // ========== Card Key Management ==========
  
  /// Get or create GlobalKey for a card (for widget identification)
  /// Also registers with animation manager
  GlobalKey _getOrCreateCardKey(String cardId, String keyType) {
    final key = '${keyType}_$cardId';
    if (!_cardKeys.containsKey(key)) {
      _cardKeys[key] = GlobalKey(debugLabel: key);
      // Register with animation manager
      _animationManager.registerCardKey(cardId, _cardKeys[key]!);
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 UnifiedGameBoardWidgetReplica: Registered card key for cardId: $cardId, keyType: $keyType');
        
      }
    }
    return _cardKeys[key]!;
  }

  // ========== Opponents Panel Methods ==========

  /// Build the opponents panel widget
  /// Reads from local state instead of StateManager
  Widget _buildOpponentsPanel(Map<String, dynamic> localState) {
    final opponentsPanel = localState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final currentTurnIndex = opponentsPanel['currentTurnIndex'] ?? -1;
    
    // For replica, we don't need cardsToPeek protection or interactive features
    // Just display the opponents as they appear in local state
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opponents.isEmpty)
          _buildEmptyOpponents()
        else
          // Spread opponents evenly vertically using Expanded
          Expanded(
            child: _buildOpponentsGrid(opponents, currentTurnIndex),
          ),
      ],
    );
  }

  Widget _buildEmptyOpponents() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: 24,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'No other players',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponentsGrid(List<dynamic> opponents, int currentTurnIndex) {
    // Simplified version - no nested ListenableBuilder, no timer config
    // Just display opponents with their cards
    
    // Order opponents: opp1 to column 1 (left), opp2 to middle column
    List<dynamic> reorderedOpponents = [];
    if (opponents.length >= 2) {
      reorderedOpponents = [
        opponents[0], // opp1 goes to column 1 (left)
        opponents[1], // opp2 goes to middle column
        if (opponents.length > 2) ...opponents.sublist(2), // opp3+ goes to right column
      ];
    } else {
      reorderedOpponents = opponents; // If less than 2 opponents, keep original order
    }
    
    // Create a map to find original index from player ID for currentTurnIndex calculation
    final originalIndexMap = <String, int>{};
    for (int i = 0; i < opponents.length; i++) {
      final player = opponents[i] as Map<String, dynamic>;
      final playerId = player['id']?.toString() ?? '';
      if (playerId.isNotEmpty) {
        originalIndexMap[playerId] = i;
      }
    }

    // Build list of opponent widgets with equal width columns
    final opponentWidgets = <Widget>[];
    final entries = reorderedOpponents.asMap().entries.toList();
    
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final displayIndex = entry.key; // Position in UI (0=left, 1=middle, 2=right)
      final player = entry.value as Map<String, dynamic>;
      final playerId = player['id']?.toString() ?? '';
      // Use original index from opponents list for turn calculation
      final originalIndex = originalIndexMap[playerId] ?? displayIndex;
      final isCurrentTurn = originalIndex == currentTurnIndex;
      
      // Register opponent section key
      final opponentSectionKey = GlobalKey(debugLabel: 'opponent_${playerId}_replica');
      _animationManager.registerSectionKey('opponent_$playerId', opponentSectionKey);
      
      // Add opponent widget wrapped in Expanded for equal width
      opponentWidgets.add(
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppPadding.mediumPadding.left),
            child: _buildOpponentCard(
              player, 
              isCurrentTurn,
              opponentSectionKey,
            ),
          ),
        ),
      );
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch, // Expand columns to fill available height
      children: opponentWidgets,
    );
  }

  Widget _buildOpponentCard(Map<String, dynamic> player, bool isCurrentTurn, GlobalKey sectionKey) {
    // Get player name - prefer full_name, fallback to name, then username, then default
    final fullName = player['full_name']?.toString();
    final playerNameRaw = player['name']?.toString();
    final username = player['username']?.toString();
    final playerName = (fullName != null && fullName.isNotEmpty) 
        ? fullName 
        : (playerNameRaw != null && playerNameRaw.isNotEmpty) 
            ? playerNameRaw 
            : (username != null && username.isNotEmpty) 
                ? username 
                : 'Unknown Player';
    final hand = player['hand'] as List<dynamic>? ?? [];
    final hasCalledDutch = player['hasCalledDutch'] ?? false;
    final playerStatus = player['status']?.toString() ?? 'unknown';
    final playerId = player['id']?.toString() ?? '';
    
    // Get profile picture
    final profilePictureUrl = player['profile_picture']?.toString();
    
    return Container(
      key: sectionKey,
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrentTurn ? AppColors.primaryColor : AppColors.borderDefault,
          width: isCurrentTurn ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profile picture and name
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPlayerProfilePicture(playerId, profilePictureUrl: profilePictureUrl),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  playerName,
                  style: AppTextStyles.bodyMedium().copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Status chip - use PlayerStatusChip with customStatus
          PlayerStatusChip(
            playerId: playerId, // Required but we'll override with customStatus
            customStatus: playerStatus,
            size: PlayerStatusChipSize.small,
          ),
          const SizedBox(height: 8),
          
          // Hand cards count
          Text(
            '${hand.length} cards',
            style: AppTextStyles.bodySmall().copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          
          // Dutch indicator
          if (hasCalledDutch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warningColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'DUTCH',
                  style: AppTextStyles.bodySmall().copyWith(
                    color: AppColors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build circular profile picture widget (simplified version)
  Widget _buildPlayerProfilePicture(String playerId, {String? profilePictureUrl}) {
    const double profilePictureSize = 28.0;
    
    // If we have a profile picture URL, show it
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: profilePictureSize,
        height: profilePictureSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceVariant,
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            width: profilePictureSize,
            height: profilePictureSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.person,
                size: profilePictureSize * 0.6,
                color: AppColors.textSecondary,
              );
            },
          ),
        ),
      );
    }
    
    // Fallback to default icon
    return Container(
      width: profilePictureSize,
      height: profilePictureSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(
          color: AppColors.borderDefault,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.person,
        size: profilePictureSize * 0.6,
        color: AppColors.textSecondary,
      ),
    );
  }

  // ========== Game Board Methods ==========

  Widget _buildGameBoard(Map<String, dynamic> localState) {
    return Container(
      key: _gameBoardKey,
      padding: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Get the actual width of the gameboard row
          final gameboardRowWidth = constraints.maxWidth;
          
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDrawPile(localState),
              _buildMatchPot(localState, gameboardRowWidth), // Match pot in the middle
              _buildDiscardPile(localState),
            ],
          );
        },
      ),
    );
  }

  // ========== Draw Pile Methods ==========

  Widget _buildDrawPile(Map<String, dynamic> localState) {
    final centerBoard = localState['centerBoard'] as Map<String, dynamic>? ?? {};
    final drawPileCount = centerBoard['drawPileCount'] as int? ?? 0;
    
    // For replica, we need to get draw pile from local state
    // Since local state only has drawPileCount, we'll render based on that
    // The actual cards will be in the original widget's state
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              
              Widget drawPileContent;
              
              if (drawPileCount == 0) {
                // Empty draw pile - render placeholder
                final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
                drawPileContent = CardWidget(
                  key: emptyKey,
                  card: CardModel(
                    cardId: 'draw_pile_empty',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDrawPile(),
                  showBack: true,
                  onTap: null, // No interaction in replica
                );
              } else {
                // Render draw pile with stacking effect
                // For replica, we'll render a placeholder card representing the top card
                // The actual card data will come from the original widget's state during animation
                final topCardKey = _getOrCreateCardKey('draw_pile_top', 'draw_pile');
                drawPileContent = SizedBox(
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Background cards for stacking effect
                      for (int i = 0; i < 2; i++)
                        Positioned.fill(
                          child: Transform.rotate(
                            angle: -(i + 1) * 2.0 * 3.14159 / 180, // 2° and 4° anticlockwise
                            child: Transform.translate(
                              offset: Offset((i + 1) * 1.5, (i + 1) * 1.5),
                              child: Opacity(
                                opacity: 0.6 - (i * 0.2),
                                child: CardWidget(
                                  card: CardModel(
                                    cardId: 'draw_pile_background_$i',
                                    rank: '?',
                                    suit: '?',
                                    points: 0,
                                  ),
                                  dimensions: cardDimensions,
                                  config: CardDisplayConfig.forDrawPile(),
                                  showBack: true,
                                  onTap: null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Top card
                      Positioned.fill(
                        child: CardWidget(
                          key: topCardKey,
                          card: CardModel(
                            cardId: 'draw_pile_top',
                            rank: '?',
                            suit: '?',
                            points: 0,
                          ),
                          dimensions: cardDimensions,
                          config: CardDisplayConfig.forDrawPile(),
                          showBack: true,
                          onTap: null, // No interaction in replica
                        ),
                      ),
                    ],
                  ),
                );
              }
              
              return drawPileContent;
            },
          ),
        ],
      ),
    );
  }

  // ========== Match Pot Methods ==========

  Widget _buildMatchPot(Map<String, dynamic> localState, double gameboardRowWidth) {
    final centerBoard = localState['centerBoard'] as Map<String, dynamic>? ?? {};
    final matchPot = centerBoard['matchPot'] as int? ?? 0;
    
    // For replica, we'll show match pot if it exists
    // Simplified version - no practice game check needed
    
    final shouldShowPot = matchPot > 0;
    
    // Calculate width: 20% of gameboard row width
    final calculatedWidth = gameboardRowWidth * 0.2;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Win',
            style: AppTextStyles.headingSmall().copyWith(
              color: shouldShowPot 
                  ? AppColors.primaryColor
                  : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/coins.png',
                width: calculatedWidth,
                fit: BoxFit.contain,
              ),
              Text(
                shouldShowPot ? matchPot.toString() : '—',
                style: AppTextStyles.headingLarge().copyWith(
                  color: AppColors.black,
                  shadows: [
                    Shadow(
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== Discard Pile Methods ==========

  Widget _buildDiscardPile(Map<String, dynamic> localState) {
    final centerBoard = localState['centerBoard'] as Map<String, dynamic>? ?? {};
    final topDiscard = centerBoard['topDiscard'] as Map<String, dynamic>?;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              
              if (topDiscard == null) {
                // Empty discard pile
                final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
                return CardWidget(
                  key: emptyKey,
                  card: CardModel(
                    cardId: 'discard_pile_empty',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDiscardPile(),
                  showBack: true,
                  onTap: null, // No interaction in replica
                );
              }
              
              // Render discard pile with stacking effect
              final cardId = topDiscard['cardId']?.toString() ?? 'discard_pile_top';
              final topCardKey = _getOrCreateCardKey(cardId, 'discard_pile');
              
              return SizedBox(
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Background cards for stacking effect
                    for (int i = 0; i < 2; i++)
                      Positioned.fill(
                        child: Transform.rotate(
                          angle: (i + 1) * 2.0 * 3.14159 / 180, // 2° and 4° clockwise
                          child: Transform.translate(
                            offset: Offset(-(i + 1) * 1.5, -(i + 1) * 1.5), // Negative X for discard pile
                            child: Opacity(
                              opacity: 0.6 - (i * 0.2),
                              child: CardWidget(
                                card: CardModel.fromMap(topDiscard),
                                dimensions: cardDimensions,
                                config: CardDisplayConfig.forDiscardPile(),
                                onTap: null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Top card
                    Positioned.fill(
                      child: CardWidget(
                        key: topCardKey,
                        card: CardModel.fromMap(topDiscard),
                        dimensions: cardDimensions,
                        config: CardDisplayConfig.forDiscardPile(),
                        onTap: null, // No interaction in replica
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ========== My Hand Methods ==========

  Widget _buildMyHand(Map<String, dynamic> localState) {
    final myHand = localState['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    final selectedIndex = myHand['selectedIndex'] ?? -1;
    final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
    
    return Container(
      key: _myHandKey,
      padding: AppPadding.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status chip - use PlayerStatusChip with customStatus
          // For replica, we need to get current user ID for playerId parameter
          Builder(
            builder: (context) {
              // Get current user ID from state (we'll use a placeholder for replica)
              // In replica, we can use the playerId from local state if available
              final currentUserId = _getCurrentUserId();
              return PlayerStatusChip(
                playerId: currentUserId.isNotEmpty ? currentUserId : 'replica_user',
                customStatus: playerStatus,
                size: PlayerStatusChipSize.medium,
              );
            },
          ),
          const SizedBox(height: 16),
          
          // Cards grid
          if (cards.isEmpty)
            _buildMyHandEmptyHand()
          else
            _buildMyHandCardsGrid(cards, selectedIndex),
        ],
      ),
    );
  }

  Widget _buildMyHandEmptyHand() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'No cards in hand',
              style: AppTextStyles.bodyMedium().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandCardsGrid(List<dynamic> cards, int selectedIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
        
        // Ensure containerWidth is valid before calculations
        if (containerWidth <= 0 || !containerWidth.isFinite) {
          return const SizedBox.shrink();
        }
        
        // Calculate card dimensions as 12% of container width, clamped to max
        final cardWidth = CardDimensions.clampCardWidth(containerWidth * 0.12);
        final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
        final cardDimensions = Size(cardWidth, cardHeight);
        final cardPadding = containerWidth * 0.02;
        
        // Build all card widgets
        List<Widget> cardWidgets = [];
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          
          // Handle null cards (blank slots from same-rank plays)
          if (card == null) {
            cardWidgets.add(
              Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: _buildMyHandBlankCardSlot(cardDimensions),
              ),
            );
            continue;
          }
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          
          final isSelected = index == selectedIndex;
          final cardKey = _getOrCreateCardKey(cardId, 'my_hand');
          
          final cardWidget = _buildMyHandCardWidget(
            cardMap,
            isSelected,
            cardKey,
            cardDimensions,
          );
          
          cardWidgets.add(
            Padding(
              padding: EdgeInsets.only(right: cardPadding),
              child: cardWidget,
            ),
          );
        }
        
        // Use Wrap widget to allow cards to wrap to next line
        return Wrap(
          spacing: 0, // Spacing is handled by card padding
          runSpacing: cardPadding, // Vertical spacing between wrapped rows
          alignment: WrapAlignment.start, // Align cards to the left
          children: cardWidgets,
        );
      },
    );
  }

  Widget _buildMyHandBlankCardSlot(Size cardDimensions) {
    return SizedBox(
      width: cardDimensions.width,
      height: cardDimensions.height,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.borderDefault,
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
            ),
    );
  }

  Widget _buildMyHandCardWidget(
    Map<String, dynamic> card,
    bool isSelected,
    GlobalKey cardKey,
    Size cardDimensions,
  ) {
    final cardModel = CardModel.fromMap(card);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    final cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forMyHand(),
      onTap: null, // No interaction in replica
    );
    
    // Apply selection highlight if selected
    if (isSelected) {
      return Container(
        width: cardDimensions.width,
        height: cardDimensions.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFBC02D).withOpacity(0.6),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: cardWidget,
      );
    }
    
    return cardWidget;
  }

  /// Get current user ID (helper method for status chip)
  String _getCurrentUserId() {
    // For replica, we use a placeholder - the customStatus parameter will override the status anyway
    // PlayerStatusChip requires playerId but we'll use customStatus to display the correct status
    return 'replica_user';
  }
}
