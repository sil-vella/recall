#!/usr/bin/env python3
"""AdMob Network report → normalized revenue rows (ESTIMATED_EARNINGS)."""

from __future__ import annotations

import json
from datetime import date
from typing import Any

from revenue_common import env, http_json, iso_day, post_form, revenue_row

TOKEN_URI = "https://oauth2.googleapis.com/token"
NETWORK_REPORT_TMPL = (
    "https://admob.googleapis.com/v1/accounts/{pub}/networkReport:generate"
)


def _access_token() -> str:
    client_id = env("ADMOB_CLIENT_ID")
    client_secret = env("ADMOB_CLIENT_SECRET")
    refresh = env("ADMOB_REFRESH_TOKEN")
    if not client_id or not client_secret or not refresh:
        raise RuntimeError(
            "Missing ADMOB_CLIENT_ID / ADMOB_CLIENT_SECRET / ADMOB_REFRESH_TOKEN"
        )
    payload = post_form(
        TOKEN_URI,
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        },
    )
    token = str(payload.get("access_token") or "").strip()
    if not token:
        raise RuntimeError("AdMob token refresh returned no access_token")
    return token


def _publisher_id() -> str:
    pub = env("ADMOB_PUBLISHER_ID")
    if not pub:
        raise RuntimeError("Missing ADMOB_PUBLISHER_ID (pub-…)")
    if not pub.startswith("accounts/"):
        return pub
    return pub.removeprefix("accounts/")


def _micros_to_amount(value: Any) -> float:
    try:
        return float(value) / 1_000_000.0
    except (TypeError, ValueError):
        return 0.0


def fetch_admob_estimated(start: date, end: date) -> dict[str, Any]:
    """Return {ok, rows, currency, warning?}."""
    try:
        token = _access_token()
        pub = _publisher_id()
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    url = NETWORK_REPORT_TMPL.format(pub=pub)
    body = {
        "reportSpec": {
            "dateRange": {
                "startDate": {
                    "year": start.year,
                    "month": start.month,
                    "day": start.day,
                },
                "endDate": {"year": end.year, "month": end.month, "day": end.day},
            },
            "dimensions": ["DATE", "APP"],
            "metrics": ["ESTIMATED_EARNINGS", "IMPRESSIONS"],
            "localizationSettings": {
                "currencyCode": env("ADMOB_CURRENCY") or "USD",
                "languageCode": "en-US",
            },
        }
    }
    try:
        # Streaming JSON array of response objects
        raw = http_json(
            "POST",
            url,
            headers={"Authorization": f"Bearer {token}"},
            body=body,
            timeout=120,
        )
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    chunks: list[dict[str, Any]]
    if isinstance(raw, list):
        chunks = [c for c in raw if isinstance(c, dict)]
    elif isinstance(raw, dict):
        chunks = [raw]
    elif isinstance(raw, (bytes, bytearray)):
        text = raw.decode("utf-8", errors="replace").strip()
        # NDJSON or JSON array
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list):
                chunks = [c for c in parsed if isinstance(c, dict)]
            elif isinstance(parsed, dict):
                chunks = [parsed]
            else:
                chunks = []
        except json.JSONDecodeError:
            chunks = []
            for line in text.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    chunks.append(obj)
    else:
        chunks = []

    currency = env("ADMOB_CURRENCY") or "USD"
    rows: list[dict[str, Any]] = []
    header_currency = currency
    for chunk in chunks:
        header = chunk.get("header") or {}
        loc = (header.get("localizationSettings") or {}) if isinstance(header, dict) else {}
        if isinstance(loc, dict) and loc.get("currencyCode"):
            header_currency = str(loc["currencyCode"]).upper()
        row_obj = chunk.get("row")
        if not isinstance(row_obj, dict):
            continue
        dims = row_obj.get("dimensionValues") or {}
        metrics = row_obj.get("metricValues") or {}
        if not isinstance(dims, dict) or not isinstance(metrics, dict):
            continue
        date_dim = dims.get("DATE") or {}
        app_dim = dims.get("APP") or {}
        day_val = ""
        if isinstance(date_dim, dict):
            day_val = str(date_dim.get("value") or date_dim.get("displayLabel") or "")
        # AdMob DATE is often YYYYMMDD
        if len(day_val) == 8 and day_val.isdigit():
            day_val = f"{day_val[0:4]}-{day_val[4:6]}-{day_val[6:8]}"
        else:
            day_val = iso_day(day_val) if day_val else ""
        app_id = ""
        app_label = ""
        if isinstance(app_dim, dict):
            app_id = str(app_dim.get("value") or "")
            app_label = str(app_dim.get("displayLabel") or app_id)
        earn = metrics.get("ESTIMATED_EARNINGS") or {}
        micros = 0
        if isinstance(earn, dict):
            micros = earn.get("microsValue")
            if micros is None:
                micros = earn.get("integerValue")
            if earn.get("currencyCode"):
                header_currency = str(earn["currencyCode"]).upper()
        amount = _micros_to_amount(micros)
        impressions = None
        imp = metrics.get("IMPRESSIONS") or {}
        if isinstance(imp, dict) and imp.get("integerValue") is not None:
            try:
                impressions = float(imp["integerValue"])
            except (TypeError, ValueError):
                impressions = None
        if not day_val:
            continue
        rows.append(
            revenue_row(
                source="admob",
                day=day_val,
                amount=amount,
                currency=header_currency,
                kind="estimated",
                app_id=app_id,
                units=impressions,
                label=app_label or "AdMob",
            )
        )

    return {
        "ok": True,
        "rows": rows,
        "currency": header_currency,
        "source": "admob",
        "kind": "estimated",
    }
