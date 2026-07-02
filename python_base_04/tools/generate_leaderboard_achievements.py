#!/usr/bin/env python3
"""Generate leaderboard placement achievements and merge into achievements_config.json."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "core/modules/dutch_game/config/achievements_config.json"
PROGRESSION_PATH = ROOT / "core/modules/dutch_game/config/progression_config.json"

PLACEMENTS = [
    ("first", "1st", "champion"),
    ("second", "2nd", "runner-up"),
    ("third", "3rd", "bronze"),
    ("top_10", "top 10", "top 10"),
    ("top_50", "top 50", "top 50"),
    ("top_100", "top 100", "top 100"),
]

GAME_TYPES = [
    ("classic", "Classic", "classic"),
    ("clear_and_collect", "Clear & Collect", "cc"),
]


def _tier_title(tier: str) -> str:
    return tier.replace("_", " ").title()


def _period_entries(rank_hierarchy: list[str]) -> list[dict]:
    out: list[dict] = []
    for period, period_label in (("monthly", "Monthly"), ("yearly", "Yearly")):
        for gt_key, gt_label, gt_id in GAME_TYPES:
            for tier in rank_hierarchy:
                tier_label = _tier_title(tier)
                for placement, place_label, place_noun in PLACEMENTS:
                    ach_id = f"lb_{period}_{gt_id}_{tier}_{placement}"
                    if placement in ("first", "second", "third"):
                        title = f"{period_label} {tier_label} {place_noun} ({gt_label})"
                        desc = (
                            f"Finish {place_label} on the {period_label.lower()} "
                            f"{gt_label} leaderboard in the {tier_label} tier."
                        )
                    else:
                        title = f"{period_label} {tier_label} {place_label} ({gt_label})"
                        desc = (
                            f"Finish in the {place_label} on the {period_label.lower()} "
                            f"{gt_label} leaderboard in the {tier_label} tier."
                        )
                    out.append(
                        {
                            "id": ach_id,
                            "title": title,
                            "description": desc,
                            "unlock": {
                                "type": "leaderboard_placement",
                                "period": period,
                                "game_type": gt_key,
                                "rank_tier": tier,
                                "placement": placement,
                                "repeatable": True,
                            },
                        }
                    )
    return out


def _alltime_entries() -> list[dict]:
    out: list[dict] = []
    for gt_key, gt_label, gt_id in GAME_TYPES:
        for placement, place_label, place_noun in PLACEMENTS:
            ach_id = f"lb_alltime_{gt_id}_{placement}"
            if placement in ("first", "second", "third"):
                title = f"All-time {place_noun} ({gt_label})"
                desc = f"Reach {place_label} on the all-time {gt_label} leaderboard."
            else:
                title = f"All-time {place_label} ({gt_label})"
                desc = f"Reach the {place_label} on the all-time {gt_label} leaderboard."
            out.append(
                {
                    "id": ach_id,
                    "title": title,
                    "description": desc,
                    "unlock": {
                        "type": "leaderboard_placement",
                        "period": "all_time",
                        "game_type": gt_key,
                        "placement": placement,
                        "repeatable": False,
                    },
                }
            )
    return out


def main() -> None:
    with open(PROGRESSION_PATH, "r", encoding="utf-8") as f:
        progression = json.load(f)
    rank_hierarchy = progression.get("rank_hierarchy") or []
    if not rank_hierarchy:
        raise SystemExit("rank_hierarchy missing from progression_config.json")

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        doc = json.load(f)

    base = [
        a
        for a in (doc.get("achievements") or [])
        if not str(a.get("id", "")).startswith("lb_")
    ]
    generated = _period_entries(rank_hierarchy) + _alltime_entries()
    doc["achievements"] = base + generated

    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Wrote {len(generated)} leaderboard achievements ({len(doc['achievements'])} total)")


if __name__ == "__main__":
    main()
