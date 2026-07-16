#!/usr/bin/env python3
"""
Seed a campaign referral code into MongoDB (local docker-compose Mongo).

Usage (from repo root, with Mongo on localhost:27018):

  python3 playbooks/00_local/seed_referral_campaign.py \\
    --code SUMMER50 --coins 200 --max-per-user 1 \\
    --db external_system \\
    --uri mongodb://external_app_user:PASSWORD@127.0.0.1:27018/external_system?authSource=admin

Or set MONGO_URI / use defaults from local compose env files if present.
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone

try:
    from pymongo import MongoClient
except ImportError:
    print("pymongo required: pip install pymongo", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Upsert referral_campaigns document")
    parser.add_argument("--code", default="SUMMER50", help="Campaign code (stored uppercase)")
    parser.add_argument("--coins", type=int, default=200, help="Coins to grant on redeem")
    parser.add_argument(
        "--max-per-user",
        type=int,
        default=1,
        help="Max times the same user can be rewarded for this code (default 1)",
    )
    parser.add_argument(
        "--max-redemptions",
        type=int,
        default=None,
        help="Global redemption cap across all users (omit for unlimited)",
    )
    parser.add_argument(
        "--uri",
        default=os.environ.get(
            "MONGO_URI",
            "mongodb://127.0.0.1:27018/external_system?authSource=admin",
        ),
        help="MongoDB URI",
    )
    parser.add_argument("--db", default=os.environ.get("MONGO_DB", "external_system"))
    parser.add_argument("--disable", action="store_true", help="Set enabled=false")
    args = parser.parse_args()

    code = str(args.code).strip().upper()
    if not code:
        print("code is required", file=sys.stderr)
        return 2
    if args.coins <= 0:
        print("coins must be > 0", file=sys.stderr)
        return 2
    if args.max_per_user < 1:
        print("max-per-user must be >= 1", file=sys.stderr)
        return 2

    client = MongoClient(args.uri, serverSelectionTimeoutMS=8000)
    db = client[args.db]
    now = datetime.now(timezone.utc).isoformat()
    doc = {
        "code": code,
        "coins": int(args.coins),
        "enabled": not args.disable,
        "expires_at": None,
        "max_redemptions": args.max_redemptions,
        "max_per_user": int(args.max_per_user),
        "updated_at": now,
    }
    result = db["referral_campaigns"].update_one(
        {"code": code},
        {
            "$set": doc,
            "$setOnInsert": {"redemption_count": 0, "created_at": now},
        },
        upsert=True,
    )
    print(
        f"upserted referral_campaigns code={code} coins={args.coins} "
        f"max_per_user={args.max_per_user} max_redemptions={args.max_redemptions} "
        f"matched={result.matched_count} upserted_id={result.upserted_id}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
