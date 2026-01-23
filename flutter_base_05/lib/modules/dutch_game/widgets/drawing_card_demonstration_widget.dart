import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../utils/card_dimensions.dart';
import 'card_widget.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../tools/logging/logger.dart';

/// Demonstration widget for drawing card phase
/// 
/// Shows a game board with draw pile and discard pile, plus a hand
/// with one face-up card (Ace of Spades, matching initial peek demo).
/// Animates drawing a card from the draw pile to the hand after 2 seconds.
/// Uses the same CardWidget and styling as the actual game widgets for consistency.
class DrawingCardDemonstrationWidget extends StatefulWidget {
  const DrawingCardDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<DrawingCardDemonstrationWidget> createState() => _DrawingCardDemonstrationWidgetState();
}

class _DrawingCardDemonstrationWidgetState extends State<DrawingCardDemonstrationWidget>
    with TickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  bool _animationStarted = false;
  bool _animationComplete = false;
  bool _cardRevealed = false;
  late AnimationController _animationController;
  late Animation<Offset> _cardAnimation;
  
  // GlobalKeys to track positions
  final GlobalKey _drawPileKey = GlobalKey(debugLabel: 'demo_draw_pile');
  final GlobalKey _lastHandCardKey = GlobalKey(debugLabel: 'demo_hand_last_card');
  
  /// The drawn card data (revealed after animation)
  Map<String, dynamic> get _drawnCard => {
    'cardId': 'demo-drawn-0',
    'rank': '3',
    'suit': 'clubs',
    'points': 3,
  };

  /// Predefined card data for demonstration
  /// Top discard card (face up)
  Map<String, dynamic> get _topDiscardCard => {
    'cardId': 'demo-discard-0',
    'rank': '5',
    'suit': 'diamonds',
    'points': 5,
  };

  /// Hand cards - one face up (Ace of Spades, matching initial peek demo), others face down
  List<Map<String, dynamic>> get _handCards => [
    // Card 0: Ace of Spades (face up - same as initial peek demo card 0)
    {
      'cardId': 'demo-hand-0',
      'rank': 'ace',
      'suit': 'spades',
      'points': 1,
    },
    // Card 1: Face down
    {
      'cardId': 'demo-hand-1',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 2: Face down
    {
      'cardId': 'demo-hand-2',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 3: Face down
    {
      'cardId': 'demo-hand-3',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // Animation will be set up with actual positions after first frame
    _cardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
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
    // Start animation after 2 seconds, then repeat every 4 seconds
    Future.delayed(const Duration(seconds: 2), () {
      _runAnimationCycle();
    });
  }

  void _runAnimationCycle() {
    if (!mounted) return;
    
    // Wait for next frame to ensure positions are calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add a small delay to ensure layout is fully settled
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        
        // Get actual positions from GlobalKeys
        final drawPileRenderBox = _drawPileKey.currentContext?.findRenderObject() as RenderBox?;
        final lastHandCardRenderBox = _lastHandCardKey.currentContext?.findRenderObject() as RenderBox?;
        
        if (drawPileRenderBox != null && lastHandCardRenderBox != null) {
          // Get positions relative to the Stack
          final drawPilePosition = drawPileRenderBox.localToGlobal(Offset.zero);
          final handCardPosition = lastHandCardRenderBox.localToGlobal(Offset.zero);
          
          // Get the Stack's position to calculate relative positions
          final stackContext = context.findRenderObject() as RenderBox?;
          if (stackContext != null) {
            final stackPosition = stackContext.localToGlobal(Offset.zero);
            
            // Calculate center positions relative to the Stack
            final startOffset = Offset(
              drawPilePosition.dx - stackPosition.dx + drawPileRenderBox.size.width / 2,
              drawPilePosition.dy - stackPosition.dy + drawPileRenderBox.size.height / 2,
            );
            
            // Calculate position for the next card slot (after the last card)
            // Use actual sizes from RenderBox for accuracy
            final cardDimensions = CardDimensions.getUnifiedDimensions();
            final spacing = AppPadding.smallPadding.left;
            
            // Get the hand Row's RenderBox to understand the layout
            final handRowContext = _lastHandCardKey.currentContext?.findAncestorRenderObjectOfType<RenderFlex>();
            
            if (handRowContext != null) {
              // Calculate where the new card will actually be positioned
              // The Row uses MainAxisAlignment.center, so we need to account for centering
              final currentCardsCount = _handCards.length;
              final totalCurrentWidth = (cardDimensions.width * currentCardsCount) + (spacing * (currentCardsCount - 1));
              // New card is added at the end, so add card width + spacing (spacing before the new card)
              final totalNewWidth = totalCurrentWidth + spacing + cardDimensions.width;
              
              // Get the Row's position and size
              final handRowPosition = handRowContext.localToGlobal(Offset.zero);
              final handRowSize = handRowContext.size;
              
              // Calculate the center of the Row (relative to Stack)
              final rowCenterX = handRowPosition.dx - stackPosition.dx + handRowSize.width / 2;
              
              // Calculate where the rightmost card (new card) will be after centering
              // The rightmost card's center = row center + (total width / 2) - (card width / 2)
              final newCardCenterX = rowCenterX + (totalNewWidth / 2) - (cardDimensions.width / 2);
              
              final endOffset = Offset(
                newCardCenterX,
                handCardPosition.dy - stackPosition.dy + lastHandCardRenderBox.size.height / 2,
              );
            
              // Update animation with actual positions
              _cardAnimation = Tween<Offset>(
                begin: startOffset,
                end: endOffset,
              ).animate(CurvedAnimation(
                parent: _animationController,
                curve: Curves.easeInOut,
              ));
              
              setState(() {
                _animationStarted = true;
                _animationComplete = false;
                _cardRevealed = false;
              });
              
              _animationController.forward(from: 0.0).then((_) {
                if (mounted) {
                  setState(() {
                    _animationComplete = true;
                  });
                  // Reveal card data after a short delay
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      setState(() {
                        _cardRevealed = true;
                      });
                      // Reset and repeat after 4 seconds total (including animation time)
                      Future.delayed(const Duration(milliseconds: 2900), () {
                        if (mounted) {
                          _runAnimationCycle();
                        }
                      });
                    }
                  });
                }
              });
            }
          }
        }
      });
    });
  }

  /// Build the game board section (draw pile and discard pile)
  Widget _buildGameBoard() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.defaultPadding.left;

    return Container(
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: AppBorderRadius.mediumRadius,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Draw Pile
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Draw',
                  style: AppTextStyles.headingSmall(),
                ),
                SizedBox(height: AppPadding.smallPadding.top),
                CardWidget(
                  key: _drawPileKey,
                  card: CardModel(
                    cardId: 'demo-draw-pile',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDrawPile(),
                  showBack: true, // Always show back for draw pile
                ),
              ],
            ),
          ),
          SizedBox(width: spacing),
          // Discard Pile (Last Played)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Last Played',
                  style: AppTextStyles.headingSmall(),
                ),
                SizedBox(height: AppPadding.smallPadding.top),
                CardWidget(
                  card: CardModel.fromMap(_topDiscardCard),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDiscardPile(),
                  showBack: false, // Face up
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the hand section
  Widget _buildHand() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.smallPadding.left;
    
    // Add drawn card to hand if animation is complete
    final cardsToShow = List<Map<String, dynamic>>.from(_handCards);
    if (_animationComplete) {
      cardsToShow.add(_drawnCard);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (cardDimensions.width + spacing) * cardsToShow.length - spacing;
        final availableWidth = constraints.maxWidth;
        final needsScroll = contentWidth > availableWidth;
        
        if (LOGGING_SWITCH) {
          _logger.debug('🎴 DrawDemo: _buildHand - cardsToShow.length: ${cardsToShow.length}, cardDimensions: ${cardDimensions.width}x${cardDimensions.height}, spacing: $spacing');
        }
        if (LOGGING_SWITCH) {
          _logger.debug('🎴 DrawDemo: _buildHand - contentWidth: $contentWidth, availableWidth: $availableWidth, needsScroll: $needsScroll');
        }
        
        final cardWidgets = List.generate(cardsToShow.length, (index) {
          final cardData = cardsToShow[index];
          final cardModel = CardModel.fromMap(cardData);
          final isDrawnCard = cardData['cardId'] == _drawnCard['cardId'];
          final isFaceUp = (cardModel.rank != '?' && cardModel.suit != '?') || 
                          (isDrawnCard && _cardRevealed);
          
          // Use key for the last card (where the drawn card will be placed)
          // The key is always on the last card in the current list
          final isLastCard = index == cardsToShow.length - 1;
          final cardKey = isLastCard ? _lastHandCardKey : null;
          
          final paddingRight = index < cardsToShow.length - 1 ? spacing : 0.0;
          if (LOGGING_SWITCH) {
            _logger.debug('🎴 DrawDemo: _buildHand - card[$index]: isDrawnCard=$isDrawnCard, isLastCard=$isLastCard, paddingRight=$paddingRight');
          }

          return Padding(
            padding: EdgeInsets.only(
              right: paddingRight,
            ),
            child: CardWidget(
              key: cardKey,
              card: isDrawnCard && _cardRevealed
                  ? CardModel.fromMap(_drawnCard)
                  : cardModel,
              dimensions: cardDimensions,
              config: CardDisplayConfig.forMyHand(),
              showBack: !isFaceUp, // Show back if card data is hidden
            ),
          );
        });
        
        if (LOGGING_SWITCH) {
          _logger.debug('🎴 DrawDemo: _buildHand - Returning SizedBox with height: ${cardDimensions.height}, needsScroll: $needsScroll');
        }
        
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

  @override
  Widget build(BuildContext context) {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Game Board (Draw Pile and Discard Pile)
            _buildGameBoard(),
            SizedBox(height: AppPadding.defaultPadding.top),
            // Hand
            _buildHand(),
          ],
        ),
        // Animated card (only during animation) - positioned using exact coordinates
        if (_animationStarted && !_animationComplete)
          AnimatedBuilder(
            animation: _cardAnimation,
            builder: (context, child) {
              return Positioned(
                left: _cardAnimation.value.dx - cardDimensions.width / 2,
                top: _cardAnimation.value.dy - cardDimensions.height / 2,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.accentColor,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: CardWidget(
                    card: CardModel.fromMap(_drawnCard),
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forMyHand(),
                    showBack: true, // Show back during animation
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
