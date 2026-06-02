"""
Google Play in-app purchases: consumable coin verify + subscription verify (Android Publisher API).
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

from bson import ObjectId
from flask import jsonify, request
from pymongo.errors import DuplicateKeyError

from core.modules.base_module import BaseModule
from core.modules.user_management_module import tier_rank_level_matcher as matcher
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

_ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
_PLAY_SUBSCRIPTIONS = "play_subscriptions"
_SUBSCRIPTION_ACTIVE_STATES = frozenset(
    {
        "SUBSCRIPTION_STATE_ACTIVE",
        "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    }
)


class PlayBillingModule(BaseModule):
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.dependencies = ["user_management_module"]
        self._android_publisher: Optional[Any] = None

    def initialize(self, app_manager):
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.db_manager = app_manager.get_db_manager(role="read_write")
        self.register_routes()
        self._ensure_indexes()
        self._initialized = True

    def _ensure_indexes(self):
        try:
            coll = self.db_manager.db[_PLAY_SUBSCRIPTIONS]
            coll.create_index([("purchase_token", 1)], unique=True)
            coll.create_index([("user_id", 1)])
            coin_coll = self.db_manager.db["play_coin_purchases"]
            coin_coll.create_index([("purchase_token", 1)], unique=True)
            coin_coll.create_index([("user_id", 1)])
        except Exception:
            pass

    def _complete_play_coin_credit(
        self,
        *,
        user_id: str,
        user_oid: ObjectId,
        purchase_token: str,
        product_id: str,
        base_coins: int,
        coins_to_credit: int,
        subscriber_bonus: bool,
        order_id: str,
        service: Any,
        package: str,
        skip_play_consume: bool = False,
        ledger_status: str = "completed",
        recovered: bool = False,
    ):
        """Insert ledger, credit coins, optionally consume on Play (idempotent per purchase_token)."""
        now_iso = datetime.utcnow().isoformat()
        try:
            self.db_manager.db["play_coin_purchases"].insert_one(
                {
                    "purchase_token": purchase_token,
                    "user_id": str(user_id),
                    "product_id": product_id,
                    "base_coins": base_coins,
                    "coins": coins_to_credit,
                    "coins_credited": coins_to_credit,
                    "subscriber_bonus_applied": subscriber_bonus,
                    "order_id": order_id,
                    "status": "processing" if not skip_play_consume else ledger_status,
                    "recovered": recovered,
                    "created_at": now_iso,
                    **({"completed_at": now_iso} if skip_play_consume else {}),
                    **({"consume_ok": True} if skip_play_consume else {}),
                }
            )
        except DuplicateKeyError:
            bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
            row = self.db_manager.find_one("play_coin_purchases", {"purchase_token": purchase_token}) or {}
            return (
                jsonify(
                    {
                        "success": True,
                        "idempotent": True,
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
            self.db_manager.db["play_coin_purchases"].delete_one({"purchase_token": purchase_token})
            return jsonify({"success": False, "error": "Failed to credit coins"}), 500

        consume_ok = skip_play_consume
        if not skip_play_consume:
            consume_ok = True
            try:
                service.purchases().products().consume(
                    packageName=package,
                    productId=product_id,
                    token=purchase_token,
                ).execute()
            except Exception:
                consume_ok = False

            self.db_manager.db["play_coin_purchases"].update_one(
                {"purchase_token": purchase_token},
                {
                    "$set": {
                        "status": ledger_status,
                        "completed_at": datetime.utcnow().isoformat(),
                        "consume_ok": consume_ok,
                    }
                },
            )

        bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
        payload: Dict[str, Any] = {
            "success": True,
            "new_coin_balance": bal,
            "coins_credited": coins_to_credit,
            "base_coins": base_coins,
            "subscriber_bonus_applied": subscriber_bonus,
            "consume_ok": consume_ok,
        }
        if recovered:
            payload["recovered"] = True
        return jsonify(payload), 200

    def _get_android_publisher(self):
        if self._android_publisher is not None:
            return self._android_publisher
        pkg = (Config.GOOGLE_PLAY_PACKAGE_NAME or "").strip()
        sa_path = (Config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE or "").strip()
        if not pkg or not sa_path:
            return None
        if not os.path.isfile(sa_path):
            return None
        try:
            from google.oauth2 import service_account
            from googleapiclient.discovery import build

            creds = service_account.Credentials.from_service_account_file(
                sa_path,
                scopes=[_ANDROID_PUBLISHER_SCOPE],
            )
            self._android_publisher = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
            return self._android_publisher
        except Exception:
            self._android_publisher = None
            return None

    def register_routes(self):
        self._register_route_helper(
            "/userauth/play/verify-coin-purchase",
            self.verify_coin_purchase,
            methods=["POST"],
        )
        self._register_route_helper(
            "/userauth/play/verify-subscription",
            self.verify_subscription,
            methods=["POST"],
        )
        self._register_route_helper(
            "/userauth/play/subscription-status",
            self.subscription_status,
            methods=["GET"],
        )

    def _default_subscription_id(self) -> str:
        cfg = get_premium_subscription_config()
        return (cfg.get("product_id") or "premium_subscription").strip()

    def _fetch_subscription_v2(self, service: Any, package: str, purchase_token: str) -> Optional[Dict[str, Any]]:
        try:
            return (
                service.purchases()
                .subscriptionsv2()
                .get(packageName=package, token=purchase_token)
                .execute()
            )
        except Exception:
            return None

    @staticmethod
    def _parse_subscription_v2(sub: Dict[str, Any]) -> Tuple[bool, str, str, str]:
        """Return (is_active, subscription_state, expiry_iso, base_plan_id)."""
        state = str(sub.get("subscriptionState") or "").strip()
        expiry_iso = ""
        base_plan_id = ""
        line_items = sub.get("lineItems") or []
        if line_items and isinstance(line_items[0], dict):
            li = line_items[0]
            expiry_iso = str(li.get("expiryTime") or "").strip()
            offer = li.get("offerDetails") or {}
            if isinstance(offer, dict):
                base_plan_id = str(offer.get("basePlanId") or "").strip()
        is_active = state in _SUBSCRIPTION_ACTIVE_STATES
        return is_active, state, expiry_iso, base_plan_id

    def _apply_subscription_tier(
        self,
        user_oid: ObjectId,
        *,
        is_active: bool,
        subscription_id: str,
        base_plan_id: str,
        expiry_iso: str,
        purchase_token: str,
    ) -> str:
        now_iso = datetime.now(timezone.utc).isoformat()
        if is_active:
            tier = matcher.TIER_PREMIUM
            sub_module = {
                "enabled": True,
                "plan": subscription_id or self._default_subscription_id(),
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

        coll = self.db_manager.db[_PLAY_SUBSCRIPTIONS]
        coll.update_one(
            {"purchase_token": purchase_token},
            {
                "$set": {
                    "user_id": str(user_oid),
                    "subscription_id": subscription_id,
                    "base_plan_id": base_plan_id,
                    "expiry_time": expiry_iso,
                    "is_active": is_active,
                    "last_verified_at": now_iso,
                },
                "$setOnInsert": {"purchase_token": purchase_token, "created_at": now_iso},
            },
            upsert=True,
        )
        return tier

    def _sync_user_subscription_from_play(
        self,
        user_oid: ObjectId,
        purchase_token: str,
        subscription_id: str,
        base_plan_id_hint: str = "",
    ) -> Tuple[bool, str, str, int]:
        """Verify token with Play and update user tier. Returns (success, tier, expiry_iso, http_status)."""
        service = self._get_android_publisher()
        package = (Config.GOOGLE_PLAY_PACKAGE_NAME or "").strip()
        if not service or not package:
            return False, "", "", 503

        sub = self._fetch_subscription_v2(service, package, purchase_token)
        if not sub:
            return False, "", "", 502

        is_active, state, expiry_iso, base_plan_id = self._parse_subscription_v2(sub)
        if base_plan_id_hint and not base_plan_id:
            base_plan_id = base_plan_id_hint

        tier = self._apply_subscription_tier(
            user_oid,
            is_active=is_active,
            subscription_id=subscription_id or self._default_subscription_id(),
            base_plan_id=base_plan_id,
            expiry_iso=expiry_iso,
            purchase_token=purchase_token,
        )
        return True, tier, expiry_iso, 200

    def verify_subscription(self):
        """JWT: body { purchase_token, subscription_id?, base_plan_id? }."""
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}),
                    401,
                )

            body = request.get_json() or {}
            purchase_token = (body.get("purchase_token") or body.get("purchaseToken") or "").strip()
            if len(purchase_token) < 8:
                return jsonify({"success": False, "error": "purchase_token is required"}), 400

            subscription_id = (body.get("subscription_id") or body.get("subscriptionId") or "").strip()
            if not subscription_id:
                subscription_id = self._default_subscription_id()
            base_plan_id = (body.get("base_plan_id") or body.get("basePlanId") or "").strip()

            try:
                user_oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            existing = self.db_manager.find_one(_PLAY_SUBSCRIPTIONS, {"purchase_token": purchase_token})
            if existing and str(existing.get("user_id") or "") != str(user_id):
                return jsonify({"success": False, "error": "Purchase token does not belong to this account"}), 403

            ok, tier, expiry_iso, status = self._sync_user_subscription_from_play(
                user_oid, purchase_token, subscription_id, base_plan_id
            )
            if not ok:
                if status == 503:
                    return (
                        jsonify(
                            {
                                "success": False,
                                "error": "Google Play verification is not configured",
                            }
                        ),
                        503,
                    )
                return jsonify({"success": False, "error": "Play subscription verification failed"}), 502

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
        """JWT: re-verify latest stored Play subscription token for this user."""
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
            ledger = self.db_manager.db[_PLAY_SUBSCRIPTIONS].find_one(
                {"user_id": str(user_id)},
                sort=[("last_verified_at", -1)],
            )
            if not ledger or not (ledger.get("purchase_token") or "").strip():
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

            purchase_token = str(ledger["purchase_token"]).strip()
            subscription_id = str(ledger.get("subscription_id") or self._default_subscription_id())
            base_plan_id = str(ledger.get("base_plan_id") or "")

            ok, new_tier, expiry_iso, status = self._sync_user_subscription_from_play(
                user_oid, purchase_token, subscription_id, base_plan_id
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

    def verify_coin_purchase(self):
        """JWT: body { product_id, purchase_token }. Credits coins once per purchase_token (idempotent)."""
        try:
            user_id = getattr(request, "user_id", None)
            if not user_id:
                return (
                    jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}),
                    401,
                )

            body = request.get_json() or {}
            product_id = (body.get("product_id") or body.get("productId") or "").strip()
            purchase_token = (body.get("purchase_token") or body.get("purchaseToken") or "").strip()
            if not product_id or not purchase_token:
                return (
                    jsonify({"success": False, "error": "product_id and purchase_token are required"}),
                    400,
                )

            service = self._get_android_publisher()
            package = (Config.GOOGLE_PLAY_PACKAGE_NAME or "").strip()
            if not service or not package:
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Google Play verification is not configured",
                            "message": "Set GOOGLE_PLAY_PACKAGE_NAME and GOOGLE_PLAY_SERVICE_ACCOUNT_FILE",
                        }
                    ),
                    503,
                )

            catalog = get_in_app_product_coins()
            base_coins = int(catalog.get(product_id, 0) or 0)
            if base_coins <= 0:
                return jsonify({"success": False, "error": "Unknown or invalid product_id for coin catalog"}), 400

            try:
                user_oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            bonus_percent = get_subscriber_coin_bonus_percent()
            tier = get_dutch_game_subscription_tier(self.db_manager, user_oid)
            coins_to_credit = effective_coin_grant(base_coins, tier, bonus_percent)
            subscriber_bonus = coins_to_credit > base_coins

            existing = self.db_manager.find_one("play_coin_purchases", {"purchase_token": purchase_token})
            if existing:
                if str(existing.get("user_id") or "") != str(user_id):
                    return jsonify({"success": False, "error": "Purchase token does not belong to this account"}), 403
                bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
                credited = int(existing.get("coins_credited") or existing.get("coins") or 0)
                return (
                    jsonify(
                        {
                            "success": True,
                            "idempotent": True,
                            "new_coin_balance": bal,
                            "coins_credited": credited,
                            "base_coins": int(existing.get("base_coins") or base_coins),
                            "subscriber_bonus_applied": bool(existing.get("subscriber_bonus_applied")),
                        }
                    ),
                    200,
                )

            try:
                pr = (
                    service.purchases()
                    .products()
                    .get(packageName=package, productId=product_id, token=purchase_token)
                    .execute()
                )
            except Exception as e:
                status = getattr(getattr(e, "resp", None), "status", None)
                err = str(e)
                if status == 404 or "404" in err or "notFound" in err:
                    return jsonify({"success": False, "error": "Invalid or expired purchase token"}), 400
                return jsonify({"success": False, "error": "Play verification failed", "message": err}), 502

            purchase_state = int(pr.get("purchaseState", -1))
            consumption_state = int(pr.get("consumptionState", -1))
            if purchase_state != 0:
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Purchase not in purchased state",
                            "purchase_state": purchase_state,
                        }
                    ),
                    400,
                )
            order_id = str(pr.get("orderId") or "")
            if consumption_state != 0:
                # Paid on Play and token already consumed (e.g. client ack) but verify failed before ledger — recover.
                return self._complete_play_coin_credit(
                    user_id=str(user_id),
                    user_oid=user_oid,
                    purchase_token=purchase_token,
                    product_id=product_id,
                    base_coins=base_coins,
                    coins_to_credit=coins_to_credit,
                    subscriber_bonus=subscriber_bonus,
                    order_id=order_id,
                    service=service,
                    package=package,
                    skip_play_consume=True,
                    ledger_status="recovered",
                    recovered=True,
                )

            return self._complete_play_coin_credit(
                user_id=str(user_id),
                user_oid=user_oid,
                purchase_token=purchase_token,
                product_id=product_id,
                base_coins=base_coins,
                coins_to_credit=coins_to_credit,
                subscriber_bonus=subscriber_bonus,
                order_id=order_id,
                service=service,
                package=package,
            )
        except Exception:
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def health_check(self) -> dict[str, Any]:
        pkg = (Config.GOOGLE_PLAY_PACKAGE_NAME or "").strip()
        sa = (Config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE or "").strip()
        pkg_ok = bool(pkg)
        sa_path_set = bool(sa)
        sa_file_ok = sa_path_set and os.path.isfile(sa)
        ok = pkg_ok and sa_file_ok
        if ok:
            details = f"package={pkg} service_account_file={sa}"
        elif not pkg_ok:
            details = "GOOGLE_PLAY_PACKAGE_NAME is not set (add to .env.prod and redeploy)"
        elif not sa_path_set:
            details = "GOOGLE_PLAY_SERVICE_ACCOUNT_FILE is not set (use /app/secrets/google-play-publisher.json in container)"
        else:
            details = f"GOOGLE_PLAY_SERVICE_ACCOUNT_FILE not readable: {sa} (mount secrets/ on VPS and redeploy flask)"
        return {
            "module": self.module_name,
            "status": "healthy" if ok else "degraded",
            "details": details,
            "package_configured": pkg_ok,
            "service_account_path_set": sa_path_set,
            "service_account_file_readable": sa_file_ok,
        }
