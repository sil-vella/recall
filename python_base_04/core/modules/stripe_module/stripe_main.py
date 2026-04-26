from core.modules.base_module import BaseModule
from core.managers.database_manager import DatabaseManager
from tools.logger.custom_logging import custom_log
from flask import request, jsonify, current_app
from datetime import datetime
from typing import Dict, Any, Optional
import stripe
import os
import hmac
import hashlib
import json
from decimal import Decimal

from bson import ObjectId
import urllib.parse

import requests

# Coin purchase / Checkout Session + webhook tracing for testing
LOGGING_SWITCH = False

# Play / App Store product id → Dutch game coins (must match client display mapping).
REVENUECAT_COIN_PRODUCT_COINS = {
    "starter_pack_100_coin": 100,
    "coins_100": 100,
    "coins_500": 500,
    "coins_1000": 1000,
    "coins_2500": 2500,
    "coins_5000": 5000,
    "coins_10000": 10000,
}


class StripeModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the StripeModule."""
        super().__init__(app_manager)
        self.dependencies = ["communications_module", "user_management", "transactions"]
        
        # Initialize Stripe with secure key management
        self.stripe = None
        self.webhook_secret = None
        self._initialize_stripe()

    def _initialize_stripe(self):
        """Initialize Stripe with secure configuration."""
        try:
            # Get Stripe keys from Config (Vault > Files > Environment > Default)
            from utils.config.config import Config
            
            stripe_secret_key = Config.STRIPE_SECRET_KEY
            stripe_publishable_key = Config.STRIPE_PUBLISHABLE_KEY
            self.webhook_secret = Config.STRIPE_WEBHOOK_SECRET
            
            if not stripe_secret_key:
                return
                
            # Initialize Stripe
            stripe.api_key = stripe_secret_key
            stripe.api_version = Config.STRIPE_API_VERSION
            self.stripe = stripe
            
        except Exception as e:
            self.stripe = None

    def initialize(self, app_manager):
        """Initialize the StripeModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        
        # Get database manager through app_manager
        self.db_manager = app_manager.get_db_manager(role="read_write")
        
        self.register_routes()
        self._initialized = True

    def register_routes(self):
        """Register Stripe-related routes."""
        self._register_route_helper("/stripe/create-payment-intent", self.create_payment_intent, methods=["POST"])
        self._register_route_helper("/stripe/confirm-payment", self.confirm_payment, methods=["POST"])
        self._register_route_helper("/stripe/webhook", self.handle_webhook, methods=["POST"])
        self._register_route_helper("/stripe/payment-status/<payment_intent_id>", self.get_payment_status, methods=["GET"])
        self._register_route_helper("/stripe/credit-packages", self.get_credit_packages, methods=["GET"])
        # Dutch game: web coin packs (Checkout Session + webhook → modules.dutch_game.coins)
        self._register_route_helper(
            "/public/stripe/coin-packages",
            self.list_coin_packages_public,
            methods=["GET"],
        )
        self._register_route_helper(
            "/userauth/stripe/create-coin-checkout-session",
            self.create_coin_checkout_session,
            methods=["POST"],
        )
        self._register_route_helper(
            "/userauth/stripe/verify-coin-checkout-session",
            self.verify_coin_checkout_session,
            methods=["POST"],
        )
        self._register_route_helper(
            "/userauth/revenuecat/verify-coin-purchase",
            self.verify_revenuecat_coin_purchase,
            methods=["POST"],
        )
        self._register_route_helper("/stripe/customers", self.create_customer, methods=["POST"])
        self._register_route_helper("/stripe/customers/<customer_id>", self.get_customer, methods=["GET"])
        self._register_route_helper("/stripe/payment-methods", self.list_payment_methods, methods=["GET"])
        self._register_route_helper("/stripe/payment-methods/<payment_method_id>", self.get_payment_method, methods=["GET"])

    def create_payment_intent(self):
        """Create a Stripe payment intent for credit purchase."""
        try:
            if not self.stripe:
                return jsonify({
                    "success": False,
                    "error": "Stripe is not configured"
                }), 503

            data = request.get_json()
            
            # Validate required fields
            required_fields = ['user_id', 'amount', 'currency']
            for field in required_fields:
                if not data.get(field):
                    return jsonify({
                        "success": False,
                        "error": f"Missing required field: {field}"
                    }), 400

            user_id = data['user_id']
            amount = data['amount']
            currency = data['currency']
            
            # Validate amount (convert to cents for Stripe)
            try:
                amount_cents = int(float(amount) * 100)
                if amount_cents <= 0:
                    return jsonify({
                        "success": False,
                        "error": "Amount must be greater than 0"
                    }), 400
            except ValueError:
                return jsonify({
                    "success": False,
                    "error": "Invalid amount format"
                }), 400

            # Generate idempotency key for this request
            import uuid
            idempotency_key = str(uuid.uuid4())
            
            # Create payment intent with idempotency
            payment_intent = self.stripe.PaymentIntent.create(
                amount=amount_cents,
                currency=currency.lower(),
                metadata={
                    'user_id': user_id,
                    'purchase_type': 'credits',
                    'amount_usd': str(amount)
                },
                automatic_payment_methods={
                    'enabled': True,
                },
                idempotency_key=idempotency_key
            )

            return jsonify({
                "success": True,
                "client_secret": payment_intent.client_secret,
                "payment_intent_id": payment_intent.id,
                "amount": amount,
                "currency": currency
            }), 200

        except stripe.error.CardError as e:
            return jsonify({
                "success": False,
                "error": "Card declined",
                "error_code": e.code,
                "decline_code": e.decline_code,
                "message": str(e)
            }), 402
        except stripe.error.InvalidRequestError as e:
            return jsonify({
                "success": False,
                "error": "Invalid request parameters",
                "error_code": e.code,
                "param": e.param,
                "message": str(e)
            }), 400
        except stripe.error.AuthenticationError as e:
            return jsonify({
                "success": False,
                "error": "Authentication failed",
                "message": "Invalid API key"
            }), 401
        except stripe.error.APIConnectionError as e:
            return jsonify({
                "success": False,
                "error": "Network error",
                "message": "Unable to connect to Stripe"
            }), 503
        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Payment processing error: {str(e)}",
                "error_code": getattr(e, 'code', None)
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def confirm_payment(self):
        """Confirm a payment and process credit purchase."""
        try:
            data = request.get_json()
            
            if not data.get('payment_intent_id'):
                return jsonify({
                    "success": False,
                    "error": "Payment intent ID is required"
                }), 400

            payment_intent_id = data['payment_intent_id']
            
            # Retrieve payment intent from Stripe
            payment_intent = self.stripe.PaymentIntent.retrieve(payment_intent_id)
            
            if payment_intent.status != 'succeeded':
                return jsonify({
                    "success": False,
                    "error": f"Payment not successful. Status: {payment_intent.status}"
                }), 400

            # Extract metadata
            user_id = payment_intent.metadata.get('user_id')
            amount_usd = float(payment_intent.metadata.get('amount_usd', 0))
            
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "Invalid payment intent - missing user ID"
                }), 400

            # Process credit purchase through transactions module
            credit_amount = self._calculate_credits_from_usd(amount_usd)
            
            # Create transaction record through queue system
            transaction_data = {
                'user_id': user_id,
                'payment_intent_id': payment_intent_id,
                'amount_usd': amount_usd,
                'credits_purchased': credit_amount,
                'status': 'completed',
                'payment_method': 'stripe',
                'created_at': datetime.utcnow().isoformat(),
                'stripe_payment_intent': payment_intent_id
            }
            
            # Use database queue system
            transaction_id = self.db_manager.insert("credit_purchases", transaction_data)
            
            if not transaction_id:
                return jsonify({
                    "success": False,
                    "error": "Failed to record transaction"
                }), 500

            # Update user wallet through transactions module
            self._update_user_credits(user_id, credit_amount)

            return jsonify({
                "success": True,
                "message": "Payment confirmed and credits added",
                "data": {
                    "transaction_id": transaction_id,
                    "credits_purchased": credit_amount,
                    "amount_paid": amount_usd,
                    "payment_intent_id": payment_intent_id
                }
            }), 200

        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Payment confirmation error: {str(e)}"
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def handle_webhook(self):
        """Handle Stripe webhooks securely."""
        try:
            custom_log("Stripe webhook: request received", level="INFO", isOn=LOGGING_SWITCH)
            if not self.webhook_secret:
                custom_log("Stripe webhook: missing STRIPE_WEBHOOK_SECRET", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "error": "Webhook secret not configured"
                }), 503

            # Get the webhook payload
            payload = request.get_data()
            sig_header = request.headers.get('Stripe-Signature')
            custom_log(
                f"Stripe webhook: payload_bytes={len(payload)} has_signature={bool(sig_header)}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )

            if not sig_header:
                custom_log("Stripe webhook: missing Stripe-Signature header", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "error": "Missing Stripe signature"
                }), 400

            # Verify webhook signature
            try:
                event = stripe.Webhook.construct_event(
                    payload, sig_header, self.webhook_secret
                )
                custom_log(
                    f"Stripe webhook: signature verified event_type={event.get('type')}",
                    level="INFO",
                    isOn=LOGGING_SWITCH,
                )
            except ValueError as e:
                custom_log(f"Stripe webhook: invalid payload ({e})", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({"error": "Invalid payload"}), 400
            except stripe.error.SignatureVerificationError as e:
                custom_log(f"Stripe webhook: signature verification failed ({e})", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({"error": "Invalid signature"}), 400

            # Handle the event
            if event['type'] == 'payment_intent.succeeded':
                self._handle_payment_succeeded(event['data']['object'])
            elif event['type'] == 'payment_intent.payment_failed':
                self._handle_payment_failed(event['data']['object'])
            elif event['type'] == 'charge.dispute.created':
                self._handle_dispute_created(event['data']['object'])
            elif event['type'] == 'checkout.session.completed':
                self._handle_checkout_session_completed(event['data']['object'])
            else:
                custom_log(
                    f"Stripe webhook: unhandled event_type={event['type']}",
                    level="INFO",
                    isOn=LOGGING_SWITCH,
                )

            custom_log(f"Stripe webhook: processed event_type={event['type']}", level="INFO", isOn=LOGGING_SWITCH)
            return jsonify({"success": True}), 200

        except Exception as e:
            custom_log(f"Stripe webhook: processing error {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "error": "Webhook processing error"
            }), 500

    def _handle_payment_succeeded(self, payment_intent):
        """Handle successful payment webhook."""
        try:
            user_id = payment_intent.metadata.get('user_id')
            payment_intent_id = payment_intent.id
            amount_usd = float(payment_intent.metadata.get('amount_usd', 0))
            
            # Process credits through queue system
            credit_amount = self._calculate_credits_from_usd(amount_usd)
            self._update_user_credits(user_id, credit_amount)
            
        except Exception as e:
            pass

    def _handle_payment_failed(self, payment_intent):
        """Handle failed payment webhook."""
        try:
            user_id = payment_intent.metadata.get('user_id')
            payment_intent_id = payment_intent.id
            
            # Log failed payment for monitoring
            failed_payment_data = {
                'user_id': user_id,
                'payment_intent_id': payment_intent_id,
                'status': 'failed',
                'created_at': datetime.utcnow().isoformat(),
                'failure_reason': payment_intent.last_payment_error.get('message', 'Unknown error') if payment_intent.last_payment_error else 'Unknown error'
            }
            
            self.db_manager.insert("failed_payments", failed_payment_data)
            
        except Exception as e:
            pass

    def _handle_dispute_created(self, dispute):
        """Handle dispute created webhook."""
        try:
            payment_intent_id = dispute.payment_intent
            
            # Log dispute for manual review
            dispute_data = {
                'payment_intent_id': payment_intent_id,
                'dispute_id': dispute.id,
                'amount': dispute.amount,
                'reason': dispute.reason,
                'status': dispute.status,
                'created_at': datetime.utcnow().isoformat()
            }
            
            self.db_manager.insert("disputes", dispute_data)
            
        except Exception as e:
            pass

    @staticmethod
    def _coin_package_rows():
        """SSOT for Dutch coin pack keys, labels, coin amounts, and configured Stripe Price IDs."""
        from utils.config.config import Config

        def _pid(v):
            s = (v or "").strip()
            return s if s else None

        return (
            {"key": "starter", "label": "Starter", "coins": 100, "price_id": _pid(Config.STRIPE_PRICE_COIN_STARTER)},
            {"key": "casual", "label": "Casual", "coins": 300, "price_id": _pid(Config.STRIPE_PRICE_COIN_CASUAL)},
            {"key": "popular", "label": "Popular", "coins": 700, "price_id": _pid(Config.STRIPE_PRICE_COIN_POPULAR)},
            {"key": "grinder", "label": "Grinder", "coins": 1500, "price_id": _pid(Config.STRIPE_PRICE_COIN_GRINDER)},
            {"key": "pro", "label": "Pro", "coins": 3500, "price_id": _pid(Config.STRIPE_PRICE_COIN_PRO)},
        )

    def list_coin_packages_public(self):
        """Which coin packages exist and whether Stripe price IDs are configured (no secrets)."""
        try:
            packages = []
            for row in self._coin_package_rows():
                packages.append(
                    {
                        "key": row["key"],
                        "label": row["label"],
                        "coins": row["coins"],
                        "available": row["price_id"] is not None,
                    }
                )
            return jsonify({"success": True, "packages": packages}), 200
        except Exception as e:
            custom_log(f"Stripe list_coin_packages_public error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Failed to list packages"}), 500

    def create_coin_checkout_session(self):
        """Create a Stripe Checkout Session for a Dutch coin pack (JWT: request.user_id)."""
        try:
            if not self.stripe:
                return jsonify({"success": False, "error": "Stripe is not configured"}), 503

            from utils.config.config import Config

            user_id = getattr(request, "user_id", None)
            if not user_id:
                return jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}), 401

            body = request.get_json() or {}
            package_key = (body.get("package_key") or "").strip().lower()
            if not package_key:
                return jsonify({"success": False, "error": "package_key is required"}), 400
            custom_log(
                f"create_coin_checkout_session: user_id={user_id} package_key={package_key}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )

            selected = None
            for row in self._coin_package_rows():
                if row["key"] == package_key:
                    selected = row
                    break
            if not selected or not selected.get("price_id"):
                return jsonify({"success": False, "error": "Invalid or unavailable package"}), 400

            success_url = (Config.STRIPE_COIN_CHECKOUT_SUCCESS_URL or "").strip()
            cancel_url = (Config.STRIPE_COIN_CHECKOUT_CANCEL_URL or "").strip()
            custom_log(
                f"create_coin_checkout_session: success_url={success_url} cancel_url={cancel_url}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
            if not success_url or not cancel_url:
                return jsonify(
                    {
                        "success": False,
                        "error": "Checkout URLs not configured",
                        "message": "Set STRIPE_COIN_CHECKOUT_SUCCESS_URL and STRIPE_COIN_CHECKOUT_CANCEL_URL",
                    }
                ), 503

            session = self.stripe.checkout.Session.create(
                mode="payment",
                line_items=[{"price": selected["price_id"], "quantity": 1}],
                success_url=success_url,
                cancel_url=cancel_url,
                client_reference_id=str(user_id),
                metadata={
                    "user_id": str(user_id),
                    "coins": str(int(selected["coins"])),
                    "package_key": package_key,
                    "purchase_type": "dutch_coins",
                },
            )
            custom_log(
                f"create_coin_checkout_session: created session_id={session.id} package_key={package_key}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )

            return jsonify({"success": True, "url": session.url, "session_id": session.id}), 200

        except stripe.error.StripeError as e:
            custom_log(f"Stripe create_coin_checkout_session: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": str(e)}), 400
        except Exception as e:
            custom_log(f"create_coin_checkout_session error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def verify_coin_checkout_session(self):
        """
        After Checkout redirect: retrieve the session from Stripe and run the same credit path as the webhook.
        Use when webhooks cannot reach the server (e.g. localhost). Idempotent via stripe_coin_purchases.
        """
        try:
            if not self.stripe:
                return jsonify({"success": False, "error": "Stripe is not configured"}), 503

            user_id = getattr(request, "user_id", None)
            if not user_id:
                return jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}), 401

            body = request.get_json() or {}
            session_id = (body.get("session_id") or "").strip()
            if not session_id:
                return jsonify({"success": False, "error": "session_id is required"}), 400

            custom_log(
                f"verify_coin_checkout_session: user_id={user_id} session_id={session_id}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )

            try:
                session = self.stripe.checkout.Session.retrieve(session_id)
            except stripe.error.StripeError as e:
                custom_log(f"verify_coin_checkout_session Stripe retrieve: {e}", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({"success": False, "error": str(e)}), 400

            if isinstance(session, dict):
                sd = session
            elif hasattr(session, "to_dict"):
                sd = session.to_dict()
            else:
                sd = {}

            meta_dict = sd.get("metadata") or {}
            if meta_dict.get("purchase_type") != "dutch_coins":
                return jsonify({"success": False, "error": "Not a Dutch coin checkout session"}), 400

            uid_meta = str(meta_dict.get("user_id") or sd.get("client_reference_id") or "")
            if uid_meta != str(user_id):
                custom_log(
                    f"verify_coin_checkout_session: user mismatch jwt={user_id!r} session={uid_meta!r}",
                    level="WARNING",
                    isOn=LOGGING_SWITCH,
                )
                return jsonify({"success": False, "error": "Session does not belong to this user"}), 403

            self._handle_checkout_session_completed(session)

            custom_log(
                f"verify_coin_checkout_session: handled session_id={session_id}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
            return jsonify({"success": True, "message": "Checkout verified"}), 200

        except Exception as e:
            custom_log(f"verify_coin_checkout_session error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def verify_revenuecat_coin_purchase(self):
        """
        After a native store purchase (RevenueCat): confirm the transaction exists for this JWT user
        on RevenueCat, then credit Dutch coins once (idempotent on store_transaction_id).
        """
        try:
            from utils.config.config import Config

            user_id = getattr(request, "user_id", None)
            if not user_id:
                return jsonify({"success": False, "error": "Authentication required", "code": "JWT_REQUIRED"}), 401

            secret = (Config.REVENUECAT_SECRET_API_KEY or "").strip()
            if not secret:
                return jsonify(
                    {
                        "success": False,
                        "error": "RevenueCat server verification is not configured",
                        "message": "Set REVENUECAT_SECRET_API_KEY (RevenueCat dashboard → API keys → Secret key).",
                    }
                ), 503

            body = request.get_json() or {}
            product_identifier = (body.get("product_identifier") or "").strip()
            store_transaction_id = (body.get("store_transaction_id") or "").strip()

            if not product_identifier or not store_transaction_id:
                return jsonify(
                    {"success": False, "error": "product_identifier and store_transaction_id are required"}
                ), 400

            coins = REVENUECAT_COIN_PRODUCT_COINS.get(product_identifier)
            if coins is None or coins <= 0:
                return jsonify({"success": False, "error": "Unknown or unsupported coin product"}), 400

            existing = self.db_manager.find_one(
                "revenuecat_coin_purchases", {"store_transaction_id": store_transaction_id}
            )
            if existing:
                if str(existing.get("user_id") or "") != str(user_id):
                    custom_log(
                        f"verify_revenuecat_coin_purchase: store_transaction_id reused by different user",
                        level="WARNING",
                        isOn=LOGGING_SWITCH,
                    )
                    return jsonify({"success": False, "error": "Transaction already recorded"}), 403
                return jsonify({"success": True, "message": "Already credited", "coins": coins}), 200

            url = "https://api.revenuecat.com/v1/subscribers/{}".format(
                urllib.parse.quote(str(user_id), safe="")
            )
            try:
                rc_resp = requests.get(
                    url,
                    headers={"Authorization": f"Bearer {secret}"},
                    timeout=20,
                )
            except requests.RequestException as e:
                custom_log(f"verify_revenuecat_coin_purchase RC request: {e}", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({"success": False, "error": "Could not reach RevenueCat"}), 502

            if rc_resp.status_code == 404:
                return jsonify(
                    {
                        "success": False,
                        "error": "Subscriber not found",
                        "code": "RC_NOT_FOUND",
                        "message": "Try again in a few seconds after the purchase completes.",
                    }
                ), 404

            if rc_resp.status_code != 200:
                custom_log(
                    f"verify_revenuecat_coin_purchase RC HTTP {rc_resp.status_code} body={rc_resp.text[:500]!r}",
                    level="ERROR",
                    isOn=LOGGING_SWITCH,
                )
                return jsonify({"success": False, "error": "RevenueCat verification failed"}), 502

            try:
                payload = rc_resp.json()
            except Exception:
                return jsonify({"success": False, "error": "Invalid RevenueCat response"}), 502

            subscriber = payload.get("subscriber") or {}
            non_subs = subscriber.get("non_subscriptions") or {}
            tx_list = non_subs.get(product_identifier)
            if not isinstance(tx_list, list):
                tx_list = []

            matched = False
            for tx in tx_list:
                if not isinstance(tx, dict):
                    continue
                rc_id = str(tx.get("id") or "")
                stid = tx.get("store_transaction_id")
                if stid is not None:
                    stid = str(stid)
                else:
                    stid = ""
                if stid == store_transaction_id or rc_id == store_transaction_id:
                    matched = True
                    break

            if not matched:
                return jsonify(
                    {
                        "success": False,
                        "error": "Transaction not found for this user",
                        "code": "RC_TXN_PENDING",
                        "message": "RevenueCat may still be syncing. Try again shortly.",
                    }
                ), 404

            try:
                oid = ObjectId(str(user_id))
            except Exception:
                return jsonify({"success": False, "error": "Invalid user id"}), 400

            self._credit_dutch_game_coins(oid, coins)
            self.db_manager.insert(
                "revenuecat_coin_purchases",
                {
                    "store_transaction_id": store_transaction_id,
                    "user_id": str(user_id),
                    "product_identifier": product_identifier,
                    "coins": coins,
                    "created_at": datetime.utcnow().isoformat(),
                },
            )
            custom_log(
                f"RevenueCat coin purchase credited user_id={user_id} coins={coins} product={product_identifier}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
            return jsonify({"success": True, "message": "Coins credited", "coins": coins}), 200

        except Exception as e:
            custom_log(f"verify_revenuecat_coin_purchase error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def _handle_checkout_session_completed(self, session_obj):
        """Credit Dutch game coins after successful Checkout (idempotent per session id)."""
        try:
            if isinstance(session_obj, dict):
                session = session_obj
            elif hasattr(session_obj, "to_dict"):
                session = session_obj.to_dict()
            else:
                session = dict(session_obj)
            if session.get("mode") != "payment":
                return
            session_id = session.get("id")
            if not session_id:
                return
            if session.get("payment_status") != "paid":
                custom_log(
                    f"Stripe checkout.session.completed: session {session_id} payment_status={session.get('payment_status')}",
                    level="WARNING",
                    isOn=LOGGING_SWITCH,
                )
                return

            meta = session.get("metadata") or {}
            if meta.get("purchase_type") != "dutch_coins":
                return

            existing = self.db_manager.find_one("stripe_coin_purchases", {"checkout_session_id": session_id})
            if existing:
                return

            user_id_str = meta.get("user_id") or session.get("client_reference_id")
            if not user_id_str:
                custom_log("checkout.session.completed: missing user_id", level="ERROR", isOn=LOGGING_SWITCH)
                return
            try:
                coins = int(meta.get("coins", "0"))
            except (TypeError, ValueError):
                coins = 0
            if coins <= 0:
                custom_log(f"checkout.session.completed: invalid coins for session {session_id}", level="ERROR", isOn=LOGGING_SWITCH)
                return

            try:
                oid = ObjectId(user_id_str)
            except Exception:
                custom_log(f"checkout.session.completed: bad user_id {user_id_str!r}", level="ERROR", isOn=LOGGING_SWITCH)
                return

            self._credit_dutch_game_coins(oid, coins)

            self.db_manager.insert(
                "stripe_coin_purchases",
                {
                    "checkout_session_id": session_id,
                    "user_id": user_id_str,
                    "coins": coins,
                    "package_key": meta.get("package_key", ""),
                    "created_at": datetime.utcnow().isoformat(),
                },
            )
            custom_log(
                f"Stripe coin purchase credited user_id={user_id_str} coins={coins} session={session_id}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        except Exception as e:
            custom_log(f"_handle_checkout_session_completed error: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _credit_dutch_game_coins(self, user_oid: ObjectId, coins: int):
        """Increment modules.dutch_game.coins (same field as match economy)."""
        if coins <= 0:
            return
        ts = datetime.utcnow().isoformat()
        result = self.db_manager.db["users"].update_one(
            {"_id": user_oid},
            {
                "$inc": {"modules.dutch_game.coins": coins},
                "$set": {"modules.dutch_game.last_updated": ts, "updated_at": ts},
            },
        )
        if result.matched_count == 0:
            raise ValueError(f"user not found: {user_oid}")

    def get_payment_status(self, payment_intent_id):
        """Get payment status from Stripe."""
        try:
            if not self.stripe:
                return jsonify({
                    "success": False,
                    "error": "Stripe is not configured"
                }), 503

            payment_intent = self.stripe.PaymentIntent.retrieve(payment_intent_id)
            
            return jsonify({
                "success": True,
                "status": payment_intent.status,
                "amount": payment_intent.amount / 100,  # Convert from cents
                "currency": payment_intent.currency,
                "created": payment_intent.created
            }), 200

        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Stripe error: {str(e)}"
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_credit_packages(self):
        """Get available credit packages."""
        packages = [
            {
                "id": "basic",
                "name": "Basic Package",
                "credits": 100,
                "price_usd": 10.00,
                "description": "100 credits for $10"
            },
            {
                "id": "standard",
                "name": "Standard Package", 
                "credits": 500,
                "price_usd": 45.00,
                "description": "500 credits for $45 (10% discount)"
            },
            {
                "id": "premium",
                "name": "Premium Package",
                "credits": 1000,
                "price_usd": 80.00,
                "description": "1000 credits for $80 (20% discount)"
            }
        ]
        
        return jsonify({
            "success": True,
            "packages": packages
        }), 200

    def _calculate_credits_from_usd(self, amount_usd: float) -> int:
        """Calculate credits from USD amount."""
        # Simple conversion: $1 = 10 credits
        # You can make this more complex with different tiers
        return int(amount_usd * 10)

    def _update_user_credits(self, user_id: str, credit_amount: int):
        """Update user credits through database queue."""
        try:
            # Find user's wallet
            wallet = self.db_manager.find_one("wallets", {"user_id": user_id})
            
            if wallet:
                # Update existing wallet
                current_balance = wallet.get('balance', 0)
                new_balance = current_balance + credit_amount
                
                update_data = {
                    'balance': new_balance,
                    'updated_at': datetime.utcnow().isoformat()
                }
                
                self.db_manager.update("wallets", {"user_id": user_id}, update_data)
            else:
                # Create new wallet
                wallet_data = {
                    'user_id': user_id,
                    'balance': credit_amount,
                    'currency': 'credits',
                    'created_at': datetime.utcnow().isoformat(),
                    'updated_at': datetime.utcnow().isoformat()
                }
                
                self.db_manager.insert("wallets", wallet_data)
                
        except Exception as e:
            raise

    def create_customer(self):
        """Create a Stripe customer for a user."""
        try:
            if not self.stripe:
                return jsonify({
                    "success": False,
                    "error": "Stripe is not configured"
                }), 503

            data = request.get_json()
            
            # Validate required fields
            if not data.get('user_id') or not data.get('email'):
                return jsonify({
                    "success": False,
                    "error": "User ID and email are required"
                }), 400

            user_id = data['user_id']
            email = data['email']
            name = data.get('name', '')
            phone = data.get('phone', '')
            
            # Create customer in Stripe
            customer = self.stripe.Customer.create(
                email=email,
                name=name,
                phone=phone,
                metadata={
                    'user_id': user_id,
                    'source': 'credit_system'
                }
            )
            
            # Store customer reference in database
            customer_data = {
                'user_id': user_id,
                'stripe_customer_id': customer.id,
                'email': email,
                'name': name,
                'created_at': datetime.utcnow().isoformat()
            }
            
            self.db_manager.insert("stripe_customers", customer_data)
            
            return jsonify({
                "success": True,
                "customer_id": customer.id,
                "email": customer.email,
                "created": customer.created
            }), 201

        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Customer creation failed: {str(e)}"
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_customer(self, customer_id):
        """Get Stripe customer information."""
        try:
            if not self.stripe:
                return jsonify({
                    "success": False,
                    "error": "Stripe is not configured"
                }), 503

            customer = self.stripe.Customer.retrieve(customer_id)
            
            return jsonify({
                "success": True,
                "customer": {
                    "id": customer.id,
                    "email": customer.email,
                    "name": customer.name,
                    "phone": customer.phone,
                    "created": customer.created,
                    "metadata": customer.metadata
                }
            }), 200

        except stripe.error.InvalidRequestError as e:
            return jsonify({
                "success": False,
                "error": "Customer not found"
            }), 404
        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Customer retrieval failed: {str(e)}"
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def list_payment_methods(self):
        """List payment methods for a customer."""
        try:
            if not self.stripe:
                return jsonify({
                    "success": False,
                    "error": "Stripe is not configured"
                }), 503

            customer_id = request.args.get('customer_id')
            if not customer_id:
                return jsonify({
                    "success": False,
                    "error": "Customer ID is required"
                }), 400

            payment_methods = self.stripe.PaymentMethod.list(
                customer=customer_id,
                type='card'
            )
            
            return jsonify({
                "success": True,
                "payment_methods": [
                    {
                        "id": pm.id,
                        "type": pm.type,
                        "card": {
                            "brand": pm.card.brand,
                            "last4": pm.card.last4,
                            "exp_month": pm.card.exp_month,
                            "exp_year": pm.card.exp_year
                        } if pm.card else None,
                        "created": pm.created
                    }
                    for pm in payment_methods.data
                ]
            }), 200

        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Failed to list payment methods: {str(e)}"
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_payment_method(self, payment_method_id):
        """Get payment method details."""
        try:
            if not self.stripe:
                return jsonify({
                    "success": False,
                    "error": "Stripe is not configured"
                }), 503

            payment_method = self.stripe.PaymentMethod.retrieve(payment_method_id)
            
            return jsonify({
                "success": True,
                "payment_method": {
                    "id": payment_method.id,
                    "type": payment_method.type,
                    "card": {
                        "brand": payment_method.card.brand,
                        "last4": payment_method.card.last4,
                        "exp_month": payment_method.card.exp_month,
                        "exp_year": payment_method.card.exp_year
                    } if payment_method.card else None,
                    "customer": payment_method.customer,
                    "created": payment_method.created
                }
            }), 200

        except stripe.error.InvalidRequestError as e:
            return jsonify({
                "success": False,
                "error": "Payment method not found"
            }), 404
        except stripe.error.StripeError as e:
            return jsonify({
                "success": False,
                "error": f"Payment method retrieval failed: {str(e)}"
            }), 400
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for StripeModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        health_status['details'] = {
            'stripe_configured': self.stripe is not None,
            'webhook_secret_configured': self.webhook_secret is not None
        }
        return health_status 