#!/usr/bin/env python3
"""Aggregate AdMob / Play / App Store revenue into a single series payload."""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from admob_revenue import fetch_admob_estimated
from appstore_revenue import fetch_appstore_estimated, fetch_appstore_settled
from play_revenue import fetch_play_estimated, fetch_play_settled
from revenue_common import (
    SOURCES,
    default_range,
    filter_rows_by_range,
    parse_date,
    summarize,
)


def collect_revenue(
    *,
    sources: list[str] | None = None,
    kind: str = "estimated",
    start: date | None = None,
    end: date | None = None,
) -> dict[str, Any]:
    if start is None or end is None:
        d0, d1 = default_range(30)
        start = start or d0
        end = end or d1
    if end < start:
        start, end = end, start

    kind_norm = (kind or "estimated").strip().lower()
    if kind_norm not in ("estimated", "settled"):
        kind_norm = "estimated"

    wanted = [s.strip().lower() for s in (sources or sorted(SOURCES)) if s.strip()]
    wanted = [s for s in wanted if s in SOURCES] or sorted(SOURCES)

    rows: list[dict[str, Any]] = []
    errors: dict[str, str] = {}
    warnings: list[str] = []

    for src in wanted:
        if src == "admob":
            if kind_norm == "settled":
                errors["admob"] = (
                    "AdMob report API exposes estimated earnings only (no settled payout report)"
                )
                continue
            result = fetch_admob_estimated(start, end)
        elif src == "play":
            result = (
                fetch_play_settled(start, end)
                if kind_norm == "settled"
                else fetch_play_estimated(start, end)
            )
        else:
            result = (
                fetch_appstore_settled(start, end)
                if kind_norm == "settled"
                else fetch_appstore_estimated(start, end)
            )

        if not result.get("ok"):
            errors[src] = str(result.get("error") or "failed")
            continue
        if result.get("warning"):
            warnings.append(f"{src}: {result['warning']}")
        rows.extend(list(result.get("rows") or []))

    rows = filter_rows_by_range(rows, start, end)
    return {
        "ok": True,
        "kind": kind_norm,
        "from": start.isoformat(),
        "to": end.isoformat(),
        "sources": wanted,
        "rows": rows,
        "summary": summarize(rows),
        "errors": errors,
        "warnings": warnings,
    }


def collect_from_query(
    *,
    sources_csv: str = "",
    kind: str = "estimated",
    from_s: str = "",
    to_s: str = "",
) -> dict[str, Any]:
    d0, d1 = default_range(30)
    start = parse_date(from_s, default=d0)
    end = parse_date(to_s, default=d1)
    sources = [p for p in sources_csv.split(",") if p.strip()] if sources_csv else None
    return collect_revenue(sources=sources, kind=kind, start=start, end=end)
