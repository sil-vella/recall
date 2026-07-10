#!/usr/bin/env python3
"""
CLI for deploy drain mode: enter, exit, status, and poll until ready.

Requires Flask API base URL and DART_BACKEND_SERVICE_KEY (same key Flask accepts on /service/*).

Examples:
  python3 tools/ops_drain.py enter --base-url http://127.0.0.1:5001
  python3 tools/ops_drain.py status --base-url http://127.0.0.1:5001
  python3 tools/ops_drain.py poll --base-url http://127.0.0.1:5001 --max-wait 1800
  python3 tools/ops_drain.py exit --base-url http://127.0.0.1:5001
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any, Dict, Optional

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _service_key() -> str:
    key = (os.environ.get("DART_BACKEND_SERVICE_KEY") or "").strip()
    if not key:
        raise SystemExit(
            "ERROR: set DART_BACKEND_SERVICE_KEY in the environment "
            "(same value Flask uses for /service/* auth)."
        )
    return key


def _headers() -> Dict[str, str]:
    return {
        "X-Service-Key": _service_key(),
        "Content-Type": "application/json",
    }


def _url(base_url: str, path: str) -> str:
    return f"{base_url.rstrip('/')}{path}"


def _request(
    method: str,
    base_url: str,
    path: str,
    *,
    timeout: float = 30.0,
) -> Dict[str, Any]:
    response = requests.request(
        method,
        _url(base_url, path),
        headers=_headers(),
        timeout=timeout,
    )
    try:
        body = response.json()
    except Exception:
        body = {"raw": response.text}
    if response.status_code >= 400:
        raise SystemExit(
            f"HTTP {response.status_code}: {json.dumps(body, indent=2)}"
        )
    if not isinstance(body, dict):
        raise SystemExit(f"Unexpected response: {body!r}")
    return body


def cmd_enter(base_url: str) -> int:
    data = _request("POST", base_url, "/service/ops/enter-drain")
    print(json.dumps(data, indent=2))
    return 0


def cmd_exit(base_url: str) -> int:
    data = _request("POST", base_url, "/service/ops/exit-drain")
    print(json.dumps(data, indent=2))
    return 0


def cmd_status(base_url: str) -> int:
    data = _request("GET", base_url, "/service/ops/drain-status")
    print(json.dumps(data, indent=2))
    return 0 if data.get("ready") else 1


def cmd_poll(
    base_url: str,
    *,
    max_wait: int,
    interval: int,
    stable_polls: int,
) -> int:
    deadline = time.time() + max_wait
    consecutive_clear = 0
    while time.time() < deadline:
        data = _request("GET", base_url, "/service/ops/drain-status")
        ready = data.get("ready") is True
        checks = data.get("checks") or {}
        matches_clear = checks.get("matches_clear") is True
        store_clear = checks.get("store_clear") is True
        print(
            f"poll: active_matches={data.get('active_matches')} "
            f"store_in_flight={data.get('store_in_flight')} "
            f"ready={ready}",
            flush=True,
        )
        if matches_clear and store_clear:
            consecutive_clear += 1
        else:
            consecutive_clear = 0
        if ready and consecutive_clear >= stable_polls:
            print(json.dumps(data, indent=2))
            return 0
        time.sleep(interval)
    print(
        f"ERROR: drain not ready after {max_wait}s — abort (call exit to revert)",
        file=sys.stderr,
    )
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Dutch deploy drain mode CLI")
    parser.add_argument(
        "command",
        choices=["enter", "exit", "status", "poll"],
        help="enter/exit drain, print status, or poll until ready",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("OPS_DRAIN_BASE_URL", "http://127.0.0.1:5001"),
        help="Flask API base URL (default: OPS_DRAIN_BASE_URL or http://127.0.0.1:5001)",
    )
    parser.add_argument(
        "--max-wait",
        type=int,
        default=1800,
        help="poll: max seconds to wait (default 1800)",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=15,
        help="poll: seconds between checks (default 15)",
    )
    parser.add_argument(
        "--stable-polls",
        type=int,
        default=2,
        help="poll: consecutive clear readings required (default 2)",
    )
    args = parser.parse_args()

    if args.command == "enter":
        return cmd_enter(args.base_url)
    if args.command == "exit":
        return cmd_exit(args.base_url)
    if args.command == "status":
        return cmd_status(args.base_url)
    return cmd_poll(
        args.base_url,
        max_wait=args.max_wait,
        interval=args.interval,
        stable_polls=args.stable_polls,
    )


if __name__ == "__main__":
    raise SystemExit(main())
