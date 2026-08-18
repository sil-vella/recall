#!/usr/bin/env python3
"""App Store Connect salesReports + financeReports → normalized revenue rows."""

from __future__ import annotations

import csv
import gzip
import io
import time
from datetime import date, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from revenue_common import env, http_bytes, iso_day, months_touching, revenue_row

ASC_BASE = "https://api.appstoreconnect.apple.com"


def _load_private_key() -> str:
    path_s = env("ASC_PRIVATE_KEY_PATH")
    if not path_s:
        raise RuntimeError("Missing ASC_PRIVATE_KEY_PATH (.p8)")
    path = Path(path_s).expanduser()
    if not path.is_file():
        raise RuntimeError(f"ASC_PRIVATE_KEY_PATH not found: {path}")
    return path.read_text(encoding="utf-8")


def _asc_token() -> str:
    from jwt_openssl import encode_jwt

    issuer = env("ASC_ISSUER_ID")
    key_id = env("ASC_KEY_ID")
    if not issuer or not key_id:
        raise RuntimeError("Missing ASC_ISSUER_ID / ASC_KEY_ID")
    private_key = _load_private_key()
    now = int(time.time())
    return encode_jwt(
        {
            "iss": issuer,
            "iat": now,
            "exp": now + 20 * 60,
            "aud": "appstoreconnect-v1",
        },
        private_key_pem=private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def _vendor() -> str:
    v = env("ASC_VENDOR_NUMBER")
    if not v:
        raise RuntimeError("Missing ASC_VENDOR_NUMBER")
    return v


def _app_filter() -> str:
    return env("ASC_APP_APPLE_ID")


def _download_report(path: str, params: dict[str, str]) -> bytes:
    token = _asc_token()
    url = f"{ASC_BASE}{path}?{urlencode(params)}"
    return http_bytes(
        "GET",
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/a-gzip",
        },
        timeout=180,
    )


def _tsv_rows(blob: bytes) -> list[dict[str, str]]:
    # ASC returns gzip TSV
    try:
        text = gzip.decompress(blob).decode("utf-8-sig", errors="replace")
    except OSError:
        text = blob.decode("utf-8-sig", errors="replace")
    reader = csv.DictReader(io.StringIO(text), delimiter="\t")
    return [{(k or "").strip(): (v or "").strip() for k, v in row.items()} for row in reader]


def _col(row: dict[str, str], *names: str) -> str:
    lower_map = {k.lower(): v for k, v in row.items()}
    for name in names:
        if name in row and row[name]:
            return row[name]
        if name.lower() in lower_map and lower_map[name.lower()]:
            return lower_map[name.lower()]
    return ""


def _parse_money(raw: str) -> float:
    s = (raw or "").replace(",", "").strip()
    if not s:
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def _daterange_days(start: date, end: date) -> list[date]:
    out: list[date] = []
    cur = start
    while cur <= end:
        out.append(cur)
        cur += timedelta(days=1)
    return out


def _parse_sales_summary(rows: list[dict[str, str]], *, day_fallback: str) -> list[dict[str, Any]]:
    app_filter = _app_filter()
    out: list[dict[str, Any]] = []
    for row in rows:
        apple_id = _col(row, "Apple Identifier", "SKU")
        if app_filter and apple_id and apple_id != app_filter:
            # Also allow title-only rows without id match skip when filter set and id present
            if _col(row, "Apple Identifier") and _col(row, "Apple Identifier") != app_filter:
                continue
        units = _parse_money(_col(row, "Units"))
        # Proceeds (developer) preferred for revenue; Customer Price is buyer-facing
        proceeds = _parse_money(_col(row, "Developer Proceeds", "Proceeds"))
        customer = _parse_money(_col(row, "Customer Price"))
        amount = proceeds if proceeds else customer * units
        currency = _col(row, "Currency of Proceeds", "Customer Currency", "Currency") or "USD"
        day = _col(row, "Begin Date", "End Date") or day_fallback
        if day and "/" in day:
            # MM/DD/YYYY
            parts = day.split("/")
            if len(parts) == 3:
                m, d, y = parts
                day = f"{int(y):04d}-{int(m):02d}-{int(d):02d}"
        else:
            day = iso_day(day) if day else day_fallback
        product_type = _col(row, "Product Type Identifier")
        # Skip free downloads with zero proceeds when clearly free
        if amount == 0 and units and product_type in ("1", "1-B", "F1"):
            continue
        out.append(
            revenue_row(
                source="appstore",
                day=day,
                amount=amount,
                currency=currency,
                kind="estimated",
                app_id=apple_id or _col(row, "SKU"),
                units=units or None,
                label=_col(row, "Title", "SKU") or "App Store",
                raw_ref="salesReports",
            )
        )
    return out


def _parse_finance(rows: list[dict[str, str]], *, month_label: str) -> list[dict[str, Any]]:
    app_filter = _app_filter()
    out: list[dict[str, Any]] = []
    # Use mid-month date for monthly settled aggregate lines lacking a day
    if len(month_label) == 7 and month_label[4] == "-":
        day_fallback = f"{month_label}-15"
    elif len(month_label) == 6:
        day_fallback = f"{month_label[0:4]}-{month_label[4:6]}-15"
    else:
        day_fallback = month_label[:10]

    for row in rows:
        apple_id = _col(row, "Apple Identifier", "SKU")
        if app_filter and apple_id and apple_id != app_filter:
            continue
        qty = _parse_money(_col(row, "Quantity", "Units"))
        partner = _parse_money(_col(row, "Partner Share", "Extended Partner Share"))
        if partner == 0:
            partner = _parse_money(_col(row, "Partner Share Currency")) * qty
        currency = _col(row, "Partner Share Currency", "Currency") or "USD"
        sale_or_return = _col(row, "Sale or Return", "Sales or Return").upper()
        amount = partner
        if sale_or_return.startswith("R") and amount > 0:
            amount = -amount
        out.append(
            revenue_row(
                source="appstore",
                day=day_fallback,
                amount=amount,
                currency=currency,
                kind="settled",
                app_id=apple_id,
                units=qty or None,
                label=_col(row, "Title", "SKU") or "App Store",
                raw_ref="financeReports",
            )
        )
    return out


def fetch_appstore_estimated(start: date, end: date) -> dict[str, Any]:
    try:
        vendor = _vendor()
        _asc_token()  # validate env early
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    rows_out: list[dict[str, Any]] = []
    errors: list[str] = []
    # Daily SALES SUMMARY for each day in range (ASC stores ~past year)
    for day in _daterange_days(start, end):
        params = {
            "filter[frequency]": "DAILY",
            "filter[reportDate]": day.isoformat(),
            "filter[reportSubType]": "SUMMARY",
            "filter[reportType]": "SALES",
            "filter[vendorNumber]": vendor,
            "filter[version]": "1_0",
        }
        try:
            blob = _download_report("/v1/salesReports", params)
            rows_out.extend(_parse_sales_summary(_tsv_rows(blob), day_fallback=day.isoformat()))
        except RuntimeError as exc:
            msg = str(exc)
            # Missing day reports are common (no sales / not ready)
            if "404" in msg or "NOT_FOUND" in msg:
                continue
            errors.append(f"{day.isoformat()}: {msg[:200]}")
            # Don't abort entire range on one bad day
            continue

    from revenue_common import filter_rows_by_range

    rows_out = filter_rows_by_range(rows_out, start, end)
    result: dict[str, Any] = {
        "ok": True,
        "rows": rows_out,
        "source": "appstore",
        "kind": "estimated",
    }
    if errors and not rows_out:
        result["ok"] = False
        result["error"] = "; ".join(errors[:5])
    elif errors:
        result["warning"] = f"{len(errors)} day(s) failed; showing available rows"
    return result


def fetch_appstore_settled(start: date, end: date) -> dict[str, Any]:
    try:
        vendor = _vendor()
        _asc_token()
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    rows_out: list[dict[str, Any]] = []
    errors: list[str] = []
    # Apple fiscal months as YYYY-MM
    for ym in months_touching(start, end):
        report_date = f"{ym[0:4]}-{ym[4:6]}"
        params = {
            "filter[regionCode]": "ZZ",
            "filter[reportDate]": report_date,
            "filter[reportType]": "FINANCIAL",
            "filter[vendorNumber]": vendor,
        }
        try:
            blob = _download_report("/v1/financeReports", params)
            rows_out.extend(_parse_finance(_tsv_rows(blob), month_label=report_date))
        except RuntimeError as exc:
            msg = str(exc)
            if "404" in msg or "NOT_FOUND" in msg:
                continue
            errors.append(f"{report_date}: {msg[:200]}")

    from revenue_common import filter_rows_by_range

    rows_out = filter_rows_by_range(rows_out, start, end)
    result: dict[str, Any] = {
        "ok": True,
        "rows": rows_out,
        "source": "appstore",
        "kind": "settled",
    }
    if errors and not rows_out:
        result["ok"] = False
        result["error"] = "; ".join(errors[:5])
    elif errors:
        result["warning"] = f"{len(errors)} month(s) failed; showing available rows"
    return result


# App first downloads (free or paid) — not IAP / subscriptions
_DOWNLOAD_PRODUCT_TYPES = frozenset({"1", "1-B", "F1", "1F"})


def _parse_sales_downloads(
    rows: list[dict[str, str]], *, day_fallback: str
) -> list[dict[str, Any]]:
    app_filter = _app_filter()
    out: list[dict[str, Any]] = []
    for row in rows:
        apple_id = _col(row, "Apple Identifier", "SKU")
        if app_filter and apple_id and apple_id != app_filter:
            if _col(row, "Apple Identifier") and _col(row, "Apple Identifier") != app_filter:
                continue
        product_type = _col(row, "Product Type Identifier")
        if product_type not in _DOWNLOAD_PRODUCT_TYPES:
            continue
        units = _parse_money(_col(row, "Units"))
        if not units:
            continue
        day = _col(row, "Begin Date", "End Date") or day_fallback
        if day and "/" in day:
            parts = day.split("/")
            if len(parts) == 3:
                m, d, y = parts
                day = f"{int(y):04d}-{int(m):02d}-{int(d):02d}"
        else:
            day = iso_day(day) if day else day_fallback
        out.append(
            revenue_row(
                source="appstore",
                day=day,
                amount=0.0,
                currency="—",
                kind="downloads",
                app_id=apple_id or _col(row, "SKU"),
                units=units,
                label=_col(row, "Title", "SKU") or "App Store",
                raw_ref="salesReports/downloads",
            )
        )
    return out


def fetch_appstore_downloads(start: date, end: date) -> dict[str, Any]:
    """App download units from daily salesReports (types 1 / 1-B / F1 / 1F)."""
    try:
        vendor = _vendor()
        _asc_token()
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    rows_out: list[dict[str, Any]] = []
    errors: list[str] = []
    for day in _daterange_days(start, end):
        params = {
            "filter[frequency]": "DAILY",
            "filter[reportDate]": day.isoformat(),
            "filter[reportSubType]": "SUMMARY",
            "filter[reportType]": "SALES",
            "filter[vendorNumber]": vendor,
            "filter[version]": "1_0",
        }
        try:
            blob = _download_report("/v1/salesReports", params)
            rows_out.extend(
                _parse_sales_downloads(_tsv_rows(blob), day_fallback=day.isoformat())
            )
        except RuntimeError as exc:
            msg = str(exc)
            if "404" in msg or "NOT_FOUND" in msg:
                continue
            errors.append(f"{day.isoformat()}: {msg[:200]}")
            continue

    from revenue_common import filter_rows_by_range

    rows_out = filter_rows_by_range(rows_out, start, end)
    result: dict[str, Any] = {
        "ok": True,
        "rows": rows_out,
        "source": "appstore",
        "kind": "downloads",
    }
    if errors and not rows_out:
        result["ok"] = False
        result["error"] = "; ".join(errors[:5])
    elif errors:
        result["warning"] = f"{len(errors)} day(s) failed; showing available rows"
    return result
