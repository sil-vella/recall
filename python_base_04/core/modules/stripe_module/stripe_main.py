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
            if not self.webhook_secret:
                return jsonify({
                    "success": False,
                    "error": "Webhook secret not configured"
                }), 503

            # Get the webhook payload
            payload = request.get_data()
            sig_header = request.headers.get('Stripe-Signature')

            if not sig_header:
                return jsonify({
                    "success": False,
                    "error": "Missing Stripe signature"
                }), 400

            # Verify webhook signature
            try:
                event = stripe.Webhook.construct_event(
                    payload, sig_header, self.webhook_secret
                )
            except ValueError as e:
                return jsonify({"error": "Invalid payload"}), 400
            except stripe.error.SignatureVerificationError as e:
                return jsonify({"error": "Invalid signature"}), 400

            # Handle the event
            if event['type'] == 'payment_intent.succeeded':
                self._handle_payment_succeeded(event['data']['object'])
            elif event['type'] == 'payment_intent.payment_failed':
                self._handle_payment_failed(event['data']['object'])
            elif event['type'] == 'charge.dispute.created':
                self._handle_dispute_created(event['data']['object'])
            else:
                pass

            return jsonify({"success": True}), 200

        except Exception as e:
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