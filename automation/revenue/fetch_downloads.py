#!/usr/bin/env python3
"""Aggregate Play / App Store download (install) units for the Revenue → Downloads tab."""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from appstore_revenue import fetch_appstore_downloads
from play_revenue import fetch_play_downloads
from revenue_common import (
    DOWNLOAD_SOURCES,
    default_range,
    filter_rows_by_range,
    parse_date,
    summarize_units,
)


def collect_downloads(
    *,
    sources: list[str] | None = None,
    start: date | None = None,
    end: date | None = None,
) -> dict[str, Any]:
    if start is None or end is None:
        d0, d1 = default_range(30)
        start = start or d0
        end = end or d1
    if end < start:
        start, end = end, start

    wanted = [s.strip().lower() for s in (sources or sorted(DOWNLOAD_SOURCES)) if s.strip()]
    wanted = [s for s in wanted if s in DOWNLOAD_SOURCES] or sorted(DOWNLOAD_SOURCES)

    rows: list[dict[str, Any]] = []
    errors: dict[str, str] = {}
    warnings: list[str] = []

    for src in wanted:
        if src == "play":
            result = fetch_play_downloads(start, end)
        else:
            result = fetch_appstore_downloads(start, end)

        if not result.get("ok"):
            errors[src] = str(result.get("error") or "failed")
            continue
        if result.get("warning"):
            warnings.append(f"{src}: {result['warning']}")
        rows.extend(list(result.get("rows") or []))

    rows = filter_rows_by_range(rows, start, end)
    return {
        "ok": True,
        "kind": "downloads",
        "from": start.isoformat(),
        "to": end.isoformat(),
        "sources": wanted,
        "rows": rows,
        "summary": summarize_units(rows),
        "errors": errors,
        "warnings": warnings,
    }


def collect_downloads_from_query(
    *,
    sources_csv: str = "",
    from_s: str = "",
    to_s: str = "",
) -> dict[str, Any]:
    d0, d1 = default_range(30)
    start = parse_date(from_s, default=d0)
    end = parse_date(to_s, default=d1)
    sources = [p for p in sources_csv.split(",") if p.strip()] if sources_csv else None
    return collect_downloads(sources=sources, start=start, end=end)
