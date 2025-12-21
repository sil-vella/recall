import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';

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
  bool _animationStarted = false;
  bool _animationComplete = false;
  late AnimationController _animationController;
  late Animation<Offset> _cardAnimation;
  
  // GlobalKeys to track positions
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'demo_discard_pile');
  final GlobalKey _thirdCardKey = GlobalKey(debugLabel: 'demo_hand_third_card');
  
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

  /// Hand cards - one face up (Ace of Spades), others face down
  /// The 3rd card (index 2) will be played
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
    // Card 2: The card to be played (7 of Hearts)
    {
      'cardId': 'demo-hand-2',
      'rank': '7',
      'suit': 'hearts',
      'points': 7,
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
        final thirdCardRenderBox = _thirdCardKey.currentContext?.findRenderObject() as RenderBox?;
        final discardPileRenderBox = _discardPileKey.currentContext?.findRenderObject() as RenderBox?;
        
        if (thirdCardRenderBox != null && discardPileRenderBox != null) {
          // Get positions relative to the Stack
          final thirdCardPosition = thirdCardRenderBox.localToGlobal(Offset.zero);
          final discardPilePosition = discardPileRenderBox.localToGlobal(Offset.zero);
          
          // Get the Stack's position to calculate relative positions
          final stackContext = context.findRenderObject() as RenderBox?;
          if (stackContext != null) {
            final stackPosition = stackContext.localToGlobal(Offset.zero);
            
            // Calculate center positions relative to the Stack
            final startOffset = Offset(
              thirdCardPosition.dx - stackPosition.dx + thirdCardRenderBox.size.width / 2,
              thirdCardPosition.dy - stackPosition.dy + thirdCardRenderBox.size.height / 2,
            );
            
            final endOffset = Offset(
              discardPilePosition.dx - stackPosition.dx + discardPileRenderBox.size.width / 2,
              discardPilePosition.dy - stackPosition.dy + discardPileRenderBox.size.height / 2,
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
            });
            
            _animationController.forward(from: 0.0).then((_) {
              if (mounted) {
                setState(() {
                  _animationComplete = true;
                });
                // Reset and repeat after 4 seconds total (including animation time)
                Future.delayed(const Duration(milliseconds: 3200), () {
                  if (mounted) {
                    _runAnimationCycle();
                  }
                });
              }
            });
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
                      card: CardModel.fromMap(_animationComplete ? _playedCard : _topDiscardCard),
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

  /// Build the hand section
  Widget _buildHand() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.smallPadding.left;
    
    // Remove played card from hand if animation is complete
    final cardsToShow = List<Map<String, dynamic>>.from(_handCards);
    if (_animationComplete) {
      // Remove the 3rd card (index 2) - the played card
      cardsToShow.removeAt(2);
    }

    return SizedBox(
      height: cardDimensions.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(cardsToShow.length, (index) {
          final cardData = cardsToShow[index];
          final cardModel = CardModel.fromMap(cardData);
          // The 3rd card (index 2) should be face up (it has card data)
          // Other cards except the first are face down
          final isFaceUp = (cardModel.rank != '?' && cardModel.suit != '?');
          
          // Use key for the 3rd card (index 2 in original list)
          // Before animation completes, the 3rd card is at index 2
          // After animation completes, we remove it
          final isThirdCard = !_animationComplete && index == 2;
          final cardKey = isThirdCard ? _thirdCardKey : null;

          return Padding(
            padding: EdgeInsets.only(
              right: index < cardsToShow.length - 1 ? spacing : 0,
            ),
            child: CardWidget(
              key: cardKey,
              card: cardModel,
              dimensions: cardDimensions,
              config: CardDisplayConfig.forMyHand(),
              showBack: !isFaceUp, // Show back if card data is hidden
            ),
          );
        }),
      ),
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
                child: CardWidget(
                  card: CardModel.fromMap(_playedCard),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forMyHand(),
                  showBack: false, // Show face up during animation
                ),
              );
            },
          ),
      ],
    );
  }
}
