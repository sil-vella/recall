#!/usr/bin/env python3
"""
Recompute modules.dutch_game.level and .rank from existing wins (progression_config SSOT).

Does not change wins or other stats.

Usage (from repo root):
  # Local Docker MongoDB (default)
  python3 playbooks/00_local/backfill_progression_from_wins.py
  python3 playbooks/00_local/backfill_progression_from_wins.py --apply

  # VPS (SSH + docker mongosh; dry-run by default)
  python3 playbooks/00_local/backfill_progression_from_wins.py --target vps
  python3 playbooks/00_local/backfill_progression_from_wins.py --target vps --apply

Reads MONGODB_PASSWORD from .env.local (local) or .env.prod (vps), or env.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_BASE = REPO_ROOT / "python_base_04"
DEFAULT_CONTAINER = "dutch_external_app_mongodb"
DEFAULT_USER_ID = "69aae0b0095ba0c771e43091"
DEFAULT_SSH_USER = "rop01_user"
DEFAULT_SSH_HOST = "65.181.125.135"
DEFAULT_SSH_KEY = os.path.expanduser("~/.ssh/rop01_key")
MONGODB_USER = "external_app_user"
MONGODB_AUTH_DB = "external_system"


def _load_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not m:
            continue
        k, v = m.group(1), m.group(2).strip().strip('"').strip("'")
        out[k] = v
    return out


def _compute_level_rank(wins: int) -> tuple[int, str]:
    sys.path.insert(0, str(PYTHON_BASE))
    from core.modules.dutch_game.wins_level_rank_matcher import WinsLevelRankMatcher as W

    level = W.wins_to_user_level(wins)
    rank = W.user_level_to_rank(level)
    return level, rank


def _mongosh_local(password: str, js: str, *, container: str) -> str:
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


def _mongosh_vps(password: str, js: str, ssh_user: str, ssh_host: str, ssh_key: str) -> str:
    token = uuid.uuid4().hex[:12]
    remote_name = f"backfill_progression_{token}.js"
    remote_host_path = f"/tmp/{remote_name}"
    container_path = f"/tmp/{remote_name}"

    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as tmp:
        tmp.write(js)
        local_path = tmp.name

    try:
        scp = subprocess.run(
            ["scp", "-i", ssh_key, local_path, f"{ssh_user}@{ssh_host}:{remote_host_path}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if scp.returncode != 0:
            raise RuntimeError(f"scp failed: {scp.stderr.strip() or scp.stdout.strip()}")

        remote_cmd = (
            f'docker cp {remote_host_path} {DEFAULT_CONTAINER}:{container_path} && '
            f'docker exec {DEFAULT_CONTAINER} mongosh -u {MONGODB_USER} -p "{password}" '
            f'--authenticationDatabase {MONGODB_AUTH_DB} --quiet {container_path} && '
            f'rm -f {remote_host_path}'
        )
        ssh = subprocess.run(
            ["ssh", "-i", ssh_key, f"{ssh_user}@{ssh_host}", remote_cmd],
            capture_output=True,
            text=True,
            check=False,
        )
        if ssh.returncode != 0:
            raise RuntimeError(f"ssh mongosh failed: {ssh.stderr.strip() or ssh.stdout.strip()}")
        return ssh.stdout.strip()
    finally:
        Path(local_path).unlink(missing_ok=True)


def _mongosh_eval(
    password: str,
    js: str,
    *,
    target: str,
    container: str,
    ssh_user: str,
    ssh_host: str,
    ssh_key: str,
) -> str:
    if target == "vps":
        return _mongosh_vps(password, js, ssh_user, ssh_host, ssh_key)
    return _mongosh_local(password, js, container=container)


def _fetch_users(
    password: str,
    user_id: str | None,
    *,
    target: str,
    container: str,
    ssh_user: str,
    ssh_host: str,
    ssh_key: str,
) -> list[dict]:
    filter_js = (
        f"{{ _id: ObjectId('{user_id}') }}"
        if user_id
        else "{ 'modules.dutch_game.wins': { $exists: true } }"
    )
    js = f"""
var d = db.getSiblingDB('external_system');
var cur = d.users.find(
  {filter_js},
  {{ _id: 1, 'modules.dutch_game.wins': 1, 'modules.dutch_game.level': 1, 'modules.dutch_game.rank': 1 }}
);
var rows = [];
cur.forEach(function(u) {{
  var dg = (u.modules && u.modules.dutch_game) ? u.modules.dutch_game : {{}};
  var wins = typeof dg.wins === 'number' ? dg.wins : parseInt(dg.wins, 10);
  if (isNaN(wins)) wins = 0;
  rows.push({{
    id: u._id.valueOf(),
    wins: wins,
    level: dg.level,
    rank: dg.rank
  }});
}});
print(JSON.stringify(rows));
"""
    raw = _mongosh_eval(
        password,
        js,
        target=target,
        container=container,
        ssh_user=ssh_user,
        ssh_host=ssh_host,
        ssh_key=ssh_key,
    )
    line = next((ln for ln in raw.splitlines() if ln.startswith("[")), raw)
    if not line:
        return []
    return json.loads(line)


def _apply_updates(
    password: str,
    updates: list[dict],
    *,
    target: str,
    container: str,
    ssh_user: str,
    ssh_host: str,
    ssh_key: str,
) -> int:
    if not updates:
        return 0
    payload = json.dumps(updates)
    js = f"""
var d = db.getSiblingDB('external_system');
var updates = {payload};
var nowIso = new Date().toISOString();
var changed = 0;
updates.forEach(function(row) {{
  var res = d.users.updateOne(
    {{ _id: ObjectId(row.id) }},
    {{ $set: {{
      'modules.dutch_game.level': row.level,
      'modules.dutch_game.rank': row.rank,
      'modules.dutch_game.last_updated': nowIso,
      updated_at: nowIso
    }} }}
  );
  if (res.modifiedCount > 0) changed += 1;
}});
print(JSON.stringify({{ updated: changed, candidates: updates.length }}));
"""
    raw = _mongosh_eval(
        password,
        js,
        target=target,
        container=container,
        ssh_user=ssh_user,
        ssh_host=ssh_host,
        ssh_key=ssh_key,
    )
    line = next((ln for ln in raw.splitlines() if ln.startswith("{")), raw)
    data = json.loads(line)
    return int(data.get("updated", 0))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write level/rank to MongoDB (default: dry-run only)",
    )
    parser.add_argument(
        "--user-id",
        default=None,
        help=f"Single user ObjectId (default: all users with dutch_game.wins). Dev default: {DEFAULT_USER_ID}",
    )
    parser.add_argument(
        "--limit-sample",
        type=int,
        default=5,
        help="Max mismatch rows to print in dry-run (id suffix only)",
    )
    parser.add_argument(
        "--inject-stale-for-test",
        action="store_true",
        help="LOCAL TEST ONLY: set level=99 rank=legend on --user-id before backfill (requires --user-id and --apply)",
    )
    parser.add_argument(
        "--target",
        choices=("local", "vps"),
        default="local",
        help="MongoDB target: local Docker or VPS via SSH (default: local)",
    )
    parser.add_argument("--ssh-user", default=DEFAULT_SSH_USER)
    parser.add_argument("--ssh-host", default=DEFAULT_SSH_HOST)
    parser.add_argument("--ssh-key", default=DEFAULT_SSH_KEY)
    parser.add_argument(
        "--container",
        default=DEFAULT_CONTAINER,
        help="Local Docker MongoDB container name or id (default: dutch_external_app_mongodb)",
    )
    args = parser.parse_args()

    env_file = REPO_ROOT / (".env.prod" if args.target == "vps" else ".env.local")
    env = _load_env_file(env_file)
    password = os.environ.get("MONGODB_PASSWORD") or env.get("MONGODB_PASSWORD", "")
    ssh_user = os.environ.get("VPS_SSH_USER") or env.get("VPS_SSH_USER") or args.ssh_user
    ssh_host = os.environ.get("VPS_SSH_HOST") or env.get("VPS_SSH_HOST") or args.ssh_host
    ssh_key = os.path.expanduser(
        os.environ.get("VPS_SSH_KEY") or env.get("VPS_SSH_KEY") or args.ssh_key
    )

    if not password:
        print(f"ERROR: MONGODB_PASSWORD not set ({env_file.name} or env)", file=sys.stderr)
        return 1
    if args.target == "vps" and not Path(ssh_key).is_file():
        print(f"ERROR: SSH key not found: {ssh_key}", file=sys.stderr)
        return 1

    container = (os.environ.get("MONGODB_CONTAINER") or args.container).strip()
    mongo_kw = dict(
        target=args.target,
        container=container,
        ssh_user=ssh_user,
        ssh_host=ssh_host,
        ssh_key=ssh_key,
    )

    user_id = args.user_id
    if args.inject_stale_for_test:
        if args.target != "local":
            print("ERROR: --inject-stale-for-test is local-only", file=sys.stderr)
            return 1
        if not args.apply or not user_id:
            print("ERROR: --inject-stale-for-test requires --apply and --user-id", file=sys.stderr)
            return 1
        _mongosh_eval(
            password,
            f"""
var d = db.getSiblingDB('external_system');
var res = d.users.updateOne(
  {{ _id: ObjectId('{user_id}') }},
  {{ $set: {{ 'modules.dutch_game.level': 99, 'modules.dutch_game.rank': 'legend' }} }}
);
if (res.matchedCount === 0) {{ print('NOT_FOUND'); quit(1); }}
print('injected_stale=1');
""",
            **mongo_kw,
        )
        print(f"injected stale level=99 rank=legend for ...{user_id[-6:]}")

    users = _fetch_users(password, user_id, **mongo_kw)

    mismatches: list[dict] = []
    for row in users:
        wins = int(row.get("wins") or 0)
        target_level, target_rank = _compute_level_rank(wins)
        stored_level = row.get("level")
        stored_rank = row.get("rank")
        try:
            stored_level_i = int(stored_level) if stored_level is not None else None
        except (TypeError, ValueError):
            stored_level_i = None
        stored_rank_s = str(stored_rank).strip() if stored_rank is not None else None

        needs = stored_level_i != target_level or stored_rank_s != target_rank
        if needs:
            mismatches.append(
                {
                    "id": row["id"],
                    "wins": wins,
                    "level_before": stored_level_i,
                    "rank_before": stored_rank_s,
                    "level": target_level,
                    "rank": target_rank,
                }
            )

    mode = "APPLY" if args.apply else "DRY-RUN"
    container_label = container if args.target == "local" else args.target
    print(
        f"[{mode}] target={args.target} container={container_label} "
        f"users_scanned={len(users)} mismatches={len(mismatches)}"
    )

    for i, m in enumerate(mismatches[: max(0, args.limit_sample)]):
        uid = m["id"]
        suffix = uid[-6:] if len(uid) >= 6 else uid
        print(
            f"  sample[{i}] ...{suffix} wins={m['wins']} "
            f"level {m['level_before']}->{m['level']} rank {m['rank_before']!r}->{m['rank']!r}"
        )
    if len(mismatches) > args.limit_sample:
        print(f"  ... and {len(mismatches) - args.limit_sample} more")

    if not args.apply:
        if mismatches:
            print("Re-run with --apply to write level/rank (wins unchanged).")
        return 0

    to_write = [{"id": m["id"], "level": m["level"], "rank": m["rank"]} for m in mismatches]
    updated = _apply_updates(password, to_write, **mongo_kw)
    print(f"updated_documents={updated}")

    if user_id and mismatches:
        after = _fetch_users(password, user_id, **mongo_kw)
        if after:
            a = after[0]
            lvl, rk = _compute_level_rank(int(a.get("wins") or 0))
            ok = int(a.get("level") or -1) == lvl and str(a.get("rank") or "") == rk
            print(f"verify_user ...{user_id[-6:]} ok={ok} level={a.get('level')} rank={a.get('rank')}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
