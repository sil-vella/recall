import 'package:flutter/material.dart' hide Card;
import '../models/card.dart';
import 'game_constants.dart';

/// Utility functions for card operations
class CardUtils {
  /// Get card color for display
  static String getCardColor(Card card) {
    return card.color;
  }

  /// Get card suit symbol
  static String getCardSuitSymbol(CardSuit suit) {
    switch (suit) {
      case CardSuit.hearts:
        return '♥';
      case CardSuit.diamonds:
        return '♦';
      case CardSuit.clubs:
        return '♣';
      case CardSuit.spades:
        return '♠';
    }
  }

  /// Get card rank display name
  static String getCardRankDisplay(CardRank rank) {
    switch (rank) {
      case CardRank.ace:
        return 'A';
      case CardRank.two:
        return '2';
      case CardRank.three:
        return '3';
      case CardRank.four:
        return '4';
      case CardRank.five:
        return '5';
      case CardRank.six:
        return '6';
      case CardRank.seven:
        return '7';
      case CardRank.eight:
        return '8';
      case CardRank.nine:
        return '9';
      case CardRank.ten:
        return '10';
      case CardRank.jack:
        return 'J';
      case CardRank.queen:
        return 'Q';
      case CardRank.king:
        return 'K';
    }
  }

  /// Get card display name
  static String getCardDisplayName(Card card) {
    final rankDisplay = getCardRankDisplay(card.rank);
    final suitSymbol = getCardSuitSymbol(card.suit);
    return '$rankDisplay$suitSymbol';
  }

  /// Get card short name (for compact display)
  static String getCardShortName(Card card) {
    return getCardDisplayName(card);
  }

  /// Get card full name (for tooltips)
  static String getCardFullName(Card card) {
    final rankName = card.rank.name.substring(0, 1).toUpperCase() + card.rank.name.substring(1);
    final suitName = card.suit.name.substring(0, 1).toUpperCase() + card.suit.name.substring(1);
    return '$rankName of $suitName';
  }

  /// Check if card is playable
  static bool isCardPlayable(Card card, List<Card> playableCards) {
    return playableCards.contains(card);
  }

  /// Check if card can be played out of turn
  static bool canPlayOutOfTurn(Card card) {
    return card.canPlayOutOfTurn;
  }

  /// Get playable cards from hand
  static List<Card> getPlayableCards(List<Card> hand, List<Card> centerPile) {
    if (centerPile.isEmpty) {
      return hand; // Any card can be played if center pile is empty
    }
    
    final topCard = centerPile.last;
    return hand.where((card) => card.rank == topCard.rank).toList();
  }

  /// Sort cards by rank and suit
  static List<Card> sortCards(List<Card> cards) {
    final sortedCards = List<Card>.from(cards);
    sortedCards.sort((a, b) {
      // First sort by rank
      if (a.rank.value != b.rank.value) {
        return a.rank.value.compareTo(b.rank.value);
      }
      // Then sort by suit
      return a.suit.index.compareTo(b.suit.index);
    });
    return sortedCards;
  }

  /// Sort cards by points (highest first)
  static List<Card> sortCardsByPoints(List<Card> cards) {
    final sortedCards = List<Card>.from(cards);
    sortedCards.sort((a, b) => b.points.compareTo(a.points));
    return sortedCards;
  }

  /// Get cards with special powers
  static List<Card> getSpecialPowerCards(List<Card> cards) {
    return cards.where((card) => card.hasSpecialPower).toList();
  }

  /// Get cards by special power type
  static List<Card> getCardsBySpecialPower(List<Card> cards, SpecialPowerType powerType) {
    return cards.where((card) => card.specialPower == powerType).toList();
  }

  /// Get queen cards
  static List<Card> getQueenCards(List<Card> cards) {
    return getCardsBySpecialPower(cards, SpecialPowerType.queen);
  }

  /// Get jack cards
  static List<Card> getJackCards(List<Card> cards) {
    return getCardsBySpecialPower(cards, SpecialPowerType.jack);
  }

  /// Get added power cards
  static List<Card> getAddedPowerCards(List<Card> cards) {
    return getCardsBySpecialPower(cards, SpecialPowerType.addedPower);
  }

  /// Get lowest point card
  static Card? getLowestPointCard(List<Card> cards) {
    if (cards.isEmpty) return null;
    
    Card lowestCard = cards.first;
    for (final card in cards) {
      if (card.points < lowestCard.points) {
        lowestCard = card;
      }
    }
    return lowestCard;
  }

  /// Get highest point card
  static Card? getHighestPointCard(List<Card> cards) {
    if (cards.isEmpty) return null;
    
    Card highestCard = cards.first;
    for (final card in cards) {
      if (card.points > highestCard.points) {
        highestCard = card;
      }
    }
    return highestCard;
  }

  /// Calculate total points in hand
  static int calculateHandPoints(List<Card> cards) {
    return cards.fold(0, (sum, card) => sum + card.points);
  }

  /// Get card background color
  static int getCardBackgroundColor(Card card) {
    return card.color == 'red' ? GameConstants.COLOR_RED : GameConstants.COLOR_BLACK;
  }

  /// Get card text color
  static int getCardTextColor(Card card) {
    return 0xFFFFFFFF; // White text
  }

  /// Get card border color
  static int getCardBorderColor(Card card, {bool isSelected = false, bool isPlayable = false}) {
    if (isSelected) {
      return GameConstants.COLOR_GOLD;
    }
    if (isPlayable) {
      return GameConstants.COLOR_SILVER;
    }
    return card.color == 'red' ? GameConstants.COLOR_RED : GameConstants.COLOR_BLACK;
  }

  /// Get card shadow color
  static int getCardShadowColor(Card card) {
    return card.color == 'red' ? GameConstants.COLOR_RED : GameConstants.COLOR_BLACK;
  }

  /// Get card elevation
  static double getCardElevation(Card card, {bool isSelected = false, bool isPlayable = false}) {
    if (isSelected) {
      return 8.0;
    }
    if (isPlayable) {
      return 4.0;
    }
    return 2.0;
  }

  /// Get card scale
  static double getCardScale(Card card, {bool isSelected = false}) {
    return isSelected ? 1.1 : 1.0;
  }

  /// Get card rotation
  static double getCardRotation(Card card, {bool isFaceDown = false}) {
    return isFaceDown ? 180.0 : 0.0;
  }

  /// Check if cards are the same rank
  static bool areSameRank(Card card1, Card card2) {
    return card1.rank == card2.rank;
  }

  /// Check if cards are the same suit
  static bool areSameSuit(Card card1, Card card2) {
    return card1.suit == card2.suit;
  }

  /// Check if cards are the same
  static bool areSameCard(Card card1, Card card2) {
    return card1.rank == card2.rank && card1.suit == card2.suit;
  }

  /// Get card description for accessibility
  static String getCardAccessibilityDescription(Card card) {
    final fullName = getCardFullName(card);
    final points = card.points;
    final specialPower = card.specialPowerDescription;
    
    String description = '$fullName, worth $points points';
    
    if (specialPower != null) {
      description += ', $specialPower';
    }
    
    return description;
  }

  /// Get card tooltip text
  static String getCardTooltipText(Card card) {
    final fullName = getCardFullName(card);
    final points = card.points;
    final specialPower = card.specialPowerDescription;
    
    String tooltip = '$fullName\nPoints: $points';
    
    if (specialPower != null) {
      tooltip += '\nSpecial: $specialPower';
    }
    
    return tooltip;
  }

  /// Get card animation duration
  static Duration getCardAnimationDuration(Card card, {bool isLongAnimation = false}) {
    if (isLongAnimation) {
      return GameConstants.CARD_ANIMATION_DURATION * 2;
    }
    return GameConstants.CARD_ANIMATION_DURATION;
  }

  /// Get card animation curve
  static Curve getCardAnimationCurve(Card card) {
    return Curves.easeInOut;
  }

  /// Check if card is a face card (Jack, Queen, King)
  static bool isFaceCard(Card card) {
    return card.rank == CardRank.jack || 
           card.rank == CardRank.queen || 
           card.rank == CardRank.king;
  }

  /// Check if card is a number card (2-10)
  static bool isNumberCard(Card card) {
    return card.rank.value >= 2 && card.rank.value <= 10;
  }

  /// Check if card is an ace
  static bool isAce(Card card) {
    return card.rank == CardRank.ace;
  }

  /// Get card value for sorting (Ace = 1, Jack = 11, Queen = 12, King = 13)
  static int getCardValue(Card card) {
    return card.rank.value;
  }

  /// Get card display order (for UI layout)
  static int getCardDisplayOrder(Card card) {
    // Sort by suit first, then by rank
    return card.suit.index * 13 + card.rank.value;
  }
} 