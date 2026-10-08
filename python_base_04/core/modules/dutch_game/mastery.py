"""Per-match mastery from leftover points, then leftover cards.

The match still ranks an empty hand above a two-card finish. Mastery does not:
holding both jokers (0 points, 2 cards — the only 0-point cards in the deck)
is the top skill finish.
"""

from __future__ import annotations

# Starting hand is 4 cards; the heaviest rank is 10.
POINT_CAP: int = 40
CARD_CAP: int = 4
POINT_WEIGHT: int = 10
# Integer half of the full-scale awards so lifetime totals stay smaller.
SCALE_DIVISOR: int = 2
# Full-scale both-jokers award is 504; stored award is 504 // 2.
BOTH_JOKERS_FULL: int = 504


def match_mastery_delta(end_points: int, end_cards: int) -> int:
    """Mastery added for one player's finish. Never negative.

    Full scale is ``(40 - points) * 10 + (4 - cards)``, then integer-divided by 2.
    ``0`` points and ``2`` cards is both jokers and uses 504 before that divide (252).
    Points are capped at 40 and cards at 4.
    """
    try:
        points = int(end_points)
    except (TypeError, ValueError):
        points = 0
    try:
        cards = int(end_cards)
    except (TypeError, ValueError):
        cards = 0
    points = max(0, points)
    cards = max(0, cards)
    if points == 0 and cards == 2:
        raw = BOTH_JOKERS_FULL
    else:
        clamped_points = min(points, POINT_CAP)
        clamped_cards = min(cards, CARD_CAP)
        raw = (POINT_CAP - clamped_points) * POINT_WEIGHT + (CARD_CAP - clamped_cards)
    return raw // SCALE_DIVISOR


def estimated_mastery_from_wins_and_points(wins: int, lifetime_points: int) -> int:
    """Inaccurate seed from stored wins and the winner end-points sum.

    Points already scored are subtracted (10 per point on the full scale).
    A points total of 0 is treated as empty hands (0 cards). A points total
    above 0 cannot be an empty hand, so the seed also subtracts the fewest
    cards that can add up to those points (each card at most 10, at most 4
    per win). Losses are ignored. The same integer half as
    ``match_mastery_delta`` is applied. Result is never negative.
    """
    try:
        win_count = int(wins)
    except (TypeError, ValueError):
        win_count = 0
    try:
        points = int(lifetime_points)
    except (TypeError, ValueError):
        points = 0
    win_count = max(0, win_count)
    points = max(0, points)
    if win_count == 0:
        return 0
    if points <= 0:
        card_penalty = 0
    else:
        min_cards = (points + POINT_WEIGHT - 1) // POINT_WEIGHT
        card_penalty = min(CARD_CAP * win_count, min_cards)
    empty_hand_full = POINT_CAP * POINT_WEIGHT + CARD_CAP
    raw = empty_hand_full * win_count - POINT_WEIGHT * points - card_penalty
    if raw < 0:
        return 0
    return raw // SCALE_DIVISOR
