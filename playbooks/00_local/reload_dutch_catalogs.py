#!/usr/bin/env python3
"""
Local dev: hot-reload Dutch declarative catalogs on a running Python API (no Flask restart).

POST /service/dutch/reload-catalogs with X-Service-Key — re-reads table_tiers.json
and consumables_catalog.json into the worker's memory only.

Usage:
  python3 playbooks/00_local/reload_dutch_catalogs.py

Requires app.debug.py running (default http://127.0.0.1:5001), e.g.:
  playbooks/frontend/run_python_app_to_global_log.sh

Env (repo-root .env.local loaded automatically):
  DART_BACKEND_SERVICE_KEY — X-Service-Key (same as Dart WS / Python local stack)
  PYTHON_API_URL / DUTCH_API_URL / FLASK_PORT — API base override
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent
LOCAL_ENV = PROJECT_ROOT / ".env.local"


def _load_env_file(path: Path) -> None:
    """Merge KEY=VALUE lines into os.environ (does not override existing vars)."""
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if not key or key in os.environ:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        os.environ[key] = value


def _resolve_api_url() -> str:
    for name in ("DUTCH_API_URL", "PYTHON_API_URL", "API_URL"):
        val = (os.environ.get(name) or "").strip().rstrip("/")
        if val:
            return val
    port = (os.environ.get("FLASK_PORT") or "5001").strip()
    return f"http://127.0.0.1:{port}"


def _resolve_service_key(explicit: str) -> str:
    if explicit.strip():
        return explicit.strip()
    for name in (
        "DART_BACKEND_SERVICE_KEY",
        "DUTCH_MT_DASHBOARD_SERVICE_KEY",
        "DUTCH_SERVICE_KEY",
        "SERVICE_KEY",
    ):
        val = (os.environ.get(name) or "").strip()
        if val:
            return val
    return ""


def main() -> int:
    _load_env_file(LOCAL_ENV)

    parser = argparse.ArgumentParser(
        description="Local dev: hot-reload Dutch catalogs on running app.debug.py",
    )
    parser.add_argument(
        "--url",
        default=_resolve_api_url(),
        help="Python API base URL",
    )
    parser.add_argument(
        "--service-key",
        default="",
        help="X-Service-Key (default: DART_BACKEND_SERVICE_KEY from env / .env.local)",
    )
    args = parser.parse_args()

    key = _resolve_service_key(args.service_key)
    if not key:
        print(
            "Error: set DART_BACKEND_SERVICE_KEY in .env.local (or pass --service-key)",
            file=sys.stderr,
        )
        return 1

    base = args.url.rstrip("/")
    endpoint = f"{base}/service/dutch/reload-catalogs"
    req = urllib.request.Request(
        endpoint,
        data=b"{}",
        headers={
            "Content-Type": "application/json",
            "X-Service-Key": key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            print(json.dumps(json.loads(body), indent=2))
            return 0 if 200 <= resp.status < 300 else 1
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}: {err_body}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"Request failed: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
