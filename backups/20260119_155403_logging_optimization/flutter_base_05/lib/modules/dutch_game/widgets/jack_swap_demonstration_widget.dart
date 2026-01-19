import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../utils/card_dimensions.dart';
import 'card_widget.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../tools/logging/logger.dart';

/// Demonstration widget for jack swap phase
/// 
/// Shows three examples:
/// 1. Swap 2 cards from 2 different opponents
/// 2. Swap a card from my hand with a card from an opponent
/// 3. Swap the collection card (face up) from my hand with another card from my hand
/// Uses the same CardWidget and styling as the actual game widgets for consistency.
class JackSwapDemonstrationWidget extends StatefulWidget {
  const JackSwapDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<JackSwapDemonstrationWidget> createState() => _JackSwapDemonstrationWidgetState();
}

class _JackSwapDemonstrationWidgetState extends State<JackSwapDemonstrationWidget>
    with TickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  int _currentExample = 0; // 0 = opponent-opponent, 1 = my hand-opponent, 2 = my hand-my hand
  int _animationPhase = 0; // 0 = idle, 1 = first tap, 2 = second tap, 3 = swapping, 4 = complete
  late AnimationController _tapAnimationController;
  late AnimationController _swapAnimationController;
  late Animation<double> _firstTapAnimation;
  late Animation<double> _secondTapAnimation;
  late Animation<Offset> _firstCardSwapAnimation;
  late Animation<Offset> _secondCardSwapAnimation;
  late Animation<double> _firstCardSizeAnimation;
  late Animation<double> _secondCardSizeAnimation;
  late Animation<double> _flipAnimation;
  
  // GlobalKeys to track positions
  final GlobalKey _firstCardKey = GlobalKey(debugLabel: 'demo_first_card');
  final GlobalKey _secondCardKey = GlobalKey(debugLabel: 'demo_second_card');
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'demo_stack');
  
  // Store actual card dimensions for animations
  Size? _firstCardBaseSize;
  Size? _secondCardBaseSize;
  
  /// My hand cards - includes one face up collection card
  List<Map<String, dynamic>> get _myHandCards => [
    // Card 0: Face up (collection card - Ace of Spades)
    {
      'cardId': 'demo-my-hand-0',
      'rank': 'ace',
      'suit': 'spades',
      'points': 1,
    },
    // Card 1: Face down
    {
      'cardId': 'demo-my-hand-1',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 2: Face down (will be swapped in example 2)
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
  
  /// Opponent data for demonstration
  List<Map<String, dynamic>> get _opponents => [
    {
      'id': 'opponent-1',
      'name': 'Player 1',
      'hand': [
        {'cardId': 'opp1-card-0', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp1-card-1', 'rank': '?', 'suit': '?', 'points': 0}, // Will be swapped in example 1
        {'cardId': 'opp1-card-2', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp1-card-3', 'rank': '?', 'suit': '?', 'points': 0},
      ],
    },
    {
      'id': 'opponent-2',
      'name': 'Player 2',
      'hand': [
        {'cardId': 'opp2-card-0', 'rank': '?', 'suit': '?', 'points': 0},
        {'cardId': 'opp2-card-1', 'rank': '?', 'suit': '?', 'points': 0}, // Will be swapped in example 1
        {'cardId': 'opp2-card-2', 'rank': '?', 'suit': '?', 'points': 0}, // Will be swapped in example 2
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
  
  /// Get card data for first card in current example
  Map<String, dynamic>? _getFirstCardData() {
    switch (_currentExample) {
      case 0: // Opponent-opponent swap
        return _opponents[0]['hand'][1] as Map<String, dynamic>;
      case 1: // My hand-opponent swap
        return _myHandCards[1];
      case 2: // My hand-my hand swap (collection card)
        return _myHandCards[0];
      default:
        return null;
    }
  }
  
  /// Get card data for second card in current example
  Map<String, dynamic>? _getSecondCardData() {
    switch (_currentExample) {
      case 0: // Opponent-opponent swap
        return _opponents[1]['hand'][1] as Map<String, dynamic>;
      case 1: // My hand-opponent swap
        return _opponents[1]['hand'][2] as Map<String, dynamic>;
      case 2: // My hand-my hand swap
        return _myHandCards[2];
      default:
        return null;
    }
  }
  
  /// Get opponent index for first card
  int? _getFirstCardOpponentIndex() {
    switch (_currentExample) {
      case 0:
        return 0; // Player 1
      case 1:
        return null; // My hand
      case 2:
        return null; // My hand
      default:
        return null;
    }
  }
  
  /// Get opponent index for second card
  int? _getSecondCardOpponentIndex() {
    switch (_currentExample) {
      case 0:
        return 1; // Player 2
      case 1:
        return 1; // Player 2
      case 2:
        return null; // My hand
      default:
        return null;
    }
  }
  
  /// Get card index in hand for first card
  int _getFirstCardIndex() {
    switch (_currentExample) {
      case 0:
        return 1; // Opponent 1, card 1
      case 1:
        return 1; // My hand, card 1
      case 2:
        return 0; // My hand, card 0 (collection)
      default:
        return 0;
    }
  }
  
  /// Get card index in hand for second card
  int _getSecondCardIndex() {
    switch (_currentExample) {
      case 0:
        return 1; // Opponent 2, card 1
      case 1:
        return 2; // Opponent 2, card 2
      case 2:
        return 2; // My hand, card 2
      default:
        return 0;
    }
  }
  
  /// Check if first card is from my hand
  bool _isFirstCardMyHand() => _getFirstCardOpponentIndex() == null;
  
  /// Check if second card is from my hand
  bool _isSecondCardMyHand() => _getSecondCardOpponentIndex() == null;
  

  @override
  void initState() {
    super.initState();
    
    // Tap animation controller (for simulating card taps)
    _tapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    // Swap animation controller (for card swap movement)
    _swapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // Initialize animations with default values to prevent null access
    _firstCardSwapAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_swapAnimationController);
    
    _secondCardSwapAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_swapAnimationController);
    
    _firstCardSizeAnimation = ConstantTween<double>(1.0).animate(_swapAnimationController);
    _secondCardSizeAnimation = ConstantTween<double>(1.0).animate(_swapAnimationController);
    
    // Tap animations (pulse effect - scale up then back down)
    _firstTapAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(
      parent: _tapAnimationController,
      curve: const Interval(0.0, 0.5, curve: Curves.linear),
    ));
    
    _secondTapAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(
      parent: _tapAnimationController,
      curve: const Interval(0.5, 1.0, curve: Curves.linear),
    ));
    
    // Flip animation (for turning cards face down at end)
    _flipAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _swapAnimationController,
      curve: const Interval(0.8, 1.0, curve: Curves.easeInOut),
    ));
    
    _startAnimation();
  }

  @override
  void dispose() {
    _tapAnimationController.dispose();
    _swapAnimationController.dispose();
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
      _animationPhase = 0;
    });
    
    // Wait for next frame to ensure positions are calculated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        
        // Phase 1: First tap
        setState(() {
          _animationPhase = 1;
        });
        _tapAnimationController.forward(from: 0.0).then((_) {
          if (!mounted) return;
          
          // Small delay between taps
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!mounted) return;
            
            // Phase 2: Second tap
            setState(() {
              _animationPhase = 2;
            });
            _tapAnimationController.forward(from: 0.5).then((_) {
              if (!mounted) return;
              
              // Phase 3: Setup swap animation and start swapping
              Future.delayed(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                
              _setupSwapAnimations();
              setState(() {
                _animationPhase = 3;
              });
              
              _logger.info('🃏 JackSwapDemo: Starting swap animation - phase: $_animationPhase', isOn: LOGGING_SWITCH);
              
              _swapAnimationController.forward(from: 0.0).then((_) {
                _logger.info('🃏 JackSwapDemo: Swap animation completed', isOn: LOGGING_SWITCH);
                  if (!mounted) return;
                  
                  // Phase 4: Complete - cards are face down
                  setState(() {
                    _animationPhase = 4;
                  });
                  
                  // Wait 2 seconds then switch to next example or repeat
                  Future.delayed(const Duration(seconds: 2), () {
                    if (!mounted) return;
                    
                    _tapAnimationController.reset();
                    _swapAnimationController.reset();
                    _firstCardBaseSize = null;
                    _secondCardBaseSize = null;
                    
                    if (exampleIndex == 0) {
                      _runExample(1);
                    } else if (exampleIndex == 1) {
                      _runExample(2);
                    } else {
                      _runExample(0);
                    }
                  });
                });
              });
            });
          });
        });
      });
    });
  }
  
  void _setupSwapAnimations() {
    _logger.info('🃏 JackSwapDemo: Setting up swap animations - phase: $_animationPhase, example: $_currentExample', isOn: LOGGING_SWITCH);
    
    // Get positions after layout
    final firstCardRenderBox = _firstCardKey.currentContext?.findRenderObject() as RenderBox?;
    final secondCardRenderBox = _secondCardKey.currentContext?.findRenderObject() as RenderBox?;
    final stackRenderBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    
    _logger.info('🃏 JackSwapDemo: RenderBox check - firstCard: ${firstCardRenderBox != null}, secondCard: ${secondCardRenderBox != null}, stack: ${stackRenderBox != null}', isOn: LOGGING_SWITCH);
    
    if (firstCardRenderBox == null || secondCardRenderBox == null || stackRenderBox == null) {
      _logger.warning('🃏 JackSwapDemo: Cannot setup animations - missing RenderBoxes', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Store actual card sizes
    _firstCardBaseSize = firstCardRenderBox.size;
    _secondCardBaseSize = secondCardRenderBox.size;
    
    _logger.info('🃏 JackSwapDemo: Card sizes - first: ${_firstCardBaseSize}, second: ${_secondCardBaseSize}', isOn: LOGGING_SWITCH);
    
    // Get positions relative to stack
    final firstCardPosition = firstCardRenderBox.localToGlobal(Offset.zero);
    final secondCardPosition = secondCardRenderBox.localToGlobal(Offset.zero);
    final stackPosition = stackRenderBox.localToGlobal(Offset.zero);
    
    _logger.info('🃏 JackSwapDemo: Positions - firstCard: $firstCardPosition, secondCard: $secondCardPosition, stack: $stackPosition', isOn: LOGGING_SWITCH);
    
    final firstCardCenter = Offset(
      firstCardPosition.dx - stackPosition.dx + firstCardRenderBox.size.width / 2,
      firstCardPosition.dy - stackPosition.dy + firstCardRenderBox.size.height / 2,
    );
    
    final secondCardCenter = Offset(
      secondCardPosition.dx - stackPosition.dx + secondCardRenderBox.size.width / 2,
      secondCardPosition.dy - stackPosition.dy + secondCardRenderBox.size.height / 2,
    );
    
    _logger.info('🃏 JackSwapDemo: Calculated centers - first: $firstCardCenter, second: $secondCardCenter', isOn: LOGGING_SWITCH);
    
    // Calculate size ratio
    final sizeRatio = firstCardRenderBox.size.width / secondCardRenderBox.size.width;
    _logger.info('🃏 JackSwapDemo: Size ratio: $sizeRatio', isOn: LOGGING_SWITCH);
    
    // Create swap animations
    _firstCardSwapAnimation = Tween<Offset>(
      begin: firstCardCenter,
      end: secondCardCenter,
    ).animate(CurvedAnimation(
      parent: _swapAnimationController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
    ));
    
    _secondCardSwapAnimation = Tween<Offset>(
      begin: secondCardCenter,
      end: firstCardCenter,
    ).animate(CurvedAnimation(
      parent: _swapAnimationController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
    ));
    
    _logger.info('🃏 JackSwapDemo: Swap animations created - first: ${_firstCardSwapAnimation.value} -> ${secondCardCenter}, second: ${_secondCardSwapAnimation.value} -> $firstCardCenter', isOn: LOGGING_SWITCH);
    
    // Size animations (only if cards are different sizes)
    if (_isFirstCardMyHand() != _isSecondCardMyHand()) {
      // One card is from my hand (larger), one from opponent (smaller)
      if (_isFirstCardMyHand()) {
        // First card shrinks, second card grows
        _firstCardSizeAnimation = Tween<double>(
          begin: 1.0,
          end: 1.0 / sizeRatio,
        ).animate(CurvedAnimation(
          parent: _swapAnimationController,
          curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
        ));
        
        _secondCardSizeAnimation = Tween<double>(
          begin: 1.0,
          end: sizeRatio,
        ).animate(CurvedAnimation(
          parent: _swapAnimationController,
          curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
        ));
      } else {
        // First card grows, second card shrinks
        _firstCardSizeAnimation = Tween<double>(
          begin: 1.0,
          end: sizeRatio,
        ).animate(CurvedAnimation(
          parent: _swapAnimationController,
          curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
        ));
        
        _secondCardSizeAnimation = Tween<double>(
          begin: 1.0,
          end: 1.0 / sizeRatio,
        ).animate(CurvedAnimation(
          parent: _swapAnimationController,
          curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
        ));
      }
    } else {
      // Same size cards - no size animation
      _firstCardSizeAnimation = ConstantTween<double>(1.0).animate(_swapAnimationController);
      _secondCardSizeAnimation = ConstantTween<double>(1.0).animate(_swapAnimationController);
    }
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
          
          // Check if this card is involved in swap
          final isFirstCard = _isFirstCardMyHand() && 
                             index == _getFirstCardIndex() &&
                             (_currentExample == 1 || _currentExample == 2);
          final isSecondCard = _isSecondCardMyHand() && 
                               index == _getSecondCardIndex() &&
                               _currentExample == 2;
          
          final isSwappingCard = isFirstCard || isSecondCard;
          final cardKey = isFirstCard ? _firstCardKey : (isSecondCard ? _secondCardKey : null);
          
          // Determine if card should be face down
          // Only cards that were swapped should turn face down at the end
          // In example 3, only the two swapped cards (collection card and the other card) turn face down
          final wasSwapped = isSwappingCard;
          final showBack = wasSwapped && _animationPhase >= 4 ? true : (!isFaceUp);

          return Padding(
            padding: EdgeInsets.only(
              right: index < _myHandCards.length - 1 ? spacing : 0,
            ),
            child: AnimatedBuilder(
              animation: _tapAnimationController,
              builder: (context, child) {
                // Tap animation (pulse)
                double tapScale = 1.0;
                if (isFirstCard && _animationPhase >= 1) {
                  tapScale = _firstTapAnimation.value;
                } else if (isSecondCard && _animationPhase >= 2) {
                  tapScale = _secondTapAnimation.value;
                }
                
                // Determine if card should have bright border (during tap or swap)
                final shouldShowBorder = (isFirstCard && _animationPhase >= 1) || 
                                         (isSecondCard && _animationPhase >= 2) ||
                                         (isSwappingCard && _animationPhase >= 3);
                
                return Transform.scale(
                  scale: tapScale,
                  child: Opacity(
                    opacity: isSwappingCard && _animationPhase >= 3 ? 0.0 : 1.0,
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
                        card: CardModel.fromMap(cardData),
                        dimensions: cardDimensions,
                        config: CardDisplayConfig.forMyHand(),
                        showBack: showBack,
                      ),
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
                      
                      // Check if this card is involved in swap
                      final isFirstCard = _getFirstCardOpponentIndex() == opponentIndex && 
                                         index == _getFirstCardIndex() &&
                                         _currentExample == 0;
                      final isSecondCard = _getSecondCardOpponentIndex() == opponentIndex && 
                                           index == _getSecondCardIndex() &&
                                           (_currentExample == 0 || _currentExample == 1);
                      
                      final isSwappingCard = isFirstCard || isSecondCard;
                      final cardKey = isFirstCard ? _firstCardKey : (isSecondCard ? _secondCardKey : null);
                      
                      // Determine if card should be face down
                      // Only cards that were swapped should turn face down at the end
                      final wasSwapped = isSwappingCard;
                      final showBack = wasSwapped && _animationPhase >= 4 ? true : true; // Opponents always face down initially

                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < hand.length - 1 ? cardPadding : 0,
                        ),
                        child: AnimatedBuilder(
                          animation: _tapAnimationController,
                          builder: (context, child) {
                            // Tap animation (pulse)
                            double tapScale = 1.0;
                            if (isFirstCard && _animationPhase >= 1) {
                              tapScale = _firstTapAnimation.value;
                            } else if (isSecondCard && _animationPhase >= 2) {
                              tapScale = _secondTapAnimation.value;
                            }
                            
                      // Determine if card should have bright border (during tap or swap)
                      final shouldShowBorder = (isFirstCard && _animationPhase >= 1) || 
                                               (isSecondCard && _animationPhase >= 2) ||
                                               (isSwappingCard && _animationPhase >= 3);
                      
                      return Transform.scale(
                        scale: tapScale,
                        child: Opacity(
                          opacity: isSwappingCard && _animationPhase >= 3 ? 0.0 : 1.0,
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
                              card: CardModel.fromMap(cardData),
                              dimensions: cardDimensions,
                              config: CardDisplayConfig.forOpponent(),
                              showBack: showBack,
                            ),
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
    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      children: [
        // Main content
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
                    ? 'Example 1: Swap cards between opponents'
                    : _currentExample == 1
                        ? 'Example 2: Swap card from my hand with opponent'
                        : 'Example 3: Swap collection card with another card in my hand',
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
        ),
        // Animated swapping cards overlay - use Positioned.fill to ensure proper bounds
        if (_animationPhase >= 3)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true, // Allow clicks to pass through
              child: AnimatedBuilder(
                animation: _swapAnimationController,
                builder: (context, child) {
                  final firstCardData = _getFirstCardData();
                  final secondCardData = _getSecondCardData();
              
                  if (firstCardData == null || secondCardData == null) {
                    _logger.warning('🃏 JackSwapDemo: Missing card data in animation builder', isOn: LOGGING_SWITCH);
                    return const SizedBox.shrink();
                  }
                  
                  // Use stored base sizes (set in _setupSwapAnimations)
                  if (_firstCardBaseSize == null || _secondCardBaseSize == null) {
                    _logger.warning('🃏 JackSwapDemo: Missing base sizes in animation builder - first: ${_firstCardBaseSize != null}, second: ${_secondCardBaseSize != null}', isOn: LOGGING_SWITCH);
                    return const SizedBox.shrink();
                  }
                  
                  // Check if animations are initialized
                  try {
                    final firstOffset = _firstCardSwapAnimation.value;
                    final secondOffset = _secondCardSwapAnimation.value;
                    _logger.info('🃏 JackSwapDemo: Animation values - first: $firstOffset, second: $secondOffset, controller: ${_swapAnimationController.value}', isOn: LOGGING_SWITCH);
                  } catch (e) {
                    _logger.error('🃏 JackSwapDemo: Error accessing animation values: $e', isOn: LOGGING_SWITCH);
                    return const SizedBox.shrink();
                  }
                  
                  // Get card dimensions based on source
                  final firstCardIsMyHand = _isFirstCardMyHand();
                  final secondCardIsMyHand = _isSecondCardMyHand();
                  
                  // Calculate final dimensions with size animation
                  final firstCardFinalWidth = _firstCardBaseSize!.width * _firstCardSizeAnimation.value;
                  final firstCardFinalHeight = _firstCardBaseSize!.height * _firstCardSizeAnimation.value;
                  final secondCardFinalWidth = _secondCardBaseSize!.width * _secondCardSizeAnimation.value;
                  final secondCardFinalHeight = _secondCardBaseSize!.height * _secondCardSizeAnimation.value;
                  
                  // Determine if cards should show back (face down)
                  // During swap animation, maintain initial state
                  // After flip animation completes, both cards turn face down
                  final firstCardShowBack = _flipAnimation.value >= 1.0;
                  final secondCardShowBack = _flipAnimation.value >= 1.0;
                  
                  // Return both Positioned widgets directly in Stack
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // First card animation - fully visible during swap with bright border
                      Positioned(
                        left: _firstCardSwapAnimation.value.dx - firstCardFinalWidth / 2,
                        top: _firstCardSwapAnimation.value.dy - firstCardFinalHeight / 2,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.accentColor,
                              width: 3.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: CardWidget(
                            card: CardModel.fromMap(firstCardData),
                            dimensions: Size(firstCardFinalWidth, firstCardFinalHeight),
                            config: firstCardIsMyHand 
                                ? CardDisplayConfig.forMyHand() 
                                : CardDisplayConfig.forOpponent(),
                            showBack: firstCardShowBack,
                          ),
                        ),
                      ),
                      // Second card animation - fully visible during swap with bright border
                      Positioned(
                        left: _secondCardSwapAnimation.value.dx - secondCardFinalWidth / 2,
                        top: _secondCardSwapAnimation.value.dy - secondCardFinalHeight / 2,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.accentColor,
                              width: 3.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: CardWidget(
                            card: CardModel.fromMap(secondCardData),
                            dimensions: Size(secondCardFinalWidth, secondCardFinalHeight),
                            config: secondCardIsMyHand 
                                ? CardDisplayConfig.forMyHand() 
                                : CardDisplayConfig.forOpponent(),
                            showBack: secondCardShowBack,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
