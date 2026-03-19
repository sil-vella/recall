"""
Tier, rank, and level matcher — single source of truth for subscription tiers,
player rank hierarchy, and game table levels. Aligned with Dart RankMatcher and LevelMatcher.

- Tiers: subscription_tier — promotional = free play (no coin check); regular and premium = both require coin check.
- Rank: player skill rank (beginner..legend); used for matchmaking and AI difficulty.
- Level: game table level (1–4); used for coin fee and display title. Not mapped to rank.
"""

from typing import List, Optional, Tuple

# ---------------------------------------------------------------------------
# Subscription tiers (subscription_tier in user modules.dutch_game)
# ---------------------------------------------------------------------------
TIER_PROMOTIONAL = "promotional"  # Free play: no coin check, no deduction
TIER_REGULAR = "regular"        # Paid: coin check and deduction
TIER_PREMIUM = "premium"        # Paid: coin check and deduction

SUBSCRIPTION_TIERS: Tuple[str, ...] = (TIER_PROMOTIONAL, TIER_REGULAR, TIER_PREMIUM)

# Defaults for new users or missing data (use these instead of hardcoding)
DEFAULT_RANK = "beginner"
DEFAULT_LEVEL = 1


def normalize_tier(tier: Optional[str]) -> str:
    """Normalize tier string (lowercase, strip). Returns empty string if None or invalid."""
    if not tier:
        return ""
    return (tier or "").strip().lower()


def is_free_play_tier(tier: Optional[str]) -> bool:
    """True only if tier is promotional (skip coin check). Regular and premium both require coins."""
    return normalize_tier(tier) == TIER_PROMOTIONAL


def is_valid_tier(tier: Optional[str]) -> bool:
    """True if tier is a known subscription tier."""
    return normalize_tier(tier) in SUBSCRIPTION_TIERS


# ---------------------------------------------------------------------------
# Rank hierarchy (player skill) — same order as Dart RankMatcher.rankHierarchy
# ---------------------------------------------------------------------------
RANK_HIERARCHY: Tuple[str, ...] = (
    "beginner",
    "novice",
    "apprentice",
    "skilled",
    "advanced",
    "expert",
    "veteran",
    "master",
    "elite",
    "legend",
)

RANK_VARIATIONS = {
    "beginner": "beginner",
    "novice": "novice",
    "apprentice": "apprentice",
    "skilled": "skilled",
    "advanced": "advanced",
    "expert": "expert",
    "veteran": "veteran",
    "master": "master",
    "elite": "elite",
    "legend": "legend",
}


def normalize_rank(rank: Optional[str]) -> str:
    """Normalize rank string (lowercase, trim). Returns empty string if invalid."""
    if not rank:
        return ""
    n = (rank or "").strip().lower()
    if n in RANK_HIERARCHY:
        return n
    return RANK_VARIATIONS.get(n, "")


def get_rank_index(rank: Optional[str]) -> int:
    """Index in RANK_HIERARCHY (0..9). Returns -1 if not found."""
    n = normalize_rank(rank)
    if not n:
        return -1
    try:
        return RANK_HIERARCHY.index(n)
    except ValueError:
        return -1


def are_ranks_compatible(rank1: Optional[str], rank2: Optional[str]) -> bool:
    """True if both ranks are valid and within ±1 in hierarchy (same as Dart)."""
    i1 = get_rank_index(rank1)
    i2 = get_rank_index(rank2)
    if i1 == -1 or i2 == -1:
        return False
    return abs(i1 - i2) <= 1


def get_compatible_ranks(rank: Optional[str]) -> List[str]:
    """Ranks within ±1 of the given rank (including itself). Empty if invalid."""
    idx = get_rank_index(rank)
    if idx == -1:
        return []
    out: List[str] = []
    if idx > 0:
        out.append(RANK_HIERARCHY[idx - 1])
    out.append(RANK_HIERARCHY[idx])
    if idx < len(RANK_HIERARCHY) - 1:
        out.append(RANK_HIERARCHY[idx + 1])
    return out


def is_valid_rank(rank: Optional[str]) -> bool:
    """True if rank is in RANK_HIERARCHY."""
    return get_rank_index(rank) != -1


def rank_to_difficulty(rank: Optional[str], default: str = "medium") -> str:
    """Map player rank to YAML difficulty for computer AI. Returns easy|medium|hard|expert (same as Dart)."""
    n = normalize_rank(rank)
    if not n:
        return default
    if n == "beginner":
        return "easy"
    if n in ("novice", "apprentice"):
        return "medium"
    if n in ("skilled", "advanced", "expert"):
        return "hard"
    if n in ("veteran", "master", "elite", "legend"):
        return "expert"
    return default


# ---------------------------------------------------------------------------
# Game **table** tier (1–4) — room `game_level` / LevelMatcher; not user progression
#
# Coin entry fees are tied to the table only (1→25, 2→50, 3→100, 4→200).
# User progression “level” in `modules.dutch_game` is separate; it only gates which
# tables you may join (see WinsLevelRankMatcher.user_may_join_game_table).
# ---------------------------------------------------------------------------
LEVEL_TO_TITLE = {
    1: "Home Table",
    2: "Local Table",
    3: "Town Table",
    4: "City Table",
}

LEVEL_TO_COIN_FEE = {
    1: 25,
    2: 50,
    3: 100,
    4: 200,
}

LEVEL_ORDER: Tuple[int, ...] = (1, 2, 3, 4)


def level_to_title(level: Optional[int], default_title: Optional[str] = None) -> str:
    """Display title for level (1–4). Returns default_title or '' if invalid."""
    if level is None:
        return default_title or ""
    return LEVEL_TO_TITLE.get(level, default_title or "")


def title_to_level(title: Optional[str]) -> Optional[int]:
    """Level number for title (case-insensitive). Returns None if not found."""
    if not title:
        return None
    t = (title or "").strip().lower()
    for lvl, name in LEVEL_TO_TITLE.items():
        if name.lower() == t:
            return lvl
    return None


def level_to_coin_fee(level: Optional[int], default_fee: Optional[int] = None) -> int:
    """Coin fee for game **table** tier (1–4). Returns default_fee or 0 if invalid."""
    if level is None:
        return default_fee if default_fee is not None else 0
    return LEVEL_TO_COIN_FEE.get(level, default_fee if default_fee is not None else 0)


def table_level_to_coin_fee(table_level: Optional[int], default_fee: Optional[int] = None) -> int:
    """Alias: entry cost for room **table** tier (1–4), not user profile progression level."""
    return level_to_coin_fee(table_level, default_fee=default_fee)


def is_valid_level(level: Optional[int]) -> bool:
    """True if level is 1–4."""
    return level is not None and level in LEVEL_TO_TITLE
