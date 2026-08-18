#!/usr/bin/env python3
"""Google Play financial CSVs via private GCS bucket (estimated sales + earnings)."""

from __future__ import annotations

import base64
import csv
import io
import json
import time
import zipfile
from datetime import date
from pathlib import Path
from typing import Any

from urllib.parse import quote

from revenue_common import (
    env,
    http_bytes,
    http_json,
    iso_day,
    months_touching,
    post_form,
    revenue_row,
)

TOKEN_URI = "https://oauth2.googleapis.com/token"
GCS_SCOPE = "https://www.googleapis.com/auth/devstorage.read_only"
STORAGE_API = "https://storage.googleapis.com/storage/v1"


def _load_sa() -> dict[str, Any]:
    path_s = env("PLAY_SERVICE_ACCOUNT_JSON")
    if not path_s:
        raise RuntimeError("Missing PLAY_SERVICE_ACCOUNT_JSON (path to SA JSON key)")
    path = Path(path_s).expanduser()
    if not path.is_file():
        raise RuntimeError(f"PLAY_SERVICE_ACCOUNT_JSON not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not data.get("client_email") or not data.get("private_key"):
        raise RuntimeError("Service account JSON missing client_email / private_key")
    return data


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _sa_access_token(sa: dict[str, Any]) -> str:
    from jwt_openssl import encode_jwt

    now = int(time.time())
    assertion = encode_jwt(
        {
            "iss": sa["client_email"],
            "scope": GCS_SCOPE,
            "aud": TOKEN_URI,
            "iat": now,
            "exp": now + 3600,
        },
        private_key_pem=str(sa["private_key"]),
        algorithm="RS256",
    )
    payload = post_form(
        TOKEN_URI,
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        },
    )
    token = str(payload.get("access_token") or "").strip()
    if not token:
        raise RuntimeError("Play SA token exchange returned no access_token")
    return token


def _bucket_id() -> str:
    raw = env("PLAY_GCS_BUCKET").strip()
    if not raw:
        raise RuntimeError("Missing PLAY_GCS_BUCKET (pubsite_prod_rev_…)")
    raw = raw.removeprefix("gs://")
    return raw.split("/", 1)[0]


def _list_objects(token: str, bucket: str, prefix: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    page_token = ""
    while True:
        q = {
            "prefix": prefix,
            "maxResults": "1000",
        }
        if page_token:
            q["pageToken"] = page_token
        qs = "&".join(f"{k}={quote(str(v), safe='')}" for k, v in q.items())
        url = f"{STORAGE_API}/b/{bucket}/o?{qs}"
        data = http_json(
            "GET",
            url,
            headers={"Authorization": f"Bearer {token}"},
        )
        if not isinstance(data, dict):
            break
        for it in data.get("items") or []:
            if isinstance(it, dict):
                items.append(it)
        page_token = str(data.get("nextPageToken") or "")
        if not page_token:
            break
    return items


def _download_object(token: str, bucket: str, name: str) -> bytes:
    url = f"{STORAGE_API}/b/{bucket}/o/{quote(name, safe='')}?alt=media"
    return http_bytes("GET", url, headers={"Authorization": f"Bearer {token}"})


def _read_csv_from_zip(blob: bytes) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            lower = info.filename.lower()
            if not (lower.endswith(".csv") or lower.endswith(".txt")):
                continue
            text = zf.read(info).decode("utf-8-sig", errors="replace")
            reader = csv.DictReader(io.StringIO(text))
            for row in reader:
                rows.append({(k or "").strip(): (v or "").strip() for k, v in row.items()})
    return rows


def _col(row: dict[str, str], *names: str) -> str:
    lower_map = {k.lower(): v for k, v in row.items()}
    for name in names:
        if name in row and row[name]:
            return row[name]
        if name.lower() in lower_map and lower_map[name.lower()]:
            return lower_map[name.lower()]
    return ""


def _parse_money(raw: str) -> float:
    s = (raw or "").replace(",", "").replace(" ", "").strip()
    if not s:
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def _package_filter() -> str:
    return env("PLAY_PACKAGE_NAME")


def _parse_sales_rows(csv_rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    pkg_filter = _package_filter()
    out: list[dict[str, Any]] = []
    for row in csv_rows:
        pkg = _col(row, "Product ID", "Product id", "Package Name", "product id")
        if pkg_filter and pkg and pkg != pkg_filter:
            continue
        day = _col(row, "Order Charged Date", "Transaction Date", "Date")
        if not day:
            continue
        # Often YYYY-MM-DD or M/D/YYYY
        day_iso = day
        if "/" in day:
            parts = day.split("/")
            if len(parts) == 3:
                m, d, y = parts
                day_iso = f"{int(y):04d}-{int(m):02d}-{int(d):02d}"
        else:
            day_iso = iso_day(day)
        amount = _parse_money(
            _col(
                row,
                "Charged Amount",
                "Item Price",
                "Amount (Merchant Currency)",
                "Currency Conversion Rate",
            )
        )
        # Prefer charged amount; some exports use Item Price * Quantity
        if amount == 0.0:
            price = _parse_money(_col(row, "Item Price"))
            qty = _parse_money(_col(row, "Item Price Currency", "Quantity") or "1")
            # Quantity column
            qty_s = _col(row, "Quantity")
            if qty_s:
                qty = _parse_money(qty_s) or 1.0
            amount = price * (qty or 1.0)
        currency = _col(
            row,
            "Currency of Sale",
            "Currency of Buyer",
            "Merchant Currency",
            "Currency",
        ) or "USD"
        status = _col(row, "Financial Status", "Order Status", "Status").upper()
        if status and status not in ("CHARGED", "CHARGE", "CHARGED ", ""):
            if "REFUND" in status:
                amount = -abs(amount)
            elif status not in ("CHARGED",):
                # skip pending/cancelled when explicit
                if status in ("CANCELLED", "CANCELED", "PENDING"):
                    continue
        units = _parse_money(_col(row, "Quantity")) or None
        out.append(
            revenue_row(
                source="play",
                day=day_iso,
                amount=amount,
                currency=currency,
                kind="estimated",
                app_id=pkg,
                units=units,
                label=_col(row, "Product Title", "SKU ID") or pkg or "Play",
                raw_ref="sales",
            )
        )
    return out


def _parse_earnings_rows(csv_rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    pkg_filter = _package_filter()
    out: list[dict[str, Any]] = []
    for row in csv_rows:
        pkg = _col(row, "Product id", "Product ID", "Package Name")
        if pkg_filter and pkg and pkg != pkg_filter:
            continue
        day = _col(
            row,
            "Transaction Date",
            "Description Date",
            "Order Charged Date",
            "Date",
        )
        if not day:
            continue
        day_iso = iso_day(day.replace("/", "-") if len(day) >= 8 else day)
        if "/" in day:
            parts = day.split("/")
            if len(parts) == 3:
                try:
                    m, d, y = parts
                    day_iso = f"{int(y):04d}-{int(m):02d}-{int(d):02d}"
                except ValueError:
                    day_iso = iso_day(day)
        amount = _parse_money(
            _col(row, "Amount (Merchant Currency)", "Merchant Currency Amount", "Amount")
        )
        currency = _col(row, "Merchant Currency", "Currency") or "USD"
        tx = _col(row, "Transaction Type", "Description").lower()
        # Charges positive; fees/refunds as signed in file — keep file sign
        if "refund" in tx and amount > 0:
            amount = -amount
        out.append(
            revenue_row(
                source="play",
                day=day_iso,
                amount=amount,
                currency=currency,
                kind="settled",
                app_id=pkg,
                label=_col(row, "Product Title") or pkg or "Play",
                raw_ref="earnings",
            )
        )
    return out


def _fetch_prefix_zips(
    token: str,
    bucket: str,
    prefix: str,
    months: list[str],
) -> list[bytes]:
    objects = _list_objects(token, bucket, prefix)
    blobs: list[bytes] = []
    for obj in objects:
        name = str(obj.get("name") or "")
        if not name.lower().endswith(".zip"):
            continue
        if months and not any(m in name for m in months):
            continue
        blobs.append(_download_object(token, bucket, name))
    return blobs


def fetch_play_estimated(start: date, end: date) -> dict[str, Any]:
    try:
        sa = _load_sa()
        bucket = _bucket_id()
        token = _sa_access_token(sa)
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    months = months_touching(start, end)
    try:
        zips = _fetch_prefix_zips(token, bucket, "sales/", months)
        rows: list[dict[str, Any]] = []
        for blob in zips:
            rows.extend(_parse_sales_rows(_read_csv_from_zip(blob)))
        # Filter to range
        from revenue_common import filter_rows_by_range

        rows = filter_rows_by_range(rows, start, end)
        return {"ok": True, "rows": rows, "source": "play", "kind": "estimated"}
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}


def fetch_play_settled(start: date, end: date) -> dict[str, Any]:
    try:
        sa = _load_sa()
        bucket = _bucket_id()
        token = _sa_access_token(sa)
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    months = months_touching(start, end)
    try:
        zips = _fetch_prefix_zips(token, bucket, "earnings/", months)
        rows: list[dict[str, Any]] = []
        for blob in zips:
            rows.extend(_parse_earnings_rows(_read_csv_from_zip(blob)))
        from revenue_common import filter_rows_by_range

        rows = filter_rows_by_range(rows, start, end)
        return {"ok": True, "rows": rows, "source": "play", "kind": "settled"}
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}


def _decode_stats_csv(blob: bytes) -> str:
    """Play stats CSVs are often UTF-16 (with or without BOM)."""
    if blob.startswith(b"\xff\xfe") or blob.startswith(b"\xfe\xff"):
        return blob.decode("utf-16")
    sample = blob[:64]
    if b"\x00" in sample:
        return blob.decode("utf-16")
    return blob.decode("utf-8-sig", errors="replace")


def _parse_installs_overview(csv_rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    pkg_filter = _package_filter()
    out: list[dict[str, Any]] = []
    for row in csv_rows:
        pkg = _col(row, "Package name", "Package Name", "Product ID")
        if pkg_filter and pkg and pkg != pkg_filter:
            continue
        day = _col(row, "Date")
        if not day:
            continue
        day_iso = iso_day(day)
        # Prefer daily user installs; fall back to device installs / install events
        units = _parse_money(
            _col(
                row,
                "Daily User Installs",
                "Daily Device Installs",
                "Install events",
            )
        )
        if units == 0.0:
            continue
        out.append(
            revenue_row(
                source="play",
                day=day_iso,
                amount=0.0,
                currency="—",
                kind="downloads",
                app_id=pkg,
                units=units,
                label=pkg or "Play",
                raw_ref="stats/installs/overview",
            )
        )
    return out


def fetch_play_downloads(start: date, end: date) -> dict[str, Any]:
    """Daily installs from GCS stats/installs/*_overview.csv."""
    try:
        sa = _load_sa()
        bucket = _bucket_id()
        token = _sa_access_token(sa)
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}

    months = months_touching(start, end)
    pkg = _package_filter()
    prefix = f"stats/installs/installs_{pkg}_" if pkg else "stats/installs/"
    try:
        objects = _list_objects(token, bucket, prefix)
        rows: list[dict[str, Any]] = []
        for obj in objects:
            name = str(obj.get("name") or "")
            if not name.endswith("_overview.csv"):
                continue
            if months and not any(m in name for m in months):
                continue
            blob = _download_object(token, bucket, name)
            text = _decode_stats_csv(blob)
            reader = csv.DictReader(io.StringIO(text))
            csv_rows = [
                {(k or "").strip(): (v or "").strip() for k, v in row.items()}
                for row in reader
            ]
            rows.extend(_parse_installs_overview(csv_rows))
        from revenue_common import filter_rows_by_range

        rows = filter_rows_by_range(rows, start, end)
        return {"ok": True, "rows": rows, "source": "play", "kind": "downloads"}
    except RuntimeError as exc:
        return {"ok": False, "error": str(exc), "rows": []}
