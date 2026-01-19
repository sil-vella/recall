import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../utils/card_dimensions.dart';
import 'card_widget.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../tools/logging/logger.dart';

/// Demonstration widget for playing card phase
/// 
/// Shows a game board with draw pile and discard pile, plus a hand
/// with cards. Animates playing the 3rd card from the hand to the discard pile.
/// Uses the same CardWidget and styling as the actual game widgets for consistency.
class PlayingCardDemonstrationWidget extends StatefulWidget {
  const PlayingCardDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<PlayingCardDemonstrationWidget> createState() => _PlayingCardDemonstrationWidgetState();
}

class _PlayingCardDemonstrationWidgetState extends State<PlayingCardDemonstrationWidget>
    with TickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  // Animation phases: 0 = idle, 1 = play animation, 2 = drawn card animation, 3 = flip
  int _animationPhase = 0;
  bool _drawnCardFlipped = false;
  late AnimationController _animationController;
  late Animation<Offset> _playCardAnimation;
  late Animation<Offset> _drawnCardAnimation;
  
  // GlobalKeys to track positions
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'demo_discard_pile');
  final GlobalKey _thirdCardKey = GlobalKey(debugLabel: 'demo_hand_third_card');
  final GlobalKey _drawnCardKey = GlobalKey(debugLabel: 'demo_hand_drawn_card');
  
  /// The card being played (3rd card in hand)
  Map<String, dynamic> get _playedCard => {
    'cardId': 'demo-played-0',
    'rank': '7',
    'suit': 'hearts',
    'points': 7,
  };

  /// Predefined card data for demonstration
  /// Top discard card (face up) - will be replaced by played card
  Map<String, dynamic> get _topDiscardCard => {
    'cardId': 'demo-discard-0',
    'rank': '5',
    'suit': 'diamonds',
    'points': 5,
  };

  /// The drawn card data (from draw demo - 3 of Clubs)
  Map<String, dynamic> get _drawnCard => {
    'cardId': 'demo-drawn-0',
    'rank': '3',
    'suit': 'clubs',
    'points': 3,
  };

  /// Hand cards - one face up (Ace of Spades), others face down
  /// The 3rd card (index 2) will be played
  /// The drawn card (3 of Clubs) is at the end, initially face up
  List<Map<String, dynamic>> get _handCards => [
    // Card 0: Ace of Spades (face up)
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
    // Card 2: The card to be played (7 of Hearts) - starts face down, turns face up when animation starts
    {
      'cardId': 'demo-hand-2',
      'rank': '?', // Start face down
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
    // Card 4: Drawn card (3 of Clubs) - initially face up, will flip after moving
    {
      'cardId': 'demo-drawn-0',
      'rank': '3',
      'suit': 'clubs',
      'points': 3,
    },
  ];

  @override
  void initState() {
    super.initState();
    // Single animation controller for both animations (sequential)
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1600), // 800ms for each animation
      vsync: this,
    );
    
    // Animations will be set up with actual positions after first frame
    _playCardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut), // First half: play animation
    ));
    
    _drawnCardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut), // Second half: drawn card animation
    ));
    
    // Listen to animation controller to track phases
    _animationController.addListener(() {
      if (!mounted) return;
      final value = _animationController.value;
      if (value < 0.5) {
        // Play animation phase
        if (_animationPhase != 1) {
          setState(() {
            _animationPhase = 1;
          });
        }
      } else if (value < 1.0) {
        // Drawn card animation phase
        if (_animationPhase != 2) {
          setState(() {
            _animationPhase = 2;
          });
        }
      } else {
        // Animation complete - both animations done
        if (_animationPhase != 3) {
          setState(() {
            _animationPhase = 3;
          });
        }
      }
    });
    
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
    
    // Reset all states for new cycle
    setState(() {
      _animationPhase = 0;
      _drawnCardFlipped = false;
    });
    
    // Wait for next frame to ensure positions are calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add a small delay to ensure layout is fully settled
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        
        // Setup both animations with actual positions
        _setupAnimations();
      });
    });
  }

  void _setupAnimations() {
    if (!mounted) return;
    
    // Get actual positions from GlobalKeys
    final thirdCardRenderBox = _thirdCardKey.currentContext?.findRenderObject() as RenderBox?;
    final discardPileRenderBox = _discardPileKey.currentContext?.findRenderObject() as RenderBox?;
    final drawnCardRenderBox = _drawnCardKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (thirdCardRenderBox != null && discardPileRenderBox != null && drawnCardRenderBox != null) {
      // Get positions relative to the Stack
      final thirdCardPosition = thirdCardRenderBox.localToGlobal(Offset.zero);
      final discardPilePosition = discardPileRenderBox.localToGlobal(Offset.zero);
      final drawnCardPosition = drawnCardRenderBox.localToGlobal(Offset.zero);
      
      // Get the Stack's position to calculate relative positions
      final stackContext = context.findRenderObject() as RenderBox?;
      if (stackContext != null) {
        final stackPosition = stackContext.localToGlobal(Offset.zero);
        
        // Calculate play card animation positions
        final playStartOffset = Offset(
          thirdCardPosition.dx - stackPosition.dx + thirdCardRenderBox.size.width / 2,
          thirdCardPosition.dy - stackPosition.dy + thirdCardRenderBox.size.height / 2,
        );
        
        final playEndOffset = Offset(
          discardPilePosition.dx - stackPosition.dx + discardPileRenderBox.size.width / 2,
          discardPilePosition.dy - stackPosition.dy + discardPileRenderBox.size.height / 2,
        );
        
        // Calculate drawn card animation positions
        // Calculate where the 3rd card slot is (after removing the played card)
        final handRowContext = _drawnCardKey.currentContext?.findAncestorRenderObjectOfType<RenderFlex>();
        
        if (handRowContext != null) {
          final cardDimensions = CardDimensions.getUnifiedDimensions();
          final spacing = AppPadding.smallPadding.left;
          
          final handRowPosition = handRowContext.localToGlobal(Offset.zero);
          final handRowSize = handRowContext.size;
          final rowCenterX = handRowPosition.dx - stackPosition.dx + handRowSize.width / 2;
          
          // We have 5 cards total (including empty slot at index 2)
          final totalWidth = (cardDimensions.width * 5) + (spacing * 4);
          
          // The 3rd card slot (index 2) center position
          final thirdSlotCenterX = rowCenterX - (totalWidth / 2) + (cardDimensions.width * 2.5) + (spacing * 2);
          
          final drawnCardStartOffset = Offset(
            drawnCardPosition.dx - stackPosition.dx + drawnCardRenderBox.size.width / 2,
            drawnCardPosition.dy - stackPosition.dy + drawnCardRenderBox.size.height / 2,
          );
          
          final drawnCardEndOffset = Offset(
            thirdSlotCenterX,
            drawnCardPosition.dy - stackPosition.dy + drawnCardRenderBox.size.height / 2,
          );
          
          // Update animations with actual positions
          _playCardAnimation = Tween<Offset>(
            begin: playStartOffset,
            end: playEndOffset,
          ).animate(CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
          ));
          
          _drawnCardAnimation = Tween<Offset>(
            begin: drawnCardStartOffset,
            end: drawnCardEndOffset,
          ).animate(CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
          ));
          
          // Start the combined animation
          _animationController.forward(from: 0.0).then((_) {
            if (mounted) {
              // After both animations complete, wait 1 second, then flip the drawn card
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() {
                    _drawnCardFlipped = true;
                  });
                  // Reset and repeat after 4 seconds total
                  Future.delayed(const Duration(milliseconds: 1400), () {
                    if (mounted) {
                      _animationController.reset();
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CardWidget(
                      key: _discardPileKey,
                      // Show played card only after play animation completes (phase >= 2)
                      card: CardModel.fromMap(_animationPhase >= 2 ? _playedCard : _topDiscardCard),
                      dimensions: cardDimensions,
                      config: CardDisplayConfig.forDiscardPile(),
                      showBack: false, // Face up
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build empty slot widget (similar to my_hand_widget)
  Widget _buildEmptySlot() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    return SizedBox(
      width: cardDimensions.width,
      height: cardDimensions.height,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.borderDefault,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.space_bar,
                size: 24,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                'Empty',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the hand section
  Widget _buildHand() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.smallPadding.left;
    
    // Keep all 5 cards in the list - show empty slot at index 2 during animation
    // Move drawn card to 3rd position only after drawn card animation completes
    final cardsToShow = List<Map<String, dynamic>>.from(_handCards);
    
    // If drawn card animation has completed, move it to the 3rd position (where played card was)
    // Before phase 3, drawn card stays at the end (index 4)
    if (_animationPhase >= 3) {
      // Find the drawn card (should be at the end, index 4)
      final drawnCardIndex = cardsToShow.indexWhere((c) => c['cardId'] == _drawnCard['cardId']);
      if (drawnCardIndex != -1 && drawnCardIndex != 2) {
        final drawnCardData = cardsToShow.removeAt(drawnCardIndex);
        // Insert at position 2 (3rd card slot, replacing the played card)
        cardsToShow.insert(2, drawnCardData);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (cardDimensions.width + spacing) * cardsToShow.length - spacing;
        final availableWidth = constraints.maxWidth;
        final needsScroll = contentWidth > availableWidth;
        
        final cardWidgets = List.generate(cardsToShow.length, (index) {
          final cardData = cardsToShow[index];
          final cardModel = CardModel.fromMap(cardData);
          final isDrawnCard = cardData['cardId'] == _drawnCard['cardId'];
          
          // Determine if card should be face up
          // Played card (index 2): starts face down, turns face up when animation starts (phase >= 1)
          // Drawn card: face up until flipped, then face down
          final isPlayedCard = index == 2 && cardData['cardId'] == 'demo-hand-2';
          bool isFaceUp;
          if (isDrawnCard) {
            isFaceUp = !_drawnCardFlipped && (cardModel.rank != '?' && cardModel.suit != '?');
          } else if (isPlayedCard) {
            // Played card: face up when animation starts (phase >= 1), face down initially (phase 0)
            isFaceUp = _animationPhase >= 1;
          } else {
            isFaceUp = (cardModel.rank != '?' && cardModel.suit != '?');
          }
          
          // Use key for the 3rd card (index 2) - the card to be played
          // Key must be on the card when it's visible (phase 0) so animation can find it
          final isThirdCard = index == 2 && _animationPhase == 0;
          final cardKey = isThirdCard ? _thirdCardKey : null;
          
          // Use key for drawn card (at end initially, index 4, then at index 2 after move)
          final isDrawnCardAtEnd = isDrawnCard && _animationPhase < 3 && index == 4;
          final isDrawnCardAtThird = isDrawnCard && _animationPhase >= 3 && index == 2;
          final drawnCardKey = (isDrawnCardAtEnd || isDrawnCardAtThird) ? _drawnCardKey : null;
          
          // Show empty slot at 3rd position (index 2) during play and drawn card animations
          // Keep empty slot until drawn card animation completes (phase < 3)
          // Hide the played card at index 2 when showing empty slot
          final showEmptySlotAt2 = _animationPhase >= 1 && _animationPhase < 3 && index == 2;
          final hidePlayedCard = showEmptySlotAt2; // Hide the played card when showing empty slot
          
          // Show empty slot at the last position (index 4) during drawn card animation (phase 2)
          // and keep it empty in phase 3 until animation restarts
          // This creates the effect of the card moving from its position to the empty slot
          // In phase 3, the drawn card has moved to index 2, so the last position should remain empty
          final isLastPosition = index == cardsToShow.length - 1;
          final showEmptySlotAt4 = _animationPhase >= 2 && isLastPosition;
          final hideDrawnCardAtOriginalPosition = showEmptySlotAt4;

          // Show empty slot at index 2 (where played card was)
          if (hidePlayedCard) {
            return Padding(
              padding: EdgeInsets.only(
                right: index < cardsToShow.length - 1 ? spacing : 0,
              ),
              child: _buildEmptySlot(),
            );
          }
          
          // Show empty slot at index 4 (where drawn card was, during its animation)
          if (hideDrawnCardAtOriginalPosition) {
          return Padding(
            padding: EdgeInsets.only(
              right: index < cardsToShow.length - 1 ? spacing : 0,
            ),
              child: _buildEmptySlot(),
            );
          }
          
          // For played card, use actual card data when face up (animation started)
          final cardToDisplay = isPlayedCard && _animationPhase >= 1
              ? CardModel.fromMap(_playedCard) // Show actual card (7 of Hearts) when animation starts
              : (isDrawnCard && _drawnCardFlipped
                        ? CardModel(
                            cardId: _drawnCard['cardId'],
                            rank: '?',
                            suit: '?',
                            points: 0,
                          )
                  : cardModel);
          
          return Padding(
            padding: EdgeInsets.only(
              right: index < cardsToShow.length - 1 ? spacing : 0,
            ),
            child: CardWidget(
              key: cardKey ?? drawnCardKey,
              card: cardToDisplay,
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forMyHand(),
                    showBack: !isFaceUp || (isDrawnCard && _drawnCardFlipped), // Show back if card data is hidden or flipped
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
        // Animated played card (only during play animation phase) - positioned using exact coordinates
        if (_animationPhase == 1)
          AnimatedBuilder(
            animation: _playCardAnimation,
            builder: (context, child) {
              return Positioned(
                left: _playCardAnimation.value.dx - cardDimensions.width / 2,
                top: _playCardAnimation.value.dy - cardDimensions.height / 2,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.accentColor,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: CardWidget(
                    card: CardModel.fromMap(_playedCard),
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forMyHand(),
                    showBack: false, // Show face up during animation
                  ),
                ),
              );
            },
          ),
        // Animated drawn card (only during drawn card animation phase) - positioned using exact coordinates
        if (_animationPhase == 2)
          AnimatedBuilder(
            animation: _drawnCardAnimation,
            builder: (context, child) {
              return Positioned(
                left: _drawnCardAnimation.value.dx - cardDimensions.width / 2,
                top: _drawnCardAnimation.value.dy - cardDimensions.height / 2,
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
                    showBack: false, // Show face up during animation
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
