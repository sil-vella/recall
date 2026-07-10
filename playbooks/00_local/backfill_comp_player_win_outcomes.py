#!/usr/bin/env python3
"""
Backfill dutch_match_win_outcomes for comp players from modules.dutch_game.wins.

Leaderboard APIs aggregate period wins from dutch_match_win_outcomes (not user.wins).
Use after seeding comp players so monthly/yearly/all-time boards show entries.

Usage:
  python3 playbooks/00_local/backfill_comp_player_win_outcomes.py
  python3 playbooks/00_local/backfill_comp_player_win_outcomes.py --apply
  python3 playbooks/00_local/backfill_comp_player_win_outcomes.py --target vps --apply
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTAINER = "dutch_external_app_mongodb"
MONGODB_USER = "external_app_user"
MONGODB_AUTH_DB = "external_system"
DEFAULT_SSH_USER = "rop01_user"
DEFAULT_SSH_HOST = "65.181.125.135"
DEFAULT_SSH_KEY = os.path.expanduser("~/.ssh/rop01_key")
ROOM_PREFIX = "backfill_cp_"
BATCH_SIZE = 2000


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


def _resolve_password(target: str) -> str:
    names = (".env.prod", ".env", ".env.local") if target == "vps" else (".env", ".env.local", ".env.prod")
    for name in names:
        env = _load_env_file(REPO_ROOT / name)
        if env.get("MONGODB_PASSWORD"):
            return env["MONGODB_PASSWORD"]
    return os.environ.get("MONGODB_PASSWORD", "6R3jjsvVhIRP20zMiHdkBzNKx")


class MongoRunner:
    def __init__(
        self,
        *,
        target: str,
        container: str,
        password: str,
        ssh_user: str,
        ssh_host: str,
        ssh_key: str,
    ) -> None:
        self.target = target
        self.container = container
        self.password = password
        self.ssh_user = ssh_user
        self.ssh_host = ssh_host
        self.ssh_key = ssh_key
        self.use_auth = True
        if target == "local":
            self.use_auth = self._local_auth_works()

    def _local_auth_works(self) -> bool:
        try:
            self._local_mongosh('db.getSiblingDB("external_system").getName()', use_auth=True)
            return True
        except RuntimeError:
            return False

    def _mongosh_auth_args(self) -> list[str]:
        if not self.use_auth or not self.password:
            return []
        return [
            "-u",
            MONGODB_USER,
            "-p",
            self.password,
            "--authenticationDatabase",
            MONGODB_AUTH_DB,
        ]

    def _local_mongosh(self, js: str, *, use_auth: bool | None = None) -> str:
        auth = self.use_auth if use_auth is None else use_auth
        cmd = ["docker", "exec", self.container, "mongosh", "--quiet"]
        if auth and self.password:
            cmd.extend(self._mongosh_auth_args())
        cmd.extend(["--eval", js])
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout.strip()

    def _local_mongosh_file(self, container_js_path: str) -> str:
        cmd = ["docker", "exec", self.container, "mongosh", "--quiet", *self._mongosh_auth_args(), container_js_path]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout.strip()

    def _ssh(self, remote_cmd: str) -> str:
        cmd = ["ssh", "-i", self.ssh_key, f"{self.ssh_user}@{self.ssh_host}", remote_cmd]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout.strip()

    def _scp_to_host(self, local_path: str, host_path: str) -> None:
        subprocess.run(
            ["scp", "-i", self.ssh_key, local_path, f"{self.ssh_user}@{self.ssh_host}:{host_path}"],
            check=True,
            capture_output=True,
            text=True,
        )

    def eval_js(self, js: str) -> str:
        if self.target == "local":
            return self._local_mongosh(js)
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as jf:
            jf.write(js)
            local_js = jf.name
        try:
            container_js = f"/tmp/backfill_cp_eval_{Path(local_js).name}.js"
            return self.run_js_file_in_container(local_js, container_js)
        finally:
            Path(local_js).unlink(missing_ok=True)

    def run_js_file_in_container(self, local_js_path: str, container_js_path: str) -> str:
        if self.target == "local":
            subprocess.run(
                ["docker", "cp", local_js_path, f"{self.container}:{container_js_path}"],
                check=True,
            )
            return self._local_mongosh_file(container_js_path)

        host_js = f"/tmp/{Path(container_js_path).name}"
        self._scp_to_host(local_js_path, host_js)
        self._ssh(f"docker cp {host_js} {self.container}:{container_js_path}")
        remote = (
            f'docker exec {self.container} mongosh --quiet '
            f'{" ".join(self._mongosh_auth_args())} {container_js_path}'
        )
        return self._ssh(remote)

    def copy_into_container(self, local_path: str, container_path: str) -> None:
        if self.target == "local":
            subprocess.run(["docker", "cp", local_path, f"{self.container}:{container_path}"], check=True)
            return
        host_path = f"/tmp/{Path(container_path).name}"
        self._scp_to_host(local_path, host_path)
        self._ssh(f"docker cp {host_path} {self.container}:{container_path}")


def _fetch_comp_players(runner: MongoRunner) -> list[dict]:
    js = """
var d = db.getSiblingDB('external_system');
var rows = [];
d.users.find(
  { is_comp_player: true, 'modules.dutch_game.wins': { $gt: 0 } },
  { _id: 1, username: 1, 'modules.dutch_game.wins': 1 }
).forEach(function(u) {
  rows.push({
    _id: u._id.valueOf(),
    username: u.username || '',
    wins: (u.modules && u.modules.dutch_game && u.modules.dutch_game.wins) || 0
  });
});
print(JSON.stringify(rows));
"""
    out = runner.eval_js(js)
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("["):
            return json.loads(line)
    return []


def _ended_at_for_index(index: int, total: int, now: datetime) -> datetime:
    if total <= 1:
        days_ago = 0
    else:
        recent_slots = max(1, int(total * 0.4))
        if index < recent_slots:
            day_slot = index / max(1, recent_slots - 1) if recent_slots > 1 else 0
            days_ago = int(day_slot * 29)
        else:
            rem = total - recent_slots
            rem_idx = index - recent_slots
            day_slot = rem_idx / max(1, rem - 1) if rem > 1 else 0
            days_ago = 30 + int(day_slot * 335)
    base = now - timedelta(days=days_ago)
    seconds = (index * 97) % 86400
    return base.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(seconds=seconds)


def _build_docs(players: list[dict], now: datetime) -> list[dict[str, Any]]:
    docs: list[dict[str, Any]] = []
    for player in players:
        uid = player["_id"]
        username = re.sub(r"[^a-zA-Z0-9._-]", "_", player.get("username") or "comp")
        wins = int(player.get("wins") or 0)
        for i in range(wins):
            ended = _ended_at_for_index(i, wins, now)
            docs.append(
                {
                    "room_id": f"{ROOM_PREFIX}{username}_{i}",
                    "user_id": {"$oid": uid},
                    "ended_at": {"$date": ended.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"},
                    "is_tournament": False,
                    "tournament_id": None,
                    "game_mode": None,
                    "game_type": "classic",
                    "end_points": 8 + (i % 13),
                    "duration_seconds": 60 + (i % 240),
                }
            )
    return docs


def _apply_batches(docs: list[dict[str, Any]], runner: MongoRunner) -> None:
    setup_js = f"""
var d = db.getSiblingDB("external_system");
var coll = d.dutch_match_win_outcomes;
coll.createIndex({{ ended_at: 1 }});
coll.createIndex({{ room_id: 1, user_id: 1 }}, {{ unique: true, name: "room_user_unique" }});
var removed = coll.deleteMany({{ room_id: {{ $regex: "^{ROOM_PREFIX}" }} }}).deletedCount;
print("Removed prior backfill rows: " + removed);
"""
    print(runner.eval_js(setup_js))

    total_batches = (len(docs) + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_idx in range(0, len(docs), BATCH_SIZE):
        batch = docs[batch_idx : batch_idx + BATCH_SIZE]
        batch_num = batch_idx // BATCH_SIZE + 1
        json_path = js_path = None
        try:
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as jf:
                json.dump(batch, jf, separators=(",", ":"))
                json_path = jf.name

            container_json = f"/tmp/backfill_cp_batch_{batch_num}.json"
            container_js = f"/tmp/backfill_cp_batch_{batch_num}.js"
            runner.copy_into_container(json_path, container_json)

            js_body = f"""
const fs = require('fs');
var d = db.getSiblingDB('external_system');
var coll = d.dutch_match_win_outcomes;
var batch = JSON.parse(fs.readFileSync('{container_json}', 'utf8'));
batch.forEach(function(doc) {{
  if (doc.user_id && doc.user_id.$oid) doc.user_id = ObjectId(doc.user_id.$oid);
  if (doc.ended_at && doc.ended_at.$date) doc.ended_at = new Date(doc.ended_at.$date);
}});
var r = coll.insertMany(batch, {{ ordered: false }});
print('batch {batch_num}/{total_batches} inserted ' + r.insertedCount);
"""
            with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as jf:
                jf.write(js_body)
                js_path = jf.name

            out = runner.run_js_file_in_container(js_path, container_js)
            for line in out.splitlines():
                if "inserted" in line:
                    print(f"  {line.strip()}")
        finally:
            if json_path:
                Path(json_path).unlink(missing_ok=True)
            if js_path:
                Path(js_path).unlink(missing_ok=True)

    summary_js = """
var d = db.getSiblingDB('external_system');
var coll = d.dutch_match_win_outcomes;
var now = new Date();
var mStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
print('Current month win rows: ' + coll.countDocuments({ ended_at: { $gte: mStart } }));
print('Total win rows: ' + coll.countDocuments({}));
"""
    print(runner.eval_js(summary_js))


def main() -> int:
    parser = argparse.ArgumentParser(description="Backfill comp player win outcomes for leaderboard")
    parser.add_argument("--apply", action="store_true", help="Write to MongoDB (default: dry-run)")
    parser.add_argument("--target", choices=("local", "vps"), default="local")
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--ssh-user", default=DEFAULT_SSH_USER)
    parser.add_argument("--ssh-host", default=DEFAULT_SSH_HOST)
    parser.add_argument("--ssh-key", default=DEFAULT_SSH_KEY)
    args = parser.parse_args()

    password = _resolve_password(args.target)
    if not password:
        print("ERROR: MONGODB_PASSWORD not set", file=sys.stderr)
        return 1
    if args.target == "vps" and not Path(args.ssh_key).expanduser().is_file():
        print(f"ERROR: SSH key not found: {args.ssh_key}", file=sys.stderr)
        return 1

    runner = MongoRunner(
        target=args.target,
        container=args.container,
        password=password,
        ssh_user=args.ssh_user,
        ssh_host=args.ssh_host,
        ssh_key=os.path.expanduser(args.ssh_key),
    )

    players = _fetch_comp_players(runner)
    now = datetime.now(timezone.utc)
    docs = _build_docs(players, now)
    total_wins = sum(int(p.get("wins") or 0) for p in players)

    label = "rop01 VPS" if args.target == "vps" else "docker-compose.yml MongoDB"
    print(f"Target: {args.target} ({label})")
    print(f"Container: {args.container}")
    print(f"Comp players with wins > 0: {len(players)}")
    print(f"Win outcome rows to insert: {len(docs)} (from {total_wins} lifetime wins)")

    if not args.apply:
        print("Dry-run only. Re-run with --apply to insert.")
        return 0

    _apply_batches(docs, runner)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
