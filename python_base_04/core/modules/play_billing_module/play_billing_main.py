"""
Google Play in-app purchases: verify purchaseToken with Android Publisher API,
credit Dutch game coins (catalog SSOT), consume on Play (consumables).
"""

from __future__ import annotations

import os
from datetime import datetime
from typing import Any, Optional

from bson import ObjectId
from flask import jsonify, request
from pymongo.errors import DuplicateKeyError

from core.modules.base_module import BaseModule
from utils.coin_catalog import get_in_app_product_coins
from utils.config.config import Config
from utils.dutch_game_credits import credit_dutch_game_coins, get_dutch_game_coin_balance

_ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"


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
        self._initialized = True

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
            coins = int(catalog.get(product_id, 0) or 0)
            if coins <= 0:
                return jsonify({"success": False, "error": "Unknown or invalid product_id for coin catalog"}), 400

            try:
                user_oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            existing = self.db_manager.find_one("play_coin_purchases", {"purchase_token": purchase_token})
            if existing:
                if str(existing.get("user_id") or "") != str(user_id):
                    return jsonify({"success": False, "error": "Purchase token does not belong to this account"}), 403
                bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
                return (
                    jsonify(
                        {
                            "success": True,
                            "idempotent": True,
                            "new_coin_balance": bal,
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
            # 0 = purchased (Payment received)
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
            # 0 = not consumed (consumable still active on Play)
            if consumption_state != 0:
                return (
                    jsonify(
                        {
                            "success": False,
                            "error": "Purchase already consumed on Play; no matching ledger",
                            "consumption_state": consumption_state,
                        }
                    ),
                    409,
                )

            order_id = str(pr.get("orderId") or "")
            now_iso = datetime.utcnow().isoformat()

            try:
                self.db_manager.db["play_coin_purchases"].insert_one(
                    {
                        "purchase_token": purchase_token,
                        "user_id": str(user_id),
                        "product_id": product_id,
                        "coins": coins,
                        "order_id": order_id,
                        "status": "processing",
                        "created_at": now_iso,
                    }
                )
            except DuplicateKeyError:
                bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
                return jsonify({"success": True, "idempotent": True, "new_coin_balance": bal}), 200

            try:
                credit_dutch_game_coins(self.db_manager, user_oid, coins)
            except Exception as e:
                self.db_manager.db["play_coin_purchases"].delete_one({"purchase_token": purchase_token})
                return jsonify({"success": False, "error": "Failed to credit coins"}), 500

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
                        "status": "completed",
                        "completed_at": datetime.utcnow().isoformat(),
                        "consume_ok": consume_ok,
                    }
                },
            )

            bal = get_dutch_game_coin_balance(self.db_manager, user_oid)
            return (
                jsonify(
                    {
                        "success": True,
                        "new_coin_balance": bal,
                        "consume_ok": consume_ok,
                    }
                ),
                200,
            )
        except Exception:
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def health_check(self) -> dict[str, Any]:
        pkg = (Config.GOOGLE_PLAY_PACKAGE_NAME or "").strip()
        sa = (Config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE or "").strip()
        ok = bool(pkg) and bool(sa) and os.path.isfile(sa)
        return {
            "module": self.module_name,
            "status": "healthy" if ok else "degraded",
            "details": "GOOGLE_PLAY_* paths configured" if ok else "Set GOOGLE_PLAY_PACKAGE_NAME and a readable GOOGLE_PLAY_SERVICE_ACCOUNT_FILE",
        }
