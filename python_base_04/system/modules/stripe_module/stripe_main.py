from typing import Dict, Any, Optional, List
from datetime import datetime
from decimal import Decimal
import stripe
import os
import hmac
import hashlib
import json
import uuid
from tools.logger.custom_logging import custom_log


class StripeModule:
    """
    Pure business logic module for Stripe payment processing.
    Completely decoupled from Flask and system dependencies.
    """
    
    def __init__(self):
        """Initialize the Stripe module with independent secret management."""
        self.stripe = None
        self.webhook_secret = None
        self.secret_sources = self._get_secret_sources()
        self._initialize_stripe()
        custom_log("StripeModule initialized with independent secret management")

    def initialize(self):
        """Initialize the module."""
        custom_log("StripeModule initialization complete")

    def _get_secret_sources(self) -> Dict[str, Any]:
        """Get secret sources for the module."""
        return {
            'stripe_secret_key': self._read_module_secret('stripe_secret_key'),
            'stripe_publishable_key': self._read_module_secret('stripe_publishable_key'),
            'stripe_webhook_secret': self._read_module_secret('stripe_webhook_secret'),
            'stripe_endpoint_secret': self._read_module_secret('stripe_endpoint_secret')
        }

    def _read_module_secret(self, secret_name: str) -> Optional[str]:
        """
        Read module-specific secrets with fallback chain.
        
        Args:
            secret_name: Name of the secret to read
            
        Returns:
            Secret value or None if not found
        """
        # Try module-specific secrets first
        module_secret_path = f"system/modules/stripe_module/secrets/{secret_name}"
        if os.path.exists(module_secret_path):
            try:
                with open(module_secret_path, 'r') as f:
                    return f.read().strip()
            except Exception as e:
                custom_log(f"Error reading module secret {secret_name}: {e}", level="WARNING")
        
        # Try global secrets
        global_secret_path = f"secrets/{secret_name}"
        if os.path.exists(global_secret_path):
            try:
                with open(global_secret_path, 'r') as f:
                    return f.read().strip()
            except Exception as e:
                custom_log(f"Error reading global secret {secret_name}: {e}", level="WARNING")
        
        # Try environment variables
        env_name = secret_name.upper()
        if env_name in os.environ:
            return os.environ[env_name]
        
        # Try alternative environment variable names
        alt_env_names = [
            f"STRIPE_{secret_name.upper()}",
            f"STRIPE_{secret_name.upper().replace('STRIPE_', '')}",
            secret_name.upper().replace('STRIPE_', 'STRIPE_')
        ]
        
        for alt_name in alt_env_names:
            if alt_name in os.environ:
                return os.environ[alt_name]
        
        return None

    def _get_environment_variable(self, env_name: str) -> Optional[str]:
        """Get environment variable value."""
        return os.environ.get(env_name)

    def _get_stripe_secret_key(self) -> str:
        """Get Stripe secret key with fallback."""
        secret_key = self.secret_sources.get('stripe_secret_key')
        if not secret_key:
            secret_key = self._get_environment_variable('STRIPE_SECRET_KEY')
        if not secret_key:
            secret_key = self._get_environment_variable('STRIPE_SECRET_KEY_TEST')
        if not secret_key:
            raise ValueError("Stripe secret key not found in any source")
        return secret_key

    def _get_stripe_webhook_secret(self) -> str:
        """Get Stripe webhook secret with fallback."""
        webhook_secret = self.secret_sources.get('stripe_webhook_secret')
        if not webhook_secret:
            webhook_secret = self._get_environment_variable('STRIPE_WEBHOOK_SECRET')
        if not webhook_secret:
            webhook_secret = self._get_environment_variable('STRIPE_ENDPOINT_SECRET')
        if not webhook_secret:
            raise ValueError("Stripe webhook secret not found in any source")
        return webhook_secret

    def _initialize_stripe(self):
        """Initialize Stripe with secret key."""
        try:
            secret_key = self._get_stripe_secret_key()
            self.stripe = stripe
            stripe.api_key = secret_key
            self.webhook_secret = self._get_stripe_webhook_secret()
            custom_log("✅ Stripe initialized successfully")
        except Exception as e:
            custom_log(f"❌ Error initializing Stripe: {e}", level="ERROR")
            self.stripe = None
            self.webhook_secret = None

    def process_payment_intent_creation(self, payment_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process payment intent creation (pure business logic).
        
        Args:
            payment_data: Payment data containing user_id, amount, currency
            
        Returns:
            Dict with payment intent creation result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            # Validate required fields
            required_fields = ['user_id', 'amount', 'currency']
            missing_fields = [field for field in required_fields if not payment_data.get(field)]
            
            if missing_fields:
                return {
                    'success': False,
                    'error': f"Missing required fields: {', '.join(missing_fields)}"
                }

            user_id = payment_data['user_id']
            amount = payment_data['amount']
            currency = payment_data['currency']
            
            # Validate amount (convert to cents for Stripe)
            try:
                amount_cents = int(float(amount) * 100)
                if amount_cents <= 0:
                    return {
                        'success': False,
                        'error': 'Amount must be greater than 0'
                    }
            except ValueError:
                return {
                    'success': False,
                    'error': 'Invalid amount format'
                }

            # Generate idempotency key for this request
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

            custom_log(f"✅ Payment intent created for user {user_id}: {payment_intent.id}")

            return {
                'success': True,
                'client_secret': payment_intent.client_secret,
                'payment_intent_id': payment_intent.id,
                'amount': amount,
                'currency': currency,
                'idempotency_key': idempotency_key
            }

        except stripe.error.CardError as e:
            custom_log(f"❌ Stripe card error: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Card declined',
                'error_code': e.code,
                'decline_code': e.decline_code,
                'message': str(e)
            }
        except stripe.error.InvalidRequestError as e:
            custom_log(f"❌ Stripe invalid request: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Invalid request parameters',
                'error_code': e.code,
                'param': e.param,
                'message': str(e)
            }
        except stripe.error.AuthenticationError as e:
            custom_log(f"❌ Stripe authentication error: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Authentication failed',
                'message': 'Invalid API key'
            }
        except stripe.error.APIConnectionError as e:
            custom_log(f"❌ Stripe API connection error: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Network error',
                'message': 'Unable to connect to Stripe'
            }
        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error creating payment intent: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Payment processing error: {str(e)}",
                'error_code': getattr(e, 'code', None)
            }
        except Exception as e:
            custom_log(f"❌ Error creating payment intent: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_payment_confirmation(self, payment_intent_id: str) -> Dict[str, Any]:
        """
        Process payment confirmation (pure business logic).
        
        Args:
            payment_intent_id: Stripe payment intent ID
            
        Returns:
            Dict with payment confirmation result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            if not payment_intent_id:
                return {
                    'success': False,
                    'error': 'Payment intent ID is required'
                }
            
            # Retrieve payment intent from Stripe
            payment_intent = self.stripe.PaymentIntent.retrieve(payment_intent_id)
            
            if payment_intent.status != 'succeeded':
                return {
                    'success': False,
                    'error': f"Payment not successful. Status: {payment_intent.status}"
                }

            # Extract metadata
            user_id = payment_intent.metadata.get('user_id')
            amount_usd = float(payment_intent.metadata.get('amount_usd', 0))
            
            if not user_id:
                return {
                    'success': False,
                    'error': 'Invalid payment intent - missing user ID'
                }

            # Calculate credits from USD amount
            credit_amount = self._calculate_credits_from_usd(amount_usd)
            
            # Prepare transaction data for orchestrator to persist
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
            
            return {
                'success': True,
                'transaction_data': transaction_data,
                'payment_intent': {
                    'id': payment_intent.id,
                    'status': payment_intent.status,
                    'amount': payment_intent.amount,
                    'currency': payment_intent.currency,
                    'metadata': payment_intent.metadata
                },
                'credits_purchased': credit_amount
            }
            
        except stripe.error.InvalidRequestError as e:
            return {
                'success': False,
                'error': 'Payment intent not found'
            }
        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error confirming payment: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Payment confirmation failed: {str(e)}"
            }
        except Exception as e:
            custom_log(f"❌ Error confirming payment: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_webhook_event(self, payload: str, signature: str) -> Dict[str, Any]:
        """
        Process webhook event (pure business logic).
        
        Args:
            payload: Raw webhook payload
            signature: Webhook signature
            
        Returns:
            Dict with webhook processing result
        """
        try:
            if not self.stripe or not self.webhook_secret:
                return {
                    'success': False,
                    'error': 'Stripe webhook not configured'
                }

            # Verify webhook signature
            try:
                event = stripe.Webhook.construct_event(
                    payload, signature, self.webhook_secret
                )
            except ValueError as e:
                return {
                    'success': False,
                    'error': 'Invalid payload'
                }
            except stripe.error.SignatureVerificationError as e:
                return {
                    'success': False,
                    'error': 'Invalid signature'
                }
            
            # Process the event
            event_type = event['type']
            
            if event_type == 'payment_intent.succeeded':
                return self._process_payment_succeeded_event(event['data']['object'])
            elif event_type == 'payment_intent.payment_failed':
                return self._process_payment_failed_event(event['data']['object'])
            elif event_type == 'charge.dispute.created':
                return self._process_dispute_created_event(event['data']['object'])
            else:
                return {
                    'success': True,
                    'message': f'Unhandled event type: {event_type}'
                }
            
        except Exception as e:
            custom_log(f"❌ Error processing webhook: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Webhook processing error'
            }

    def _process_payment_succeeded_event(self, payment_intent: Dict[str, Any]) -> Dict[str, Any]:
        """Process payment succeeded event."""
        user_id = payment_intent.get('metadata', {}).get('user_id')
        amount_usd = float(payment_intent.get('metadata', {}).get('amount_usd', 0))
        credit_amount = self._calculate_credits_from_usd(amount_usd)
        
        return {
            'success': True,
            'event_type': 'payment_succeeded',
            'user_id': user_id,
            'amount_usd': amount_usd,
            'credits_purchased': credit_amount,
            'payment_intent_id': payment_intent.get('id')
        }

    def _process_payment_failed_event(self, payment_intent: Dict[str, Any]) -> Dict[str, Any]:
        """Process payment failed event."""
        user_id = payment_intent.get('metadata', {}).get('user_id')
        
        return {
            'success': True,
            'event_type': 'payment_failed',
            'user_id': user_id,
            'payment_intent_id': payment_intent.get('id'),
            'failure_reason': payment_intent.get('last_payment_error', {}).get('message')
        }

    def _process_dispute_created_event(self, dispute: Dict[str, Any]) -> Dict[str, Any]:
        """Process dispute created event."""
        return {
            'success': True,
            'event_type': 'dispute_created',
            'dispute_id': dispute.get('id'),
            'charge_id': dispute.get('charge'),
            'amount': dispute.get('amount'),
            'reason': dispute.get('reason')
        }

    def process_payment_status_request(self, payment_intent_id: str) -> Dict[str, Any]:
        """
        Process payment status request (pure business logic).
        
        Args:
            payment_intent_id: Stripe payment intent ID
            
        Returns:
            Dict with payment status result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            if not payment_intent_id:
                return {
                    'success': False,
                    'error': 'Payment intent ID is required'
                }
            
            # Retrieve payment intent from Stripe
            payment_intent = self.stripe.PaymentIntent.retrieve(payment_intent_id)
            
            return {
                'success': True,
                'payment_intent': {
                    'id': payment_intent.id,
                    'status': payment_intent.status,
                    'amount': payment_intent.amount,
                    'currency': payment_intent.currency,
                    'metadata': payment_intent.metadata,
                    'created': payment_intent.created
                }
            }
            
        except stripe.error.InvalidRequestError as e:
            return {
                'success': False,
                'error': 'Payment intent not found'
            }
        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error retrieving payment status: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Payment status retrieval failed: {str(e)}"
            }
        except Exception as e:
            custom_log(f"❌ Error retrieving payment status: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_credit_packages_request(self) -> Dict[str, Any]:
        """
        Process credit packages request (pure business logic).
        
        Returns:
            Dict with credit packages result
        """
        try:
            # Define credit packages
            credit_packages = [
            {
                    'id': 'basic',
                    'name': 'Basic Package',
                    'credits': 100,
                    'price_usd': 5.00,
                    'description': '100 credits for $5.00'
            },
            {
                    'id': 'standard',
                    'name': 'Standard Package',
                    'credits': 500,
                    'price_usd': 20.00,
                    'description': '500 credits for $20.00'
            },
            {
                    'id': 'premium',
                    'name': 'Premium Package',
                    'credits': 1200,
                    'price_usd': 45.00,
                    'description': '1200 credits for $45.00'
                },
                {
                    'id': 'enterprise',
                    'name': 'Enterprise Package',
                    'credits': 3000,
                    'price_usd': 100.00,
                    'description': '3000 credits for $100.00'
                }
            ]
            
            return {
                'success': True,
                'credit_packages': credit_packages
            }
                
        except Exception as e:
            custom_log(f"❌ Error processing credit packages request: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_customer_creation(self, customer_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process customer creation (pure business logic).
        
        Args:
            customer_data: Customer data containing email, name, etc.
            
        Returns:
            Dict with customer creation result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            # Validate required fields
            if not customer_data.get('email'):
                return {
                    'success': False,
                    'error': 'Email is required'
                }
            
            # Create customer in Stripe
            customer = self.stripe.Customer.create(
                email=customer_data['email'],
                name=customer_data.get('name'),
                metadata=customer_data.get('metadata', {})
            )
            
            return {
                'success': True,
                'customer': {
                    'id': customer.id,
                    'email': customer.email,
                    'name': customer.name,
                    'created': customer.created
                }
            }

        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error creating customer: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Customer creation failed: {str(e)}"
            }
        except Exception as e:
            custom_log(f"❌ Error creating customer: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_customer_retrieval(self, customer_id: str) -> Dict[str, Any]:
        """
        Process customer retrieval (pure business logic).
        
        Args:
            customer_id: Stripe customer ID
            
        Returns:
            Dict with customer retrieval result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            if not customer_id:
                return {
                    'success': False,
                    'error': 'Customer ID is required'
                }
            
            # Retrieve customer from Stripe
            customer = self.stripe.Customer.retrieve(customer_id)
            
            return {
                'success': True,
                'customer': {
                    'id': customer.id,
                    'email': customer.email,
                    'name': customer.name,
                    'created': customer.created,
                    'metadata': customer.metadata
                }
            }

        except stripe.error.InvalidRequestError as e:
            return {
                'success': False,
                'error': 'Customer not found'
            }
        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error retrieving customer: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Customer retrieval failed: {str(e)}"
            }
        except Exception as e:
            custom_log(f"❌ Error retrieving customer: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_payment_methods_list(self, customer_id: str) -> Dict[str, Any]:
        """
        Process payment methods list request (pure business logic).
        
        Args:
            customer_id: Stripe customer ID
            
        Returns:
            Dict with payment methods list result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            if not customer_id:
                return {
                    'success': False,
                    'error': 'Customer ID is required'
                }
            
            # List payment methods from Stripe
            payment_methods = self.stripe.PaymentMethod.list(
                customer=customer_id,
                type='card'
            )
            
            return {
                'success': True,
                'payment_methods': [
                    {
                        'id': pm.id,
                        'type': pm.type,
                        'card': {
                            'brand': pm.card.brand,
                            'last4': pm.card.last4,
                            'exp_month': pm.card.exp_month,
                            'exp_year': pm.card.exp_year
                        } if pm.card else None,
                        'created': pm.created
                    }
                    for pm in payment_methods.data
                ]
            }

        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error listing payment methods: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Failed to list payment methods: {str(e)}"
            }
        except Exception as e:
            custom_log(f"❌ Error listing payment methods: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def process_payment_method_retrieval(self, payment_method_id: str) -> Dict[str, Any]:
        """
        Process payment method retrieval (pure business logic).
        
        Args:
            payment_method_id: Stripe payment method ID
            
        Returns:
            Dict with payment method retrieval result
        """
        try:
            if not self.stripe:
                return {
                    'success': False,
                    'error': 'Stripe is not configured'
                }
            
            if not payment_method_id:
                return {
                    'success': False,
                    'error': 'Payment method ID is required'
                }
            
            # Retrieve payment method from Stripe
            payment_method = self.stripe.PaymentMethod.retrieve(payment_method_id)
            
            return {
                'success': True,
                'payment_method': {
                    'id': payment_method.id,
                    'type': payment_method.type,
                    'card': {
                        'brand': payment_method.card.brand,
                        'last4': payment_method.card.last4,
                        'exp_month': payment_method.card.exp_month,
                        'exp_year': payment_method.card.exp_year
                    } if payment_method.card else None,
                    'customer': payment_method.customer,
                    'created': payment_method.created
                }
            }

        except stripe.error.InvalidRequestError as e:
            return {
                'success': False,
                'error': 'Payment method not found'
            }
        except stripe.error.StripeError as e:
            custom_log(f"❌ Stripe error retrieving payment method: {e}", level="ERROR")
            return {
                'success': False,
                'error': f"Payment method retrieval failed: {str(e)}"
            }
        except Exception as e:
            custom_log(f"❌ Error retrieving payment method: {e}", level="ERROR")
            return {
                'success': False,
                'error': 'Internal server error'
            }

    def _calculate_credits_from_usd(self, amount_usd: float) -> int:
        """Calculate credits from USD amount."""
        # Simple conversion: $1 = 20 credits
        return int(amount_usd * 20)

    def get_secret_sources(self) -> Dict[str, Any]:
        """Get secret sources for debugging."""
        return {
            'stripe_secret_key': '***' if self.secret_sources.get('stripe_secret_key') else None,
            'stripe_publishable_key': '***' if self.secret_sources.get('stripe_publishable_key') else None,
            'stripe_webhook_secret': '***' if self.secret_sources.get('stripe_webhook_secret') else None,
            'stripe_endpoint_secret': '***' if self.secret_sources.get('stripe_endpoint_secret') else None
        }

    def get_config_requirements(self) -> List[Dict[str, Any]]:
        """Get configuration requirements for this module."""
        return [
            {
                'name': 'stripe_secret_key',
                'description': 'Stripe secret key for API access',
                'required': True,
                'sources': ['module_secrets', 'environment_variables']
            },
            {
                'name': 'stripe_webhook_secret',
                'description': 'Stripe webhook secret for signature verification',
                'required': True,
                'sources': ['module_secrets', 'environment_variables']
            },
            {
                'name': 'stripe_publishable_key',
                'description': 'Stripe publishable key for client-side integration',
                'required': False,
                'sources': ['module_secrets', 'environment_variables']
            }
        ]

    def get_hooks_needed(self) -> List[Dict[str, Any]]:
        """Get hooks needed by this module."""
        return [
            {
                'event': 'payment_succeeded',
                'priority': 10,
                'context': 'stripe',
                'description': 'Process successful payment in Stripe module'
            },
            {
                'event': 'payment_failed',
                'priority': 10,
                'context': 'stripe',
                'description': 'Process failed payment in Stripe module'
            },
            {
                'event': 'dispute_created',
                'priority': 10,
                'context': 'stripe',
                'description': 'Process dispute creation in Stripe module'
            }
        ]

    def get_routes_needed(self) -> List[Dict[str, Any]]:
        """Get routes needed by this module."""
        return [
            {
                'route': '/stripe/create-payment-intent',
                'methods': ['POST'],
                'handler': 'create_payment_intent',
                'description': 'Create a Stripe payment intent',
                'auth_required': True
            },
            {
                'route': '/stripe/confirm-payment',
                'methods': ['POST'],
                'handler': 'confirm_payment',
                'description': 'Confirm a payment and process credit purchase',
                'auth_required': True
            },
            {
                'route': '/stripe/webhook',
                'methods': ['POST'],
                'handler': 'handle_webhook',
                'description': 'Handle Stripe webhook events',
                'auth_required': False
            },
            {
                'route': '/stripe/payment-status/<payment_intent_id>',
                'methods': ['GET'],
                'handler': 'get_payment_status',
                'description': 'Get payment status',
                'auth_required': True
            },
            {
                'route': '/stripe/credit-packages',
                'methods': ['GET'],
                'handler': 'get_credit_packages',
                'description': 'Get available credit packages',
                'auth_required': False
            },
            {
                'route': '/stripe/customers',
                'methods': ['POST'],
                'handler': 'create_customer',
                'description': 'Create a Stripe customer',
                'auth_required': True
            },
            {
                'route': '/stripe/customers/<customer_id>',
                'methods': ['GET'],
                'handler': 'get_customer',
                'description': 'Get customer details',
                'auth_required': True
            },
            {
                'route': '/stripe/payment-methods',
                'methods': ['GET'],
                'handler': 'list_payment_methods',
                'description': 'List customer payment methods',
                'auth_required': True
            },
            {
                'route': '/stripe/payment-methods/<payment_method_id>',
                'methods': ['GET'],
                'handler': 'get_payment_method',
                'description': 'Get payment method details',
                'auth_required': True
            }
        ]

    def process_hook_event(self, event_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process hook events (pure business logic).
        
        Args:
            event_name: Name of the hook event
            event_data: Event data
            
        Returns:
            Dict with processing result
        """
        try:
            if event_name == 'payment_succeeded':
                return self._process_payment_succeeded_hook(event_data)
            elif event_name == 'payment_failed':
                return self._process_payment_failed_hook(event_data)
            elif event_name == 'dispute_created':
                return self._process_dispute_created_hook(event_data)
            else:
                return {
                    'success': False,
                    'error': f'Unknown hook event: {event_name}'
                }
                
        except Exception as e:
            custom_log(f"Error processing hook event {event_name}: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Hook event processing error: {str(e)}'
            }

    def _process_payment_succeeded_hook(self, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process payment succeeded hook event."""
        return {
            'success': True,
            'message': 'Payment succeeded event processed',
            'event_data': event_data
        }

    def _process_payment_failed_hook(self, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process payment failed hook event."""
        return {
            'success': True,
            'message': 'Payment failed event processed',
            'event_data': event_data
        }

    def _process_dispute_created_hook(self, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process dispute created hook event."""
        return {
            'success': True,
            'message': 'Dispute created event processed',
            'event_data': event_data
        }

    def health_check(self) -> Dict[str, Any]:
        """Module health check."""
        return {
            'module': 'stripe_module',
            'status': 'healthy' if self.stripe else 'not_initialized',
            'details': {
                'stripe_configured': self.stripe is not None,
                'webhook_secret_configured': self.webhook_secret is not None,
                'secret_sources': self.get_secret_sources()
            }
        }

    def get_config(self) -> Dict[str, Any]:
        """Get module configuration."""
        return {
            'module': 'stripe_module',
            'stripe_configured': self.stripe is not None,
            'webhook_secret_configured': self.webhook_secret is not None,
            'config_requirements': self.get_config_requirements()
        }