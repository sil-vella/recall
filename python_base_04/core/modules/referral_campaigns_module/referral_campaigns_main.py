"""
Campaign referral codes: sync client-pending codes onto the user document and credit coins.
URL carries only the code; coin amounts come from the referral_campaigns collection.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from bson import ObjectId
from flask import jsonify, request

from core.modules.base_module import BaseModule
from utils.dutch_game_credits import credit_dutch_game_coins, get_dutch_game_coin_balance


class ReferralCampaignsModule(BaseModule):
    _CAMPAIGNS = "referral_campaigns"

    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.dependencies = ["user_management_module"]
        self.module_name = "ReferralCampaignsModule"

    def initialize(self, app_manager):
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.db_manager = app_manager.get_db_manager(role="read_write")
        self.register_routes()
        self._ensure_indexes()
        self._initialized = True

    def _ensure_indexes(self):
        try:
            coll = self.db_manager.db[self._CAMPAIGNS]
            coll.create_index("code", unique=True)
            coll.create_index([("enabled", 1), ("expires_at", 1)])
        except Exception:
            pass

    def register_routes(self):
        self._register_auth_route_helper(
            "/userauth/referrals/sync",
            self.sync_referral_codes,
            methods=["POST"],
        )

    @staticmethod
    def _normalize_code(raw: Any) -> str:
        return str(raw or "").strip().upper()

    @staticmethod
    def _parse_expires_at(value: Any) -> Optional[datetime]:
        if value is None or value == "":
            return None
        if isinstance(value, datetime):
            dt = value
        else:
            s = str(value).strip()
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            try:
                dt = datetime.fromisoformat(s)
            except ValueError:
                return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)

    @staticmethod
    def _max_per_user(campaign: dict) -> int:
        """Per-user reward cap for this code. Missing/invalid → 1 (once only)."""
        raw = campaign.get("max_per_user")
        if raw is None:
            return 1
        try:
            cap = int(raw)
        except (TypeError, ValueError):
            return 1
        return max(1, cap)

    @staticmethod
    def _user_code_count(
        code: str,
        counts: Dict[str, Any],
        existing_set: set,
    ) -> int:
        """How many times this user has already been rewarded for [code]."""
        raw = counts.get(code)
        if raw is not None:
            try:
                return max(0, int(raw))
            except (TypeError, ValueError):
                return 0
        # Legacy: code listed in referral_codes with no count map → counted as 1
        if code in existing_set:
            return 1
        return 0

    def _campaign_valid(self, campaign: dict, now: datetime) -> Optional[str]:
        """Return rejection reason or None if applicable."""
        if not campaign:
            return "not_found"
        if not campaign.get("enabled", False):
            return "disabled"
        expires = self._parse_expires_at(campaign.get("expires_at"))
        if expires is not None and now >= expires:
            return "expired"
        max_redemptions = campaign.get("max_redemptions")
        if max_redemptions is not None:
            try:
                cap = int(max_redemptions)
            except (TypeError, ValueError):
                cap = None
            if cap is not None and cap >= 0:
                count = int(campaign.get("redemption_count") or 0)
                if count >= cap:
                    return "cap_reached"
        try:
            coins = int(campaign.get("coins") or 0)
        except (TypeError, ValueError):
            coins = 0
        if coins <= 0:
            return "invalid_reward"
        return None

    def sync_referral_codes(self):
        """
        JWT body: { "codes": ["SUMMER50", ...] }

        For each code:
          1. Validate campaign (enabled, expiry, global max_redemptions, coins)
          2. If user reward count >= campaign.max_per_user → already_applied
          3. Else atomic $inc count + credit coins + inc global redemption_count
        """
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Authentication required",
                            "code": "JWT_REQUIRED",
                        }
                    ),
                    401,
                )

            body = request.get_json(silent=True) or {}
            raw_codes = body.get("codes")
            if not isinstance(raw_codes, list):
                return jsonify({"success": False, "error": "codes must be a list"}), 400

            # Dedupe while preserving order
            seen = set()
            codes: List[str] = []
            for item in raw_codes:
                code = self._normalize_code(item)
                if not code or code in seen:
                    continue
                seen.add(code)
                codes.append(code)

            if not codes:
                return jsonify({"success": False, "error": "codes list is empty"}), 400

            try:
                oid = ObjectId(user_id)
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            user_doc = self.db_manager.find_one("users", {"_id": oid}) or {}
            referrals = (user_doc.get("modules") or {}).get("referrals") or {}
            existing_codes = referrals.get("referral_codes") or []
            if not isinstance(existing_codes, list):
                existing_codes = []
            existing_set = {self._normalize_code(c) for c in existing_codes if c}

            raw_counts = referrals.get("referral_code_counts") or {}
            counts: Dict[str, Any] = raw_counts if isinstance(raw_counts, dict) else {}

            now = datetime.now(timezone.utc)
            added: List[str] = []
            already_applied: List[str] = []
            rejected: List[dict] = []
            coins_awarded = 0

            for code in codes:
                campaign = self.db_manager.find_one(self._CAMPAIGNS, {"code": code}) or {}
                reason = self._campaign_valid(campaign, now)
                if reason is not None:
                    rejected.append({"code": code, "reason": reason})
                    continue

                max_per_user = self._max_per_user(campaign)
                current_count = self._user_code_count(code, counts, existing_set)
                if current_count >= max_per_user:
                    already_applied.append(code)
                    continue

                # Migrate legacy presence → count=1 before atomic claim
                count_path = f"modules.referrals.referral_code_counts.{code}"
                if code in existing_set and counts.get(code) is None:
                    self.db_manager.db["users"].update_one(
                        {
                            "_id": oid,
                            count_path: {"$exists": False},
                        },
                        {"$set": {count_path: 1}},
                    )
                    counts[code] = 1
                    current_count = 1
                    if current_count >= max_per_user:
                        already_applied.append(code)
                        continue

                coins = int(campaign.get("coins") or 0)

                claim = self.db_manager.db["users"].update_one(
                    {
                        "_id": oid,
                        "$or": [
                            {count_path: {"$exists": False}},
                            {count_path: {"$lt": max_per_user}},
                        ],
                    },
                    {
                        "$inc": {count_path: 1},
                        "$addToSet": {"modules.referrals.referral_codes": code},
                        "$set": {
                            "modules.referrals.enabled": True,
                            "updated_at": now.isoformat(),
                        },
                    },
                )
                if claim.modified_count == 0:
                    already_applied.append(code)
                    counts[code] = max_per_user
                    existing_set.add(code)
                    continue

                new_count = current_count + 1
                counts[code] = new_count
                existing_set.add(code)

                try:
                    credit_dutch_game_coins(self.db_manager, oid, coins)
                except Exception:
                    # Roll back this redemption so client can retry
                    self.db_manager.db["users"].update_one(
                        {"_id": oid},
                        {"$inc": {count_path: -1}},
                    )
                    counts[code] = current_count
                    rejected.append({"code": code, "reason": "credit_failed"})
                    continue

                self.db_manager.db[self._CAMPAIGNS].update_one(
                    {"_id": campaign["_id"]},
                    {
                        "$inc": {"redemption_count": 1},
                        "$set": {"updated_at": now.isoformat()},
                    },
                )

                added.append(code)
                coins_awarded += coins

            if coins_awarded > 0:
                try:
                    from core.modules.dutch_game.utils.redis_read_cache import (
                        invalidate_init_stats,
                    )

                    invalidate_init_stats(self.app_manager, str(user_id))
                except Exception:
                    pass

            balance = get_dutch_game_coin_balance(self.db_manager, oid)
            return (
                jsonify(
                    {
                        "success": True,
                        "added": added,
                        "already_applied": already_applied,
                        "rejected": rejected,
                        "coins_awarded": coins_awarded,
                        "balance": balance,
                    }
                ),
                200,
            )
        except Exception as e:
            return jsonify({"success": False, "error": f"Referral sync failed: {e}"}), 500

    def health_check(self):
        return {
            "module": self.module_name,
            "status": "healthy" if self._initialized else "not_initialized",
            "details": "Campaign referral code sync and coin credit",
        }
