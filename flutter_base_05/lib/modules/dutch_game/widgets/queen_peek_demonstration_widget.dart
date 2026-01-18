import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../utils/card_dimensions.dart';
import 'card_widget.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../tools/logging/logger.dart';

/// Demonstration widget for queen peek phase
/// 
/// Shows two examples:
/// 1. Peeking at a card in your own hand
/// 2. Peeking at a card from an opponent
/// Uses the same CardWidget and styling as the actual game widgets for consistency.
class QueenPeekDemonstrationWidget extends StatefulWidget {
  const QueenPeekDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<QueenPeekDemonstrationWidget> createState() => _QueenPeekDemonstrationWidgetState();
}

class _QueenPeekDemonstrationWidgetState extends State<QueenPeekDemonstrationWidget>
    with TickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  int _currentExample = 0; // 0 = my hand example, 1 = opponent example
  bool _cardRevealed = false;
  late AnimationController _animationController;
  late Animation<double> _revealAnimation;
  
  // GlobalKeys to track positions
  final GlobalKey _myHandCardKey = GlobalKey(debugLabel: 'demo_my_hand_card');
  final GlobalKey _opponentCardKey = GlobalKey(debugLabel: 'demo_opponent_card');
  
  /// My hand cards - mix of face up and face down
  List<Map<String, dynamic>> get _myHandCards => [
    // Card 0: Face up (Ace of Spades)
    {
      'cardId': 'demo-my-hand-0',
      'rank': 'ace',
      'suit': 'spades',
      'points': 1,
    },
    // Card 1: Face down (will be revealed in example 1)
    {
      'cardId': 'demo-my-hand-1',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 2: Face down
    {
      'cardId': 'demo-my-hand-2',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 3: Face down
    {
      'cardId': 'demo-my-hand-3',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
  ];
  
  /// The card to be revealed in my hand (example 1)
  Map<String, dynamic> get _myHandRevealedCard => {
    'cardId': 'demo-my-hand-1',
    'rank': '9',
    'suit': 'diamonds',
    'points': 9,
  };
  
  /// Opponent data for demonstration
  List<Map<String, dynamic>> get _opponents => [
    {
      'id': 'opponent-1',
      'name': 'Player 1',
      'hand': [
        {'cardId': 'opp1-card-0', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp1-card-1', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp1-card-2', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp1-card-3', 'rank': '?', 'suit': '?', 'points': 0},
      ],
    },
    {
      'id': 'opponent-2',
      'name': 'Player 2',
      'hand': [
        {'cardId': 'opp2-card-0', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp2-card-1', 'rank': '?', 'suit': '?', 'points': 0}, // This one will be revealed
        {'cardId': 'opp2-card-2', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp2-card-3', 'rank': '?', 'suit': '?', 'points': 0},
      ],
    },
    {
      'id': 'opponent-3',
      'name': 'Player 3',
      'hand': [
        {'cardId': 'opp3-card-0', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp3-card-1', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp3-card-2', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp3-card-3', 'rank': '?', 'suit': '?', 'points': 0},
      ],
    },
  ];
  
  /// The card to be revealed from opponent (example 2)
  Map<String, dynamic> get _opponentRevealedCard => {
    'cardId': 'opp2-card-1',
    'rank': 'king',
    'suit': 'spades',
    'points': 10,
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _revealAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _startAnimation();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _startAnimation() {
    // Start first example after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      _runExample(0);
    });
  }

  void _runExample(int exampleIndex) {
    if (!mounted) return;
    
    setState(() {
      _currentExample = exampleIndex;
      _cardRevealed = false;
    });
    
    // Wait for next frame to ensure positions are calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        
        // Start reveal animation
        _animationController.forward(from: 0.0).then((_) {
          if (mounted) {
            setState(() {
              _cardRevealed = true;
            });
            // After reveal, wait 2 seconds then switch to next example or repeat
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                _animationController.reset();
                if (exampleIndex == 0) {
                  // Switch to opponent example
                  _runExample(1);
                } else {
                  // Repeat from beginning
                  _runExample(0);
                }
              }
            });
          }
        });
      });
    });
  }

  /// Build my hand section
  Widget _buildMyHand() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.smallPadding.left;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (cardDimensions.width + spacing) * _myHandCards.length - spacing;
        final availableWidth = constraints.maxWidth;
        final needsScroll = contentWidth > availableWidth;
        
        final cardWidgets = List.generate(_myHandCards.length, (index) {
          final cardData = _myHandCards[index];
          final cardModel = CardModel.fromMap(cardData);
          final isFaceUp = cardModel.rank != '?' && cardModel.suit != '?';
          
          // Check if this is the card being revealed in example 1
          final isRevealingCard = _currentExample == 0 && 
                                 cardData['cardId'] == _myHandRevealedCard['cardId'];
          final cardKey = isRevealingCard ? _myHandCardKey : null;
          
          // Determine if card should show revealed data
          final shouldShowRevealed = isRevealingCard && _cardRevealed;
          final cardToShow = shouldShowRevealed 
              ? _myHandRevealedCard 
              : cardData;

          return Padding(
            padding: EdgeInsets.only(
              right: index < _myHandCards.length - 1 ? spacing : 0,
            ),
            child: AnimatedBuilder(
              animation: _revealAnimation,
              builder: (context, child) {
                // Fade in the revealed card
                final opacity = isRevealingCard && !_cardRevealed
                    ? 1.0 - _revealAnimation.value
                    : (shouldShowRevealed ? _revealAnimation.value : 1.0);
                
                // Show bright border when card is being revealed
                final shouldShowBorder = isRevealingCard && (_revealAnimation.value > 0 || _cardRevealed);
                
                return Opacity(
                  opacity: opacity,
                  child: Container(
                    decoration: shouldShowBorder
                        ? BoxDecoration(
                            border: Border.all(
                              color: AppColors.accentColor,
                              width: 3.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          )
                        : null,
                    child: CardWidget(
                      key: cardKey,
                      card: CardModel.fromMap(cardToShow),
                      dimensions: cardDimensions,
                      config: CardDisplayConfig.forMyHand(),
                      showBack: !isFaceUp && !shouldShowRevealed,
                    ),
                  ),
                );
              },
            ),
          );
        });
        
        return SizedBox(
          height: cardDimensions.height,
          child: needsScroll
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: cardWidgets,
                    ),
                  ),
                )
              : Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: cardWidgets,
                  ),
                ),
        );
      },
    );
  }

  /// Build opponent section
  Widget _buildOpponent(Map<String, dynamic> opponent, int opponentIndex) {
    final hand = opponent['hand'] as List<dynamic>;
    final playerName = opponent['name']?.toString() ?? 'Unknown';
    
    // Check if this opponent has the card being revealed in example 2
    final isRevealingOpponent = _currentExample == 1 && opponentIndex == 1; // Player 2
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: AppPadding.smallPadding.left,
        vertical: 0,
      ),
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: AppBorderRadius.mediumRadius,
        border: Border.all(
          color: AppColors.borderDefault,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: Cards - Expanded(flex: 2) matching opponents panel
          Expanded(
            flex: 2,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate card dimensions: 10% of the Expanded(flex: 2) width (matching opponents panel)
                final containerWidth = constraints.maxWidth.isFinite 
                    ? constraints.maxWidth 
                    : MediaQuery.of(context).size.width * 0.5;
                final cardWidth = CardDimensions.clampCardWidth(containerWidth * 0.10); // 10% of Expanded(flex: 2) width, clamped to max
                final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO; // Maintain 5:7 ratio
                final cardDimensions = Size(cardWidth, cardHeight);
                final cardPadding = containerWidth * 0.02; // 2% of Expanded(flex: 2) width for spacing
                
                return SizedBox(
                  height: cardHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(hand.length, (index) {
                      final cardData = hand[index] as Map<String, dynamic>;
                      
                      // Check if this is the card being revealed
                      final isRevealingCard = isRevealingOpponent && 
                                             cardData['cardId'] == _opponentRevealedCard['cardId'];
                      final cardKey = isRevealingCard ? _opponentCardKey : null;
                      
                      // Determine if card should show revealed data
                      final shouldShowRevealed = isRevealingCard && _cardRevealed;
                      final cardToShow = shouldShowRevealed 
                          ? _opponentRevealedCard 
                          : cardData;

                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < hand.length - 1 ? cardPadding : 0,
                        ),
                        child: AnimatedBuilder(
                          animation: _revealAnimation,
                          builder: (context, child) {
                            // Fade in the revealed card
                            final opacity = isRevealingCard && !_cardRevealed
                                ? 1.0 - _revealAnimation.value
                                : (shouldShowRevealed ? _revealAnimation.value : 1.0);
                            
                            // Show bright border when card is being revealed
                            final shouldShowBorder = isRevealingCard && (_revealAnimation.value > 0 || _cardRevealed);
                            
                            return Opacity(
                              opacity: opacity,
                              child: Container(
                                decoration: shouldShowBorder
                                    ? BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.accentColor,
                                          width: 3.0,
                                        ),
                                        borderRadius: BorderRadius.circular(8.0),
                                      )
                                    : null,
                                child: CardWidget(
                                  key: cardKey,
                                  card: CardModel.fromMap(cardToShow),
                                  dimensions: cardDimensions,
                                  config: CardDisplayConfig.forOpponent(),
                                  showBack: !shouldShowRevealed,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
          // Right side: Player name
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                playerName,
                style: AppTextStyles.label().copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Example label
        Container(
          padding: AppPadding.smallPadding,
          margin: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
          decoration: BoxDecoration(
            color: AppColors.accentColor.withOpacity(0.1),
            borderRadius: AppBorderRadius.smallRadius,
          ),
          child: Text(
            _currentExample == 0 
                ? 'Example 1: Peek at your own card'
                : 'Example 2: Peek at opponent\'s card',
            style: AppTextStyles.bodyMedium().copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.accentColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        // Opponents (always visible) - moved to top
        ..._opponents.asMap().entries.map((entry) {
          return _buildOpponent(entry.value, entry.key);
        }),
        SizedBox(height: AppPadding.defaultPadding.top),
        // My Hand (always visible) - moved to bottom
        _buildMyHand(),
      ],
    );
  }
}
