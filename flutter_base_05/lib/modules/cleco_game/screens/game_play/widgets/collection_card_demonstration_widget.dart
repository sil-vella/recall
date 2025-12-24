import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

/// Demonstration widget for collection card phase
/// 
/// Shows how a same rank card from the discard pile is collected
/// and placed on top of the face-up collection card in hand.
/// The card animates from discard pile to the collection card position,
/// slightly offset to show stacking.
class CollectionCardDemonstrationWidget extends StatefulWidget {
  const CollectionCardDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<CollectionCardDemonstrationWidget> createState() => _CollectionCardDemonstrationWidgetState();
}

class _CollectionCardDemonstrationWidgetState extends State<CollectionCardDemonstrationWidget>
    with TickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  int _animationPhase = 0; // 0 = idle, 1 = animating
  late AnimationController _animationController;
  late Animation<Offset> _collectionCardAnimation;
  
  // GlobalKeys to track positions
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'demo_discard_pile');
  final GlobalKey _collectionCardKey = GlobalKey(debugLabel: 'demo_collection_card');
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'demo_stack');

  /// Top discard card (face up) - same rank as collection card
  Map<String, dynamic> get _topDiscardCard => {
    'cardId': 'demo-discard-collection',
    'rank': '7',
    'suit': 'diamonds',
    'points': 7,
  };

  /// Hand cards - first card is face up (collection card), others face down
  List<Map<String, dynamic>> get _handCards => [
    // Card 0: Face up collection card (7 of Hearts) - same rank as discard
    {
      'cardId': 'demo-hand-collection-0',
      'rank': '7',
      'suit': 'hearts',
      'points': 7,
    },
    // Card 1: Face down
    {
      'cardId': 'demo-hand-collection-1',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 2: Face down
    {
      'cardId': 'demo-hand-collection-2',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 3: Face down
    {
      'cardId': 'demo-hand-collection-3',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800), // Same as other animations
      vsync: this,
    );
    
    // Initialize animation with default values (will be updated in _setupAnimations)
    _collectionCardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Start animation cycle after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAnimationCycle();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Run the animation cycle
  void _runAnimationCycle() {
    if (!mounted) return;
    
    // Wait for next frame to ensure positions are calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAnimations();
    });
  }

  /// Setup animations based on actual positions
  void _setupAnimations() {
    if (!mounted) return;
    
    final discardPileRenderBox = _discardPileKey.currentContext?.findRenderObject() as RenderBox?;
    final collectionCardRenderBox = _collectionCardKey.currentContext?.findRenderObject() as RenderBox?;
    final stackContext = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (discardPileRenderBox == null || collectionCardRenderBox == null || stackContext == null) {
      // Retry after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _setupAnimations();
      });
      return;
    }
    
    // Get positions relative to the Stack
    final discardPilePosition = discardPileRenderBox.localToGlobal(Offset.zero);
    final collectionCardPosition = collectionCardRenderBox.localToGlobal(Offset.zero);
    final stackPosition = stackContext.localToGlobal(Offset.zero);
    
    // Calculate animation positions
    final startOffset = Offset(
      discardPilePosition.dx - stackPosition.dx + discardPileRenderBox.size.width / 2,
      discardPilePosition.dy - stackPosition.dy + discardPileRenderBox.size.height / 2,
    );
    
    // End position: collection card position, but slightly lower to show stacking
    final stackOffset = 8.0; // Slight vertical offset to show stacking
    final endOffset = Offset(
      collectionCardPosition.dx - stackPosition.dx + collectionCardRenderBox.size.width / 2,
      collectionCardPosition.dy - stackPosition.dy + collectionCardRenderBox.size.height / 2 + stackOffset,
    );
    
    setState(() {
      _animationPhase = 1; // Start animation
    });
    
    _collectionCardAnimation = Tween<Offset>(
      begin: startOffset,
      end: endOffset,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.forward(from: 0.0).then((_) {
      if (mounted) {
        // Wait 2 seconds, then repeat (same as other demos)
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _animationController.reset();
            _runAnimationCycle();
          }
        });
      }
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
                CardWidget(
                  key: _discardPileKey,
                  card: CardModel.fromMap(_topDiscardCard),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDiscardPile(),
                  showBack: false, // Show face up
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
    final handCards = _handCards;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (cardDimensions.width + spacing) * handCards.length - spacing;
        final availableWidth = constraints.maxWidth;
        final needsScroll = contentWidth > availableWidth;
        
        final cardWidgets = List.generate(handCards.length, (index) {
          final cardData = handCards[index];
          final cardModel = CardModel.fromMap(cardData);
          final isFaceUp = cardModel.rank != '?' && cardModel.suit != '?';
          
          // First card (index 0) is the collection card
          final isCollectionCard = index == 0;
          final cardKey = isCollectionCard ? _collectionCardKey : null;
          
          return Padding(
            padding: EdgeInsets.only(
              right: index < handCards.length - 1 ? spacing : 0,
            ),
            child: CardWidget(
              key: cardKey,
              card: cardModel,
              dimensions: cardDimensions,
              config: CardDisplayConfig.forMyHand(),
              showBack: !isFaceUp,
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
      key: _stackKey,
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
        // Animated collection card (from discard pile to collection card)
        if (_animationPhase >= 1)
          AnimatedBuilder(
            animation: _collectionCardAnimation,
            builder: (context, child) {
              return Positioned(
                left: _collectionCardAnimation.value.dx - cardDimensions.width / 2,
                top: _collectionCardAnimation.value.dy - cardDimensions.height / 2,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.accentColor,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: CardWidget(
                    card: CardModel.fromMap(_topDiscardCard),
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
