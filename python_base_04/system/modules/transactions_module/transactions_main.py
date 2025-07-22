from system.modules.base_module import BaseModule
from system.managers.database_manager import DatabaseManager
from tools.logger.custom_logging import custom_log
from flask import request, jsonify
from datetime import datetime
from typing import Dict, Any


class TransactionsModule(BaseModule):
    def __init__(self, app_initializer=None):
        """Initialize the TransactionsModule."""
        super().__init__(app_initializer)
        self.dependencies = ["communications_module", "user_management", "wallet", "stripe"]
        
        # Use centralized managers from app_manager
        if app_initializer:
            self.db_manager = app_initializer.get_db_manager(role="read_write")
        else:
            self.db_manager = DatabaseManager(role="read_write")
            
        custom_log("TransactionsModule created with database manager")

    def initialize(self, app_initializer):
        """Initialize the TransactionsModule with AppInitializer."""
        self.app_initializer = app_initializer
        self.app = app_initializer.flask_app
        self.register_routes()
        self._initialized = True
        custom_log("TransactionsModule initialized")

    def register_routes(self):
        """Register transaction-related routes."""
        self._register_route_helper("/transactions/info", self.transactions_info, methods=["GET"])
        self._register_route_helper("/transactions/history", self.get_transaction_history, methods=["GET"])
        self._register_route_helper("/transactions/credit-purchase", self.process_credit_purchase, methods=["POST"])
        self._register_route_helper("/transactions/refund", self.process_refund, methods=["POST"])
        custom_log(f"TransactionsModule registered {len(self.registered_routes)} routes")

    def transactions_info(self):
        """Get transactions module information."""
        return jsonify({
            "module": "transactions",
            "status": "operational", 
            "message": "Transactions module is running with queue-based database operations"
        })

    def get_transaction_history(self):
        """Get transaction history for a user."""
        try:
            # Get user_id from request (should be authenticated)
            user_id = request.args.get('user_id')
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "User ID is required"
                }), 400

            # Get credit purchases through queue system
            purchases = self.db_manager.find("credit_purchases", {"user_id": user_id})
            
            # Get failed payments
            failed_payments = self.db_manager.find("failed_payments", {"user_id": user_id})
            
            # Format response
            history = {
                "purchases": purchases,
                "failed_payments": failed_payments,
                "total_purchases": len(purchases),
                "total_failed": len(failed_payments)
            }
            
            return jsonify({
                "success": True,
                "data": history
            }), 200

        except Exception as e:
            custom_log(f"❌ Error getting transaction history: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def process_credit_purchase(self):
        """Process credit purchase through Stripe integration."""
        try:
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
            
            # Validate amount
            if amount <= 0:
                return jsonify({
                    "success": False,
                    "error": "Amount must be greater than 0"
                }), 400

            # Create transaction record through queue system
            transaction_data = {
                'user_id': user_id,
                'amount': amount,
                'currency': currency,
                'purchase_date': datetime.utcnow().isoformat(),
                'status': 'pending',
                'payment_method': 'stripe',
                'created_at': datetime.utcnow().isoformat()
            }
            
            # Use queue system for database operation
            transaction_id = self.db_manager.insert("credit_purchases", transaction_data)
            
            if not transaction_id:
                return jsonify({
                    "success": False,
                    "error": "Failed to create transaction record"
                }), 500

            custom_log(f"✅ Credit purchase transaction created: {transaction_id}")

            return jsonify({
                "success": True,
                "message": "Transaction created successfully",
                "transaction_id": transaction_id,
                "next_step": "Call Stripe module to process payment"
            }), 201

        except Exception as e:
            custom_log(f"❌ Error processing credit purchase: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def process_refund(self):
        """Process refund for a transaction."""
        try:
            data = request.get_json()
            
            if not data.get('transaction_id'):
                return jsonify({
                    "success": False,
                    "error": "Transaction ID is required"
                }), 400

            transaction_id = data['transaction_id']
            refund_amount = data.get('refund_amount')
            reason = data.get('reason', 'Customer request')
            
            # Get original transaction through queue system
            transaction = self.db_manager.find_one("credit_purchases", {"_id": transaction_id})
            
            if not transaction:
                return jsonify({
                    "success": False,
                    "error": "Transaction not found"
                }), 404

            # Create refund record through queue system
            refund_data = {
                'original_transaction_id': transaction_id,
                'user_id': transaction['user_id'],
                'refund_amount': refund_amount or transaction['amount_usd'],
                'reason': reason,
                'status': 'pending',
                'created_at': datetime.utcnow().isoformat()
            }
            
            refund_id = self.db_manager.insert("refunds", refund_data)
            
            if not refund_id:
                return jsonify({
                    "success": False,
                    "error": "Failed to create refund record"
                }), 500

            custom_log(f"✅ Refund record created: {refund_id}")

            return jsonify({
                "success": True,
                "message": "Refund request created",
                "refund_id": refund_id,
                "next_step": "Call Stripe module to process refund"
            }), 201

        except Exception as e:
            custom_log(f"❌ Error processing refund: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def buy_credits(self):
        """Purchase credits directly in database (legacy method - use process_credit_purchase instead)."""
        try:
            data = request.get_json()
            
            # Validate required fields
            required_fields = ['user_id', 'amount']
            for field in required_fields:
                if field not in data:
                    return jsonify({'error': f'Missing required field: {field}'}), 400
            
            user_id = data['user_id']
            amount = data['amount']
            currency = data.get('currency', 'USD')
            payment_method = data.get('payment_method', 'unknown')
            transaction_id = data.get('transaction_id')
            
            # Validate amount
            if amount <= 0:
                return jsonify({'error': 'Amount must be greater than 0'}), 400
            
            # Create transaction record through queue system
            transaction_data = {
                'user_id': user_id,
                'amount': amount,
                'currency': currency,
                'purchase_date': datetime.utcnow().isoformat(),
                'status': 'completed',
                'transaction_id': transaction_id,
                'payment_method': payment_method
            }
            
            # Use queue system for database operation
            result = self.db_manager.insert("credit_purchases", transaction_data)
            
            if result:
                transaction_data['_id'] = result
                
                return jsonify({
                    'success': True,
                    'message': 'Credit purchase completed successfully',
                    'transaction_id': result,
                    'user_id': user_id,
                    'amount': amount,
                    'currency': currency,
                    'status': 'completed'
                }), 201
            
            return jsonify({'error': 'Failed to process credit purchase'}), 500
            
        except Exception as e:
            custom_log(f"Error processing credit purchase: {e}")
            return jsonify({'error': 'Failed to process credit purchase'}), 500

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for TransactionsModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        
        # Add database queue status
        try:
            queue_status = self.db_manager.get_queue_status()
            health_status['details'] = {
                'database_queue': {
                    'queue_size': queue_status['queue_size'],
                    'worker_alive': queue_status['worker_alive'],
                    'queue_enabled': queue_status['queue_enabled'],
                    'pending_results': queue_status['pending_results']
                },
                'stripe_integration': True
            }
        except Exception as e:
            health_status['details'] = {
                'database_queue': f'error: {str(e)}',
                'stripe_integration': True
            }
        
        return health_status 