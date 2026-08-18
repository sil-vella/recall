#!/usr/bin/env python3
"""Shared helpers for dashboard Revenue tab (AdMob / Play / App Store)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any


SOURCES = frozenset({"admob", "play", "appstore"})
DOWNLOAD_SOURCES = frozenset({"play", "appstore"})
KINDS = frozenset({"estimated", "settled"})


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    env_file = os.environ.get("WFRUN_ENV_FILE", "").strip()
    if not env_file:
        return ""
    path = Path(env_file)
    if not path.is_file():
        return ""
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            if key.strip() != name:
                continue
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            return val.strip()
    except OSError:
        return ""
    return ""


def parse_date(value: str | None, *, default: date | None = None) -> date:
    raw = (value or "").strip()
    if not raw:
        if default is None:
            raise ValueError("date required")
        return default
    return date.fromisoformat(raw[:10])


def default_range(days: int = 30) -> tuple[date, date]:
    end = date.today()
    start = end - timedelta(days=max(1, days) - 1)
    return start, end


def months_touching(start: date, end: date) -> list[str]:
    """YYYYMM strings covering [start, end] inclusive."""
    if end < start:
        start, end = end, start
    out: list[str] = []
    y, m = start.year, start.month
    while (y, m) <= (end.year, end.month):
        out.append(f"{y:04d}{m:02d}")
        m += 1
        if m > 12:
            m = 1
            y += 1
    return out


def revenue_row(
    *,
    source: str,
    day: str,
    amount: float,
    currency: str,
    kind: str,
    app_id: str = "",
    units: float | None = None,
    label: str = "",
    raw_ref: str = "",
) -> dict[str, Any]:
    row: dict[str, Any] = {
        "source": source,
        "date": day,
        "app_id": app_id or "",
        "amount": round(float(amount), 6),
        "currency": (currency or "USD").upper(),
        "kind": kind,
        "label": label or "",
        "raw_ref": raw_ref or "",
    }
    if units is not None:
        row["units"] = float(units)
    return row


def http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: dict[str, Any] | bytes | None = None,
    timeout: float = 90,
) -> Any:
    data: bytes | None = None
    hdrs = dict(headers or {})
    if isinstance(body, dict):
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    elif isinstance(body, (bytes, bytearray)):
        data = bytes(body)
    req = urllib.request.Request(url, data=data, method=method.upper(), headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            if not raw:
                return None
            ctype = (resp.headers.get("Content-Type") or "").lower()
            if "json" in ctype or raw[:1] in (b"{", b"["):
                return json.loads(raw.decode("utf-8"))
            return raw
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} {url}: {err_body[:800]}") from exc


def http_bytes(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    timeout: float = 120,
) -> bytes:
    req = urllib.request.Request(url, method=method.upper(), headers=dict(headers or {}))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} {url}: {err_body[:800]}") from exc


def post_form(url: str, fields: dict[str, str], *, timeout: float = 60) -> dict[str, Any]:
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} {url}: {err_body[:800]}") from exc


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_source: dict[str, dict[str, float]] = {}
    currencies: set[str] = set()
    for row in rows:
        src = str(row.get("source") or "unknown")
        cur = str(row.get("currency") or "USD").upper()
        amt = float(row.get("amount") or 0)
        currencies.add(cur)
        bucket = by_source.setdefault(src, {})
        bucket[cur] = bucket.get(cur, 0.0) + amt
    totals = {
        src: {cur: round(v, 6) for cur, v in cur_map.items()}
        for src, cur_map in by_source.items()
    }
    return {
        "by_source": totals,
        "currencies": sorted(currencies),
        "mixed_currency": len(currencies) > 1,
        "row_count": len(rows),
    }


def summarize_units(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Sum download/install units by source (no FX / money)."""
    by_source: dict[str, float] = {}
    total = 0.0
    for row in rows:
        src = str(row.get("source") or "unknown")
        try:
            units = float(row.get("units") or 0)
        except (TypeError, ValueError):
            units = 0.0
        by_source[src] = by_source.get(src, 0.0) + units
        total += units
    return {
        "by_source": {k: round(v, 3) for k, v in sorted(by_source.items())},
        "total_units": round(total, 3),
        "row_count": len(rows),
    }


def filter_rows_by_range(
    rows: list[dict[str, Any]], start: date, end: date
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        day_s = str(row.get("date") or "")[:10]
        try:
            day = date.fromisoformat(day_s)
        except ValueError:
            continue
        if start <= day <= end:
            out.append(row)
    out.sort(key=lambda r: (str(r.get("date") or ""), str(r.get("source") or "")))
    return out


def iso_day(value: date | datetime | str) -> str:
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return str(value)[:10]
