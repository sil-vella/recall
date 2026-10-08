#!/usr/bin/env python3
"""
Seed modules.dutch_game.mastery from wins and lifetime winner points.

Estimate (halved live formula):

    (404 * wins - 10 * points - min_cards) // 2

``min_cards`` is 0 when lifetime points are 0 (empty hands). Otherwise it is
the fewest cards that can total those points, at most 10 each and at most 4
per win. Losses are not included.

Re-running replaces a stored mastery only when it is still 0 or still equal to
the previous zero-card seed. Any other value is left alone.

Local Docker MongoDB only.

Usage (from repo root):
  python3 playbooks/00_local/backfill_mastery_from_wins_points.py
  python3 playbooks/00_local/backfill_mastery_from_wins_points.py --humans-only
  python3 playbooks/00_local/backfill_mastery_from_wins_points.py --humans-only --apply

Reads MONGODB_PASSWORD from .env.local or the environment.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_BASE = REPO_ROOT / "python_base_04"
DEFAULT_CONTAINER = "dutch_external_app_mongodb"
MONGODB_USER = "external_app_user"
MONGODB_AUTH_DB = "external_system"

sys.path.insert(0, str(PYTHON_BASE))
from core.modules.dutch_game.mastery import estimated_mastery_from_wins_and_points  # noqa: E402


def _load_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip().strip('"').strip("'")
        out[key] = value
    return out


def _mongosh(password: str, js: str, *, container: str) -> str:
    cmd = [
        "docker",
        "exec",
        container,
        "mongosh",
        "-u",
        MONGODB_USER,
        "-p",
        password,
        "--authenticationDatabase",
        MONGODB_AUTH_DB,
        "--quiet",
        "--eval",
        js,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"mongosh failed (exit {result.returncode}): {result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout.strip()


def _fetch_users(password: str, *, container: str, humans_only: bool) -> list[dict]:
    human_match = (
        ", is_comp_player: { $ne: true }"
        if humans_only
        else ""
    )
    js = f"""
var d = db.getSiblingDB('external_system');
var cur = d.users.find(
  {{ 'modules.dutch_game': {{ $exists: true }}{human_match} }},
  {{
    _id: 1,
    is_comp_player: 1,
    'modules.dutch_game.wins': 1,
    'modules.dutch_game.points': 1,
    'modules.dutch_game.mastery': 1
  }}
);
var rows = [];
cur.forEach(function(u) {{
  var dg = (u.modules && u.modules.dutch_game) ? u.modules.dutch_game : {{}};
  function num(v) {{
    var n = typeof v === 'number' ? v : parseInt(v, 10);
    return isNaN(n) ? 0 : n;
  }}
  rows.push({{
    id: u._id.valueOf(),
    wins: num(dg.wins),
    points: num(dg.points),
    mastery: num(dg.mastery),
    is_comp_player: !!u.is_comp_player
  }});
}});
print(JSON.stringify(rows));
"""
    raw = _mongosh(password, js, container=container)
    line = next((ln for ln in raw.splitlines() if ln.startswith("[")), raw)
    if not line:
        return []
    return json.loads(line)


def _apply(password: str, updates: list[dict], *, container: str) -> int:
    if not updates:
        return 0
    payload = json.dumps(updates)
    # Missing mastery must match previous===0 (Mongo {field:0} does not match missing).
    js = f"""
var d = db.getSiblingDB('external_system');
var updates = {payload};
var nowIso = new Date().toISOString();
var changed = 0;
var skipped = 0;
updates.forEach(function(row) {{
  var masteryFilter = row.previous === 0
    ? {{ $or: [
        {{ 'modules.dutch_game.mastery': {{ $exists: false }} }},
        {{ 'modules.dutch_game.mastery': null }},
        {{ 'modules.dutch_game.mastery': 0 }}
      ] }}
    : {{ 'modules.dutch_game.mastery': row.previous }};
  var filter = Object.assign({{ _id: ObjectId(row.id) }}, masteryFilter);
  var res = d.users.updateOne(
    filter,
    {{ $set: {{
      'modules.dutch_game.mastery': row.mastery,
      'modules.dutch_game.last_updated': nowIso,
      updated_at: nowIso
    }} }}
  );
  if (res.modifiedCount > 0) changed += 1;
  else skipped += 1;
}});
print(JSON.stringify({{ updated: changed, skipped: skipped, candidates: updates.length }}));
"""
    raw = _mongosh(password, js, container=container)
    line = next((ln for ln in raw.splitlines() if ln.startswith("{")), raw)
    data = json.loads(line)
    return int(data.get("updated", 0))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write mastery on local MongoDB (default: dry-run only)",
    )
    parser.add_argument(
        "--humans-only",
        action="store_true",
        help="Skip computer players (is_comp_player != true)",
    )
    parser.add_argument(
        "--container",
        default=DEFAULT_CONTAINER,
        help="Local Docker MongoDB container name",
    )
    args = parser.parse_args()

    env = _load_env_file(REPO_ROOT / ".env.local")
    password = os.environ.get("MONGODB_PASSWORD") or env.get("MONGODB_PASSWORD", "")
    if not password:
        print("ERROR: MONGODB_PASSWORD not set (.env.local or env)", file=sys.stderr)
        return 1

    container = (os.environ.get("MONGODB_CONTAINER") or args.container).strip()
    users = _fetch_users(password, container=container, humans_only=args.humans_only)
    updates = []
    skipped_live = 0
    skipped_same = 0
    skipped_zero = 0
    for row in users:
        wins = int(row.get("wins") or 0)
        points = int(row.get("points") or 0)
        current = int(row.get("mastery") or 0)
        seed = estimated_mastery_from_wins_and_points(wins, points)
        if points <= 0:
            card_penalty = 0
        else:
            card_penalty = min(4 * max(wins, 0), (points + 9) // 10)
        empty_full = 404 * max(wins, 0) - 10 * max(points, 0)
        previous_seed = 0 if empty_full < 0 else empty_full // 2
        if seed == current:
            skipped_same += 1
            continue
        if current not in (0, previous_seed):
            skipped_live += 1
            continue
        if seed <= 0:
            skipped_zero += 1
            continue
        updates.append(
            {
                "id": row["id"],
                "mastery": seed,
                "previous": current,
                "wins": wins,
                "points": points,
                "cards": card_penalty,
            }
        )

    scope = "humans-only" if args.humans_only else "all-users"
    print(
        f"scope={scope} users={len(users)} to_update={len(updates)} "
        f"unchanged={skipped_same} left_live={skipped_live} stays_zero={skipped_zero}"
    )
    for row in updates[:8]:
        tail = str(row["id"])[-6:]
        print(
            f"  …{tail} wins={row['wins']} points={row['points']} "
            f"cards={row['cards']} {row['previous']} -> {row['mastery']}"
        )
    if len(updates) > 8:
        print(f"  … {len(updates) - 8} more")

    if not args.apply:
        print("Dry-run only. Re-run with --apply to write local MongoDB.")
        return 0

    changed = _apply(
        password,
        [{"id": u["id"], "mastery": u["mastery"], "previous": u["previous"]} for u in updates],
        container=container,
    )
    print(f"updated={changed}")
    if changed != len(updates):
        print(
            f"WARNING: expected {len(updates)} updates, got {changed}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
