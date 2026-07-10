#!/usr/bin/env python3
"""
Re-align comp_players.json entries with progression_config.json (SSOT).

Keeps each player's stored rank; assigns a valid user level within that rank's
span and sets wins to the minimum lifetime wins for that level.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

_REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO_ROOT / "python_base_04"))

from core.modules.dutch_game.progression_catalog import (  # noqa: E402
    CUMULATIVE_WINS_FOR_USER_LEVEL,
    LEVELS_PER_RANK_BY_RANK,
    LEVELS_PER_RANK_MAP,
    RANK_HIERARCHY,
    user_level_to_rank,
    wins_to_user_level_from_catalog,
)


def _rank_title(rank: str) -> str:
    return (rank or "beginner").strip().lower().capitalize()


def rank_level_range(rank: str) -> Tuple[int, int]:
    normalized = (rank or "").strip().lower()
    if normalized not in RANK_HIERARCHY:
        normalized = "beginner"
    idx = RANK_HIERARCHY.index(normalized)
    level_min = 1 + sum(LEVELS_PER_RANK_BY_RANK[:idx])
    span = LEVELS_PER_RANK_MAP[normalized]
    level_max = level_min + span - 1
    return level_min, level_max


def align_level_for_rank(old_level: int, rank: str) -> int:
    """Map prior level into a valid level for the kept rank (spread across span)."""
    level_min, level_max = rank_level_range(rank)
    span = level_max - level_min + 1
    try:
        lv = int(old_level)
    except (TypeError, ValueError):
        lv = level_min
    offset = (max(1, lv) - 1) % span
    return level_min + offset


def wins_for_user_level(level: int) -> int:
    return int(CUMULATIVE_WINS_FOR_USER_LEVEL[max(0, level - 1)])


def regen_players(players: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for player in players:
        updated = dict(player)
        rank_raw = str(player.get("rank", "beginner"))
        rank_norm = rank_raw.strip().lower()
        if rank_norm not in RANK_HIERARCHY:
            rank_norm = "beginner"

        old_level = player.get("level", 1)
        new_level = align_level_for_rank(old_level, rank_norm)
        new_wins = wins_for_user_level(new_level)

        updated["rank"] = _rank_title(rank_norm)
        updated["level"] = new_level
        updated["wins"] = new_wins
        out.append(updated)
    return out


def validate_players(players: List[Dict[str, Any]]) -> List[str]:
    errors: List[str] = []
    for player in players:
        username = player.get("username", "?")
        level = int(player.get("level", 0))
        rank = str(player.get("rank", "")).lower()
        wins = int(player.get("wins", -1))
        expected_rank = user_level_to_rank(level)
        if rank != expected_rank:
            errors.append(
                f"{username}: level {level} rank {rank!r} != expected {expected_rank!r}"
            )
        if wins_to_user_level_from_catalog(wins) != level:
            errors.append(
                f"{username}: wins {wins} -> level {wins_to_user_level_from_catalog(wins)}, expected {level}"
            )
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description="Regen comp_players.json for progression SSOT")
    parser.add_argument("json_file", type=Path, help="Path to comp_players.json")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate only; do not write file",
    )
    args = parser.parse_args()

    path = args.json_file.resolve()
    if not path.is_file():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    with open(path, encoding="utf-8") as f:
        players = json.load(f)

    if not isinstance(players, list):
        print("JSON root must be an array", file=sys.stderr)
        sys.exit(1)

    regenned = regen_players(players)
    errors = validate_players(regenned)
    if errors:
        print("Validation failed:", file=sys.stderr)
        for err in errors[:20]:
            print(f"  {err}", file=sys.stderr)
        sys.exit(1)

    levels = [int(p["level"]) for p in regenned]
    print(f"{path.name}: {len(regenned)} players")
    print(f"  level range: {min(levels)} - {max(levels)}")
    print(f"  wins range: {min(int(p['wins']) for p in regenned)} - {max(int(p['wins']) for p in regenned)}")

    if args.dry_run:
        print("  dry-run: no file written")
        return

    with open(path, "w", encoding="utf-8") as f:
        json.dump(regenned, f, indent=2)
        f.write("\n")

    print(f"  wrote {path}")


if __name__ == "__main__":
    main()
