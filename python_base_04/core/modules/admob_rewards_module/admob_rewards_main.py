"""
AdMob rewarded flow: client shows RewardedAd, then POSTs an idempotent claim.
Caps per UTC day. Does not verify Google SSV yet — add server-side verification for production hardening.
"""

from __future__ import annotations

from datetime import datetime, timezone

from bson import ObjectId
from flask import jsonify, request
from pymongo.errors import DuplicateKeyError

from core.modules.base_module import BaseModule
from utils.config.config import Config
from utils.dutch_game_credits import credit_dutch_game_coins, get_dutch_game_coin_balance


class AdmobRewardsModule(BaseModule):
    _CLAIMS = "admob_rewarded_claims"

    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.dependencies = ["user_management_module"]

    def initialize(self, app_manager):
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.db_manager = app_manager.get_db_manager(role="read_write")
        self.register_routes()
        self._ensure_indexes()
        self._initialized = True

    def _ensure_indexes(self):
        try:
            coll = self.db_manager.db[self._CLAIMS]
            coll.create_index([("user_id", 1), ("client_nonce", 1)], unique=True)
            coll.create_index([("user_id", 1), ("created_at", 1)])
        except Exception:
            pass

    def register_routes(self):
        self._register_route_helper(
            "/userauth/admob/claim-rewarded-ad",
            self.claim_rewarded_ad,
            methods=["POST"],
        )

    def claim_rewarded_ad(self):
        """JWT: body { client_nonce: str }. Idempotent per (user, nonce); daily cap in Config."""
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}),
                    401,
                )

            body = request.get_json() or {}
            client_nonce = (body.get("client_nonce") or "").strip()
            if len(client_nonce) < 8:
                return jsonify({"success": False, "error": "client_nonce is required (min 8 chars)"}), 400

            coins = int(Config.ADMOB_REWARDED_COINS_PER_CLAIM or 0)
            daily_cap = int(Config.ADMOB_REWARDED_DAILY_CAP or 0)
            if coins <= 0 or daily_cap <= 0:
                return jsonify({"success": False, "error": "Rewarded ad grants are not configured"}), 503

            try:
                oid = ObjectId(user_id)
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            user_doc = self.db_manager.find_one("users", {"_id": oid}) or {}
            dg = (user_doc.get("modules") or {}).get("dutch_game") or {}
            tier = str(dg.get("subscription_tier") or "").strip().lower()
            if tier == "premium":
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Premium subscription does not include rewarded ad grants",
                            "code": "PREMIUM_NO_ADS",
                        }
                    ),
                    403,
                )

            now = datetime.now(timezone.utc)
            day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

            coll = self.db_manager.db[self._CLAIMS]
            used_today = coll.count_documents({"user_id": oid, "created_at": {"$gte": day_start}})
            if used_today >= daily_cap:
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Daily rewarded ad limit reached",
                            "code": "DAILY_CAP",
                        }
                    ),
                    429,
                )

            existing = self.db_manager.find_one(self._CLAIMS, {"user_id": oid, "client_nonce": client_nonce})
            if existing:
                bal = get_dutch_game_coin_balance(self.db_manager, oid)
                return (
                    jsonify(
                        {
                            "success": True,
                            "duplicate": True,
                            "coins_credited": int(existing.get("coins") or 0),
                            "balance": bal,
                        }
                    ),
                    200,
                )

            doc = {
                "user_id": oid,
                "client_nonce": client_nonce,
                "coins": coins,
                "created_at": now,
            }
            try:
                ins = coll.insert_one(doc)
            except DuplicateKeyError:
                row = self.db_manager.find_one(self._CLAIMS, {"user_id": oid, "client_nonce": client_nonce}) or {}
                bal = get_dutch_game_coin_balance(self.db_manager, oid)
                return (
                    jsonify(
                        {
                            "success": True,
                            "duplicate": True,
                            "coins_credited": int(row.get("coins") or 0),
                            "balance": bal,
                        }
                    ),
                    200,
                )

            try:
                credit_dutch_game_coins(self.db_manager, oid, coins)
            except Exception:
                coll.delete_one({"_id": ins.inserted_id})
                return jsonify({"success": False, "error": "Could not credit coins"}), 500

            bal = get_dutch_game_coin_balance(self.db_manager, oid)
            return (
                jsonify(
                    {
                        "success": True,
                        "coins_credited": coins,
                        "balance": bal,
                    }
                ),
                200,
            )

        except Exception:
            return jsonify({"success": False, "error": "Internal server error"}), 500
