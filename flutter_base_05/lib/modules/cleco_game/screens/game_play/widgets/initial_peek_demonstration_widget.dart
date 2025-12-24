import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

/// Demonstration widget for initial peek phase
/// 
/// Shows 4 face-down cards and simulates tapping to reveal 2 of them.
/// Uses the same CardWidget and styling as MyHandWidget for consistency.
class InitialPeekDemonstrationWidget extends StatefulWidget {
  const InitialPeekDemonstrationWidget({Key? key}) : super(key: key);

  @override
  State<InitialPeekDemonstrationWidget> createState() => _InitialPeekDemonstrationWidgetState();
}

class _InitialPeekDemonstrationWidgetState extends State<InitialPeekDemonstrationWidget> {
  static const bool LOGGING_SWITCH = false; // Enabled for demo animation debugging
  static final Logger _logger = Logger();
  
  final Set<int> _revealedIndices = {};
  final Set<int> _highlightedIndices = {}; // Cards with bright border
  Timer? _animationTimer;

  /// Predefined card data for demonstration
  List<Map<String, dynamic>> get _cardData => [
    // Card 0: Ace of Spades (first to reveal)
    {
      'cardId': 'demo-0',
      'rank': 'ace',
      'suit': 'spades',
      'points': 1,
    },
    // Card 1: 7 of Hearts (second to reveal)
    {
      'cardId': 'demo-1',
      'rank': '7',
      'suit': 'hearts',
      'points': 7,
    },
    // Card 2: Face-down (not revealed)
    {
      'cardId': 'demo-2',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
    // Card 3: Face-down (not revealed)
    {
      'cardId': 'demo-3',
      'rank': '?',
      'suit': '?',
      'points': 0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  /// Start the animation sequence to simulate card reveals
  void _startAnimation() {
    // Highlight card 0 slightly before reveal (at 0.8 seconds)
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _highlightedIndices.add(0);
        });
      }
    });
    
    // Reveal card 0 after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _revealedIndices.add(0);
        });
      }
    });
    
    // Highlight card 1 slightly before reveal (at 2.3 seconds)
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (mounted) {
        setState(() {
          _highlightedIndices.add(1);
        });
      }
    });
    
    // Reveal card 1 after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _revealedIndices.add(1);
        });
      }
    });
  }

  /// Get card data for a specific index
  Map<String, dynamic> _getCardData(int index) {
    if (index >= 0 && index < _cardData.length) {
      return _cardData[index];
    }
    return {
      'cardId': 'demo-$index',
      'rank': '?',
      'suit': '?',
      'points': 0,
    };
  }

  /// Build a single card widget
  Widget _buildCard(int index) {
    final cardData = _getCardData(index);
    final isRevealed = _revealedIndices.contains(index);
    final isHighlighted = _highlightedIndices.contains(index);
    final cardModel = CardModel.fromMap(cardData);
    final dimensions = CardDimensions.getUnifiedDimensions();

    return Container(
      decoration: isHighlighted || isRevealed
          ? BoxDecoration(
              border: Border.all(
                color: AppColors.accentColor,
                width: 3.0,
              ),
              borderRadius: BorderRadius.circular(8.0),
            )
          : null,
      child: CardWidget(
        card: cardModel,
        dimensions: dimensions,
        config: CardDisplayConfig.forMyHand(),
        showBack: !isRevealed, // Show back if not revealed
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dimensions = CardDimensions.getUnifiedDimensions();
    final spacing = AppPadding.smallPadding.left;

    return SizedBox(
      height: dimensions.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          return Padding(
            padding: EdgeInsets.only(
              right: index < 3 ? spacing : 0, // No spacing after last card
            ),
            child: _buildCard(index),
          );
        }),
      ),
    );
  }
}
