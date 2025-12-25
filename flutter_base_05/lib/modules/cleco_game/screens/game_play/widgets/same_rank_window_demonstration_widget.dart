import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

/// Demonstration widget for same rank window phase
/// 
/// Shows two examples:
/// 1. Successful same rank play (card matches discard pile rank)
/// 2. Failed same rank play (wrong rank, reverts, then penalty card drawn)
class SameRankWindowDemonstrationWidget extends StatefulWidget {
  const SameRankWindowDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<SameRankWindowDemonstrationWidget> createState() => _SameRankWindowDemonstrationWidgetState();
}

class _SameRankWindowDemonstrationWidgetState extends State<SameRankWindowDemonstrationWidget>
    with TickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  // Animation phases: 0 = idle, 1 = play animation, 2 = waiting for revert, 3 = revert animation, 4 = penalty draw animation
  int _animationPhase = 0;
  int _currentExample = 0; // 0 = successful, 1 = failed
  bool _penaltyCardComplete = false; // Track when penalty card animation completes
  late AnimationController _animationController;
  late Animation<Offset> _playCardAnimation;
  late Animation<Offset> _revertCardAnimation;
  late Animation<Offset> _penaltyCardAnimation;
  
  // Store positions for revert animation
  Offset? _playStartOffset;
  Offset? _playEndOffset;
  
  // GlobalKeys to track positions
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'demo_discard_pile');
  final GlobalKey _playCardKey = GlobalKey(debugLabel: 'demo_hand_play_card');
  final GlobalKey _drawPileKey = GlobalKey(debugLabel: 'demo_draw_pile');
  final GlobalKey _lastHandCardKey = GlobalKey(debugLabel: 'demo_hand_last_card');
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'demo_stack');

  /// Top discard card (face up) - shows the rank to match
  Map<String, dynamic> get _topDiscardCard => {
    'cardId': 'demo-discard-0',
    'rank': '7',
    'suit': 'diamonds',
    'points': 7,
  };

  /// Hand cards for Example 1 (successful same rank play)
  List<Map<String, dynamic>> get _handCardsExample1 => [
    // Card 0: Face down
    {
      'cardId': 'demo-hand-1-0',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 1: Face down
    {
      'cardId': 'demo-hand-1-1',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 2: 7 of Hearts (matches discard pile rank) - will be played
    {
      'cardId': 'demo-hand-1-2',
      'rank': '7',
      'suit': 'hearts',
      'points': 7,
    },
    // Card 3: Face down
    {
      'cardId': 'demo-hand-1-3',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
  ];

  /// Hand cards for Example 2 (failed same rank play)
  List<Map<String, dynamic>> get _handCardsExample2 => [
    // Card 0: Face down
    {
      'cardId': 'demo-hand-2-0',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 1: Face down
    {
      'cardId': 'demo-hand-2-1',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 2: 5 of Clubs (wrong rank, doesn't match discard pile) - will attempt to play
    {
      'cardId': 'demo-hand-2-2',
      'rank': '5',
      'suit': 'clubs',
      'points': 5,
    },
    // Card 3: Face down
    {
      'cardId': 'demo-hand-2-3',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
  ];

  /// Get current hand cards based on example
  List<Map<String, dynamic>> get _handCards => 
      _currentExample == 0 ? _handCardsExample1 : _handCardsExample2;

  /// Get the card being played (index 2)
  Map<String, dynamic> get _playCard => _handCards[2];

  /// Penalty card data (drawn after failed same rank play)
  Map<String, dynamic> get _penaltyCard => {
    'cardId': 'demo-penalty',
    'rank': '?',
    'suit': '?',
    'points': 0,
  };

  @override
  void initState() {
    super.initState();
    // Test log to verify logging is working - using forceLog to bypass any conditions
    _logger.forceLog('🎴 SameRankDemo: Widget initialized - FORCE LOG TEST');
    _logger.info('🎴 SameRankDemo: Widget initialized - logging test', isOn: LOGGING_SWITCH);
    
    // Duration: 800ms play + 1000ms wait + 800ms revert + 800ms penalty = 3400ms total
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 3400),
      vsync: this,
    );
    
    // Initialize animations with default values (will be updated in _setupAnimations)
    _playCardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_animationController);
    
    _revertCardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));
    
    _penaltyCardAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
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

  /// Run the animation cycle for current example
  void _runAnimationCycle() {
    if (!mounted) return;
    
    // Wait for next frame to ensure positions are calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAnimations();
    });
  }

  /// Setup animations based on current example
  void _setupAnimations() {
    if (!mounted) return;
    
    _logger.info('🎴 SameRankDemo: _setupAnimations called - currentExample: $_currentExample', isOn: LOGGING_SWITCH);
    
    final playCardRenderBox = _playCardKey.currentContext?.findRenderObject() as RenderBox?;
    final discardPileRenderBox = _discardPileKey.currentContext?.findRenderObject() as RenderBox?;
    final drawPileRenderBox = _drawPileKey.currentContext?.findRenderObject() as RenderBox?;
    final lastHandCardRenderBox = _lastHandCardKey.currentContext?.findRenderObject() as RenderBox?;
    final stackContext = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    
    _logger.debug('🎴 SameRankDemo: Render boxes - playCard: ${playCardRenderBox != null}, discard: ${discardPileRenderBox != null}, draw: ${drawPileRenderBox != null}, lastHand: ${lastHandCardRenderBox != null}, stack: ${stackContext != null}', isOn: LOGGING_SWITCH);
    
    if (playCardRenderBox == null || discardPileRenderBox == null || stackContext == null) {
      // Retry after a short delay
      _logger.debug('🎴 SameRankDemo: Missing required render boxes, retrying in 100ms', isOn: LOGGING_SWITCH);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _setupAnimations();
      });
      return;
    }
    
    // Get positions relative to the Stack
    final playCardPosition = playCardRenderBox.localToGlobal(Offset.zero);
    final discardPilePosition = discardPileRenderBox.localToGlobal(Offset.zero);
    final stackPosition = stackContext.localToGlobal(Offset.zero);
    
    // Calculate play card animation positions
    final playStartOffset = Offset(
      playCardPosition.dx - stackPosition.dx + playCardRenderBox.size.width / 2,
      playCardPosition.dy - stackPosition.dy + playCardRenderBox.size.height / 2,
    );
    
    final playEndOffset = Offset(
      discardPilePosition.dx - stackPosition.dx + discardPileRenderBox.size.width / 2,
      discardPilePosition.dy - stackPosition.dy + discardPileRenderBox.size.height / 2,
    );
    
    // Store positions for revert animation
    _playStartOffset = playStartOffset;
    _playEndOffset = playEndOffset;
    
    _logger.info('🎴 SameRankDemo: Starting animation setup for Example $_currentExample', isOn: LOGGING_SWITCH);
    
    if (_currentExample == 0) {
      // Example 1: Successful same rank play
      // Just animate card to discard pile (800ms, same as other animations)
      _logger.info('🎴 SameRankDemo: Setting up Example 1 (successful play)', isOn: LOGGING_SWITCH);
      setState(() {
        _animationPhase = 1; // Start play animation
      });
      
      _playCardAnimation = Tween<Offset>(
        begin: playStartOffset,
        end: playEndOffset,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.235, curve: Curves.easeInOut), // 800ms out of 3400ms
      ));
      
      _animationController.forward(from: 0.0).then((_) {
        if (mounted) {
          _logger.info('🎴 SameRankDemo: Example 1 animation complete, waiting 2s before Example 2', isOn: LOGGING_SWITCH);
          // Wait 2 seconds, then switch to example 2 (same as jack swap demo)
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _logger.info('🎴 SameRankDemo: Switching to Example 2 (failed play with penalty)', isOn: LOGGING_SWITCH);
              setState(() {
                _currentExample = 1;
                _animationPhase = 0;
                _penaltyCardComplete = false; // Reset for example 2
              });
              _animationController.reset();
              _runAnimationCycle();
            }
          });
        }
      });
    } else {
      // Example 2: Failed same rank play
      // Animate to discard, wait 1 second, revert, then draw penalty
      _logger.info('🎴 SameRankDemo: Setting up Example 2 (failed play with penalty)', isOn: LOGGING_SWITCH);
      if (drawPileRenderBox == null || lastHandCardRenderBox == null) {
        _logger.debug('🎴 SameRankDemo: Missing drawPile or lastHandCard render boxes, retrying in 100ms', isOn: LOGGING_SWITCH);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _setupAnimations();
        });
        return;
      }
      
      final drawPilePosition = drawPileRenderBox.localToGlobal(Offset.zero);
      final lastHandCardPosition = lastHandCardRenderBox.localToGlobal(Offset.zero);
      
      setState(() {
        _animationPhase = 1; // Start play animation
      });
      
      // Play animation (to discard pile) - 0.0 to 0.235 (800ms)
      _playCardAnimation = Tween<Offset>(
        begin: playStartOffset,
        end: playEndOffset,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.235, curve: Curves.easeInOut),
      ));
      
      // Revert animation (back to hand) - 0.529 to 0.764 (800ms, after 1 second wait)
      // Wait period: 0.235 to 0.529 (1000ms wait)
      _revertCardAnimation = Tween<Offset>(
        begin: _playEndOffset!,
        end: _playStartOffset!,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.529, 0.764, curve: Curves.easeInOut),
      ));
      
      // Penalty card animation (from draw pile to hand) - 0.764 to 1.0 (800ms)
      _logger.info('🎴 SameRankDemo: Setting up penalty card animation', isOn: LOGGING_SWITCH);
      
      final penaltyStartOffset = Offset(
        drawPilePosition.dx - stackPosition.dx + drawPileRenderBox.size.width / 2,
        drawPilePosition.dy - stackPosition.dy + drawPileRenderBox.size.height / 2,
      );
      
      // Calculate position for the penalty card accounting for Row centering
      // Use actual sizes from RenderBox for accuracy
      final cardDimensions = CardDimensions.getUnifiedDimensions();
      final spacing = AppPadding.smallPadding.left;
      
      // Get the hand Row's RenderBox to understand the layout
      final handRowContext = _lastHandCardKey.currentContext?.findAncestorRenderObjectOfType<RenderFlex>();
      
      Offset penaltyEndOffset;
      
      if (handRowContext != null) {
        // Calculate where the new card will actually be positioned after Row centering
        final currentCardsCount = _handCards.length; // Before penalty card is added
        final totalCurrentWidth = (cardDimensions.width * currentCardsCount) + (spacing * (currentCardsCount - 1));
        // New card is added at the end, so add card width + spacing (spacing before the new card)
        final totalNewWidth = totalCurrentWidth + spacing + cardDimensions.width;
        
        // Get the Row's position and size
        final handRowPosition = handRowContext.localToGlobal(Offset.zero);
        final handRowSize = handRowContext.size;
        
        // Calculate the center of the Row (relative to Stack)
        final rowCenterX = handRowPosition.dx - stackPosition.dx + handRowSize.width / 2;
        
        // Calculate where the rightmost card (new penalty card) will be after centering
        // The rightmost card's center = row center + (total width / 2) - (card width / 2)
        final newCardCenterX = rowCenterX + (totalNewWidth / 2) - (cardDimensions.width / 2);
        
        penaltyEndOffset = Offset(
          newCardCenterX,
          lastHandCardPosition.dy - stackPosition.dy + lastHandCardRenderBox.size.height / 2,
        );
        
        _logger.info('🎴 SameRankDemo: Penalty card calculation (with Row centering) - currentCards: $currentCardsCount, totalNewWidth: $totalNewWidth, rowCenterX: $rowCenterX, newCardCenterX: $newCardCenterX', isOn: LOGGING_SWITCH);
      } else {
        // Fallback: simple calculation if Row context not available
        final lastCardRightEdge = lastHandCardPosition.dx - stackPosition.dx + lastHandCardRenderBox.size.width;
        final penaltyCardCenterX = lastCardRightEdge + spacing + (cardDimensions.width / 2);
        
        penaltyEndOffset = Offset(
          penaltyCardCenterX,
          lastHandCardPosition.dy - stackPosition.dy + lastHandCardRenderBox.size.height / 2,
        );
        
        _logger.info('🎴 SameRankDemo: Penalty card calculation (fallback) - lastCardRightEdge: $lastCardRightEdge, spacing: $spacing, cardWidth: ${cardDimensions.width}, centerX: $penaltyCardCenterX', isOn: LOGGING_SWITCH);
      }
      
      _logger.info('🎴 SameRankDemo: Penalty card positions - start: $penaltyStartOffset, end: $penaltyEndOffset', isOn: LOGGING_SWITCH);
      
      _penaltyCardAnimation = Tween<Offset>(
        begin: penaltyStartOffset,
        end: penaltyEndOffset,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.764, 1.0, curve: Curves.easeInOut),
      ));
      
      _logger.info('🎴 SameRankDemo: Penalty card animation created - interval: 0.764-1.0', isOn: LOGGING_SWITCH);
      
      // Start animation
      _logger.info('🎴 SameRankDemo: Starting animation cycle for Example 2 (failed play with penalty)', isOn: LOGGING_SWITCH);
      _animationController.forward(from: 0.0).then((_) {
        if (mounted) {
          _logger.info('🎴 SameRankDemo: All animations complete - setting penalty card complete', isOn: LOGGING_SWITCH);
          setState(() {
            _animationPhase = 4; // All animations complete
            _penaltyCardComplete = true; // Penalty card is now in hand
          });
          
          // Wait 2 seconds, then repeat from example 1
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _logger.info('🎴 SameRankDemo: Resetting for next cycle - switching to Example 1', isOn: LOGGING_SWITCH);
              setState(() {
                _currentExample = 0;
                _animationPhase = 0;
                _penaltyCardComplete = false; // Reset for next cycle
              });
              _animationController.reset();
              _runAnimationCycle();
            }
          });
        }
      });
      
      // Update phase during animation
      _animationController.addListener(() {
        if (mounted) {
          final value = _animationController.value;
          if (value <= 0.235) {
            setState(() => _animationPhase = 1); // Play animation
          } else if (value <= 0.529) {
            setState(() => _animationPhase = 2); // Waiting at discard
          } else if (value <= 0.764) {
            setState(() => _animationPhase = 3); // Revert animation
          } else {
            // Penalty animation phase
            if (_animationPhase != 4) {
              _logger.info('🎴 SameRankDemo: Entering penalty animation phase - value: $value, phase: 4', isOn: LOGGING_SWITCH);
            }
            setState(() => _animationPhase = 4); // Penalty animation
            
            // Log penalty animation progress at key points
            if (value >= 0.764 && value < 0.80) {
              // Just started penalty animation
              _logger.debug('🎴 SameRankDemo: Penalty animation started - value: $value, position: ${_penaltyCardAnimation.value}', isOn: LOGGING_SWITCH);
            } else if (value >= 0.90 && value < 0.95) {
              // Near completion
              _logger.debug('🎴 SameRankDemo: Penalty animation near completion - value: $value, position: ${_penaltyCardAnimation.value}', isOn: LOGGING_SWITCH);
            }
          }
        }
      });
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

  /// Build a single card widget for the hand (without padding - padding is handled in parent)
  /// Only adds wrappers when necessary (for play card animation), otherwise matches draw demo structure
  Widget _buildHandCard(Map<String, dynamic> cardData, int index, Size cardDimensions, double spacing, List<Map<String, dynamic>> handCards, {Key? providedKey}) {
    final cardModel = CardModel.fromMap(cardData);
    final isFaceUp = cardModel.rank != '?' && cardModel.suit != '?';
    
    // Check if this is the card being played (index 2)
    final isPlayCard = index == 2;
    // Use key for play card, or use provided key (e.g., for last card)
    final cardKey = providedKey ?? (isPlayCard ? _playCardKey : null);
    
    // During animation phases, hide the original card
    // For Example 2, show card again after revert completes (phase 4+)
    final shouldHide = isPlayCard && _animationPhase >= 1 && 
        (_currentExample == 0 || _animationPhase < 4);
    
    // Only add wrappers if needed (for play card animation)
    // Otherwise, use CardWidget directly like draw demo
    if (shouldHide || (isPlayCard && _animationPhase >= 1)) {
      return Opacity(
        opacity: shouldHide ? 0.0 : 1.0,
        child: Container(
          decoration: isPlayCard && _animationPhase >= 1
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
            card: cardModel,
            dimensions: cardDimensions,
            config: CardDisplayConfig.forMyHand(),
            showBack: !isFaceUp,
          ),
        ),
      );
    }
    
    // For regular cards, use CardWidget directly (matching draw demo)
    return CardWidget(
      key: cardKey,
      card: cardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forMyHand(),
      showBack: !isFaceUp,
    );
  }

  /// Build the hand section
  Widget _buildHand() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.smallPadding.left;
    
    // Add penalty card to hand if animation is complete (Example 2 only)
    final cardsToShow = List<Map<String, dynamic>>.from(_handCards);
    _logger.debug('🎴 SameRankDemo: _buildHand - _penaltyCardComplete: $_penaltyCardComplete, _currentExample: $_currentExample, _handCards.length: ${_handCards.length}', isOn: LOGGING_SWITCH);
    if (_penaltyCardComplete && _currentExample == 1) {
      cardsToShow.add(_penaltyCard);
      _logger.debug('🎴 SameRankDemo: _buildHand - Added penalty card to cardsToShow, new length: ${cardsToShow.length}', isOn: LOGGING_SWITCH);
    } else {
      _logger.debug('🎴 SameRankDemo: _buildHand - NOT adding penalty card (penaltyCardComplete: $_penaltyCardComplete, currentExample: $_currentExample)', isOn: LOGGING_SWITCH);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (cardDimensions.width + spacing) * cardsToShow.length - spacing;
        final availableWidth = constraints.maxWidth;
        // Enable scroll if content exceeds or is very close to available width
        // Use larger buffer (10px) to account for Center widget centering calculations and rounding
        // Also always scroll if we have 5+ cards to prevent any overflow issues
        final needsScroll = cardsToShow.length >= 5 || contentWidth >= (availableWidth - 10);
        
        _logger.debug('🎴 SameRankDemo: _buildHand - cardsToShow.length: ${cardsToShow.length}, cardDimensions: ${cardDimensions.width}x${cardDimensions.height}, spacing: $spacing', isOn: LOGGING_SWITCH);
        _logger.debug('🎴 SameRankDemo: _buildHand - contentWidth: $contentWidth, availableWidth: $availableWidth, needsScroll: $needsScroll', isOn: LOGGING_SWITCH);
        
        final cardWidgets = List.generate(cardsToShow.length, (index) {
          final cardData = cardsToShow[index];
          final isPenaltyCard = _penaltyCardComplete && 
                               _currentExample == 1 && 
                               cardData['cardId'] == _penaltyCard['cardId'];
          
          // Use key for the last card (where the penalty card will be placed)
          final isLastCard = index == cardsToShow.length - 1;
          final cardKey = isLastCard ? _lastHandCardKey : null;
          
          final paddingRight = index < cardsToShow.length - 1 ? spacing : 0.0;
          _logger.debug('🎴 SameRankDemo: _buildHand - card[$index]: isPenaltyCard=$isPenaltyCard, isLastCard=$isLastCard, paddingRight=$paddingRight', isOn: LOGGING_SWITCH);

          // Build penalty card exactly like drawing card demo - no extra wrappers
          final cardWidget = isPenaltyCard
              ? CardWidget(
                  key: cardKey,
                  card: CardModel.fromMap(_penaltyCard),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forMyHand(),
                  showBack: true, // Penalty card is face down
                )
              : _buildHandCard(cardsToShow[index], index, cardDimensions, spacing, cardsToShow, providedKey: cardKey);
          
          _logger.debug('🎴 SameRankDemo: _buildHand - card[$index] widget type: ${isPenaltyCard ? "CardWidget (penalty)" : "_buildHandCard"}', isOn: LOGGING_SWITCH);
          
          return Padding(
            padding: EdgeInsets.only(
              right: paddingRight,
            ),
            child: cardWidget,
          );
        });
        
        _logger.debug('🎴 SameRankDemo: _buildHand - Returning SizedBox with height: ${cardDimensions.height}, needsScroll: $needsScroll', isOn: LOGGING_SWITCH);
        
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
    
    _logger.info('🎴 SameRankDemo: build() called - animationPhase: $_animationPhase, currentExample: $_currentExample', isOn: LOGGING_SWITCH);
    
    return SizedBox(
      width: double.infinity,
      child: Stack(
        key: _stackKey,
        clipBehavior: Clip.none,
        children: [
          Column(
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
                    ? 'Example 1: Successful same rank play (7 matches 7)'
                    : 'Example 2: Failed same rank play (5 doesn\'t match 7 - penalty applied)',
                style: AppTextStyles.bodyMedium().copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            // Game Board (Draw Pile and Discard Pile)
            _buildGameBoard(),
            SizedBox(height: AppPadding.defaultPadding.top),
            // Hand
            _buildHand(),
          ],
        ),
        // Animated playing card (Example 1: successful play, Example 2: attempted play then revert)
        if (_animationPhase >= 1 && _currentExample == 0)
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
                    card: CardModel.fromMap(_playCard),
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forMyHand(),
                    showBack: false, // Show face up during animation
                  ),
                ),
              );
            },
          ),
        // Animated playing card for Example 2 (attempted play, then revert)
        if (_animationPhase >= 1 && _currentExample == 1)
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              // Show play animation during phase 1 (0.0-0.2) or waiting phase 2 (0.2-0.6)
              if (_animationPhase == 1 || _animationPhase == 2) {
                // During wait phase, card stays at discard pile position
                final currentOffset = _animationPhase == 1 
                    ? _playCardAnimation.value 
                    : _playEndOffset ?? _playCardAnimation.value;
                
                return Positioned(
                  left: currentOffset.dx - cardDimensions.width / 2,
                  top: currentOffset.dy - cardDimensions.height / 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.accentColor,
                        width: 3.0,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: CardWidget(
                      card: CardModel.fromMap(_playCard),
                      dimensions: cardDimensions,
                      config: CardDisplayConfig.forMyHand(),
                      showBack: false, // Show face up during animation
                    ),
                  ),
                );
              }
              // Show revert animation during phase 3 (0.529-0.764)
              // After revert completes (phase 4), card is shown in hand, not as animated overlay
              if (_animationPhase == 3) {
                return Positioned(
                  left: _revertCardAnimation.value.dx - cardDimensions.width / 2,
                  top: _revertCardAnimation.value.dy - cardDimensions.height / 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.accentColor,
                        width: 3.0,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: CardWidget(
                      card: CardModel.fromMap(_playCard),
                      dimensions: cardDimensions,
                      config: CardDisplayConfig.forMyHand(),
                      showBack: false, // Show face up during revert
                    ),
                  ),
                );
              }
              // Phase 4+: Card is back in hand, no longer need animated overlay
              return const SizedBox.shrink();
            },
          ),
        // Animated penalty card (Example 2 only, during animation, before completion)
        if (_currentExample == 1 && !_penaltyCardComplete)
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              // Show penalty card animation during phase 4 (0.764-1.0)
              // Hide once animation completes and card is added to hand
              final animationValue = _animationController.value;
              if (animationValue < 0.764 || animationValue >= 1.0) {
                return const SizedBox.shrink();
              }
              
              final penaltyPosition = _penaltyCardAnimation.value;
              final left = penaltyPosition.dx - cardDimensions.width / 2;
              final top = penaltyPosition.dy - cardDimensions.height / 2;
              
              // Log penalty card rendering (throttled to avoid spam)
              if ((animationValue * 100).round() % 10 == 0) {
                _logger.debug('🎴 SameRankDemo: Rendering penalty card - value: $animationValue, position: ($left, $top)', isOn: LOGGING_SWITCH);
              }
              
              return Positioned(
                left: left,
                top: top,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.accentColor,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: CardWidget(
                    card: CardModel(
                      cardId: 'demo-penalty',
                      rank: '?',
                      suit: '?',
                      points: 0,
                    ),
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forMyHand(),
                    showBack: true, // Show face down (penalty card)
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
