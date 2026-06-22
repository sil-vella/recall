"""
Apple App Store in-app purchases: consumable coin verify + subscription verify (StoreKit 2 JWS).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

from bson import ObjectId
from flask import jsonify, request
from pymongo.errors import DuplicateKeyError

from core.modules.base_module import BaseModule
from core.modules.user_management_module import tier_rank_level_matcher as matcher
from utils.apple_storekit_client import (
    apple_billing_configured,
    resolve_transaction,
    subscription_is_active,
)
from utils.coin_catalog import (
    get_in_app_product_coins,
    get_premium_subscription_config,
    get_subscriber_coin_bonus_percent,
)
from utils.config.config import Config
from utils.dutch_game_credits import (
    credit_dutch_game_coins,
    effective_coin_grant,
    get_dutch_game_coin_balance,
    get_dutch_game_subscription_tier,
)

_APPLE_SUBSCRIPTIONS = "apple_subscriptions"


class AppleBillingModule(BaseModule):
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
            sub_coll = self.db_manager.db[_APPLE_SUBSCRIPTIONS]
            sub_coll.create_index([("original_transaction_id", 1)], unique=True)
            sub_coll.create_index([("user_id", 1)])
            coin_coll = self.db_manager.db["apple_coin_purchases"]
            coin_coll.create_index([("transaction_id", 1)], unique=True)
            coin_coll.create_index([("user_id", 1)])
        except Exception:
            pass

    def register_routes(self):
        self._register_route_helper(
            "/userauth/apple/verify-coin-purchase",
            self.verify_coin_purchase,
            methods=["POST"],
        )
        self._register_route_helper(
            "/userauth/apple/verify-subscription",
            self.verify_subscription,
            methods=["POST"],
        )
        self._register_route_helper(
            "/userauth/apple/subscription-status",
            self.subscription_status,
            methods=["GET"],
        )

    @staticmethod
    def _premium_apple_product_ids() -> Tuple[str, str]:
        cfg = get_premium_subscription_config()
        apple = cfg.get("apple_product_ids") if isinstance(cfg.get("apple_product_ids"), dict) else {}
        monthly = str(apple.get("monthly") or "").strip()
        yearly = str(apple.get("yearly") or "").strip()
        return monthly, yearly

    @staticmethod
    def _plan_key_for_product(product_id: str) -> str:
        monthly, yearly = AppleBillingModule._premium_apple_product_ids()
        if product_id == monthly:
            return "monthly"
        if product_id == yearly:
            return "yearly"
        return product_id

    def _apply_subscription_tier(
        self,
        user_oid: ObjectId,
        *,
        is_active: bool,
        product_id: str,
        expiry_iso: str,
        original_transaction_id: str,
        transaction_id: str,
    ) -> str:
        now_iso = datetime.now(timezone.utc).isoformat()
        plan_key = self._plan_key_for_product(product_id)
        if is_active:
            tier = matcher.TIER_PREMIUM
            sub_module = {
                "enabled": True,
                "plan": product_id,
                "expires_at": expiry_iso or None,
            }
        else:
            tier = matcher.TIER_REGULAR
            sub_module = {
                "enabled": False,
                "plan": None,
                "expires_at": None,
            }

        self.db_manager.db["users"].update_one(
            {"_id": user_oid},
            {
                "$set": {
                    "modules.dutch_game.subscription_tier": tier,
                    "modules.dutch_game.last_updated": now_iso,
                    "modules.subscription": sub_module,
                    "updated_at": now_iso,
                }
            },
        )

        coll = self.db_manager.db[_APPLE_SUBSCRIPTIONS]
        coll.update_one(
            {"original_transaction_id": original_transaction_id},
            {
                "$set": {
                    "user_id": str(user_oid),
                    "product_id": product_id,
                    "plan_key": plan_key,
                    "expiry_time": expiry_iso,
                    "is_active": is_active,
                    "last_transaction_id": transaction_id,
                    "last_verified_at": now_iso,
                },
                "$setOnInsert": {
                    "original_transaction_id": original_transaction_id,
                    "created_at": now_iso,
                },
            },
            upsert=True,
        )
        return tier

    def _complete_apple_coin_credit(
        self,
        *,
        user_id: str,
        user_oid: ObjectId,
        transaction_id: str,
        product_id: str,
        base_coins: int,
        coins_to_credit: int,
        subscriber_bonus: bool,
        original_transaction_id: str,
    ):
        now_iso = datetime.utcnow().isoformat()
        try:
            self.db_manager.db["apple_coin_purchases"].insert_one(
                {
                    "transaction_id": transaction_id,
                    "original_transaction_id": original_transaction_id,
                    "user_id": str(user_id),
                    "product_id": product_id,
                    "base_coins": base_coins,
                    "coins": coins_to_credit,
                    "coins_credited": coins_to_credit,
                    "subscriber_bonus_applied": subscriber_bonus,
                    "status": "completed",
                    "created_at": now_iso,
                    "completed_at": now_iso,
                }
            )
        except DuplicateKeyError:
            bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
            row = self.db_manager.find_one("apple_coin_purchases", {"transaction_id": transaction_id}) or {}
            return (
                jsonify(
                    {
                        "success": True,
                        "idempotent": True,
                        "duplicate": True,
                        "new_coin_balance": bal,
                        "coins_credited": int(row.get("coins_credited") or row.get("coins") or 0),
                        "subscriber_bonus_applied": bool(row.get("subscriber_bonus_applied")),
                    }
                ),
                200,
            )

        try:
            credit_dutch_game_coins(self.db_manager, user_oid, coins_to_credit)
        except Exception:
            self.db_manager.db["apple_coin_purchases"].delete_one({"transaction_id": transaction_id})
            return jsonify({"success": False, "error": "Failed to credit coins"}), 500

        bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
        return (
            jsonify(
                {
                    "success": True,
                    "new_coin_balance": bal,
                    "coins_credited": coins_to_credit,
                    "base_coins": base_coins,
                    "subscriber_bonus_applied": subscriber_bonus,
                }
            ),
            200,
        )

    def verify_coin_purchase(self):
        """JWT: body { product_id, signed_transaction } or { product_id, transaction_id }."""
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}),
                    401,
                )

            if not apple_billing_configured():
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Apple IAP verification is not configured",
                            "message": "Set APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, and APPLE_IAP_PRIVATE_KEY_FILE",
                        }
                    ),
                    503,
                )

            body = request.get_json() or {}
            product_id = (body.get("product_id") or body.get("productId") or "").strip()
            signed_transaction = (body.get("signed_transaction") or body.get("signedTransaction") or "").strip()
            transaction_id = (body.get("transaction_id") or body.get("transactionId") or "").strip()

            if not product_id:
                return jsonify({"success": False, "error": "product_id is required"}), 400
            if not signed_transaction and not transaction_id:
                return jsonify({"success": False, "error": "signed_transaction or transaction_id is required"}), 400

            catalog = get_in_app_product_coins()
            base_coins = int(catalog.get(product_id, 0) or 0)
            if base_coins <= 0:
                return jsonify({"success": False, "error": "Unknown or invalid product_id for coin catalog"}), 400

            try:
                user_oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            payload, err = resolve_transaction(
                signed_transaction=signed_transaction,
                transaction_id=transaction_id,
                expected_product_id=product_id,
            )
            if err or not payload:
                return jsonify({"success": False, "error": err or "Verification failed"}), 400

            verified_tx_id = str(payload.get("transaction_id") or "").strip()
            original_tx_id = str(payload.get("original_transaction_id") or verified_tx_id).strip()
            if not verified_tx_id:
                return jsonify({"success": False, "error": "Missing transaction id in verified payload"}), 400

            existing = self.db_manager.find_one("apple_coin_purchases", {"transaction_id": verified_tx_id})
            if existing:
                if str(existing.get("user_id") or "") != str(user_id):
                    return jsonify({"success": False, "error": "Transaction does not belong to this account"}), 403
                bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
                credited = int(existing.get("coins_credited") or existing.get("coins") or 0)
                return (
                    jsonify(
                        {
                            "success": True,
                            "idempotent": True,
                            "duplicate": True,
                            "new_coin_balance": bal,
                            "coins_credited": credited,
                            "base_coins": int(existing.get("base_coins") or base_coins),
                            "subscriber_bonus_applied": bool(existing.get("subscriber_bonus_applied")),
                        }
                    ),
                    200,
                )

            bonus_percent = get_subscriber_coin_bonus_percent()
            tier = get_dutch_game_subscription_tier(self.db_manager, user_oid)
            coins_to_credit = effective_coin_grant(base_coins, tier, bonus_percent)
            subscriber_bonus = coins_to_credit > base_coins

            return self._complete_apple_coin_credit(
                user_id=str(user_id),
                user_oid=user_oid,
                transaction_id=verified_tx_id,
                product_id=product_id,
                base_coins=base_coins,
                coins_to_credit=coins_to_credit,
                subscriber_bonus=subscriber_bonus,
                original_transaction_id=original_tx_id,
            )
        except Exception:
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def _sync_user_subscription_from_apple(
        self,
        user_oid: ObjectId,
        *,
        product_id: str,
        signed_transaction: str = "",
        transaction_id: str = "",
    ) -> Tuple[bool, str, str, int]:
        payload, err = resolve_transaction(
            signed_transaction=signed_transaction,
            transaction_id=transaction_id,
            expected_product_id=product_id,
        )
        if err or not payload:
            return False, "", "", 400 if err else 502

        monthly, yearly = self._premium_apple_product_ids()
        if product_id not in {monthly, yearly}:
            return False, "", "", 400

        is_active = subscription_is_active(payload)
        expiry_iso = str(payload.get("expires_at") or "")
        original_tx_id = str(payload.get("original_transaction_id") or payload.get("transaction_id") or "")
        tx_id = str(payload.get("transaction_id") or "")

        tier = self._apply_subscription_tier(
            user_oid,
            is_active=is_active,
            product_id=product_id,
            expiry_iso=expiry_iso,
            original_transaction_id=original_tx_id,
            transaction_id=tx_id,
        )
        return True, tier, expiry_iso, 200

    def verify_subscription(self):
        """JWT: body { product_id, signed_transaction } or { product_id, transaction_id }."""
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}),
                    401,
                )

            if not apple_billing_configured():
                return (
                    jsonify({"success": False, "error": "Apple IAP verification is not configured"}),
                    503,
                )

            body = request.get_json() or {}
            product_id = (body.get("product_id") or body.get("productId") or "").strip()
            signed_transaction = (body.get("signed_transaction") or body.get("signedTransaction") or "").strip()
            transaction_id = (body.get("transaction_id") or body.get("transactionId") or "").strip()

            if not product_id:
                return jsonify({"success": False, "error": "product_id is required"}), 400
            if not signed_transaction and not transaction_id:
                return jsonify({"success": False, "error": "signed_transaction or transaction_id is required"}), 400

            try:
                user_oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            payload, err = resolve_transaction(
                signed_transaction=signed_transaction,
                transaction_id=transaction_id,
                expected_product_id=product_id,
            )
            if err or not payload:
                return jsonify({"success": False, "error": err or "Verification failed"}), 400

            original_tx_id = str(payload.get("original_transaction_id") or "").strip()
            existing = None
            if original_tx_id:
                existing = self.db_manager.find_one(_APPLE_SUBSCRIPTIONS, {"original_transaction_id": original_tx_id})
                if existing and str(existing.get("user_id") or "") != str(user_id):
                    return jsonify({"success": False, "error": "Subscription does not belong to this account"}), 403

            ok, tier, expiry_iso, status = self._sync_user_subscription_from_apple(
                user_oid,
                product_id=product_id,
                signed_transaction=signed_transaction,
                transaction_id=transaction_id,
            )
            if not ok:
                return jsonify({"success": False, "error": "Apple subscription verification failed"}), status if status >= 400 else 502

            return (
                jsonify(
                    {
                        "success": True,
                        "subscription_tier": tier,
                        "expires_at": expiry_iso or None,
                        "duplicate": existing is not None,
                    }
                ),
                200,
            )
        except Exception:
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def subscription_status(self):
        """JWT: re-verify latest stored Apple subscription for this user."""
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}),
                    401,
                )

            try:
                user_oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            tier = get_dutch_game_subscription_tier(self.db_manager, user_oid)
            ledger = self.db_manager.db[_APPLE_SUBSCRIPTIONS].find_one(
                {"user_id": str(user_id)},
                sort=[("last_verified_at", -1)],
            )
            if not ledger:
                return (
                    jsonify(
                        {
                            "success": True,
                            "subscription_tier": tier or matcher.TIER_REGULAR,
                            "refreshed": False,
                        }
                    ),
                    200,
                )

            product_id = str(ledger.get("product_id") or "").strip()
            last_tx = str(ledger.get("last_transaction_id") or "").strip()
            if not product_id or not last_tx or not apple_billing_configured():
                return (
                    jsonify(
                        {
                            "success": True,
                            "subscription_tier": tier or matcher.TIER_REGULAR,
                            "refreshed": False,
                        }
                    ),
                    200,
                )

            ok, new_tier, expiry_iso, _status = self._sync_user_subscription_from_apple(
                user_oid,
                product_id=product_id,
                transaction_id=last_tx,
            )
            if not ok:
                return (
                    jsonify(
                        {
                            "success": True,
                            "subscription_tier": tier or matcher.TIER_REGULAR,
                            "refreshed": False,
                        }
                    ),
                    200,
                )

            return (
                jsonify(
                    {
                        "success": True,
                        "subscription_tier": new_tier,
                        "expires_at": expiry_iso or None,
                        "refreshed": True,
                    }
                ),
                200,
            )
        except Exception:
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def health_check(self) -> dict[str, Any]:
        ok = apple_billing_configured()
        bundle = (Config.APPLE_BUNDLE_ID or "").strip()
        env = (Config.APPLE_APP_STORE_ENVIRONMENT or "").strip()
        if ok:
            details = f"bundle={bundle} environment={env}"
        else:
            details = "Set APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, APPLE_IAP_PRIVATE_KEY_FILE, and Apple root certs"
        return {
            "module": self.module_name,
            "status": "healthy" if ok else "degraded",
            "details": details,
            "apple_billing_configured": ok,
        }
