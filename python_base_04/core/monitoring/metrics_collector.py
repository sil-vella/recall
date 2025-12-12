from prometheus_client import Counter, Gauge, Histogram, start_http_server
import time
from typing import Dict, Any, Optional
from flask import request
import logging

class MetricsCollector:
    def __init__(self, port: int = 8000):
        """Initialize the metrics collector."""
        self.logger = logging.getLogger(__name__)
        
        # API Metrics
        self.request_count = Counter(
            'flask_app_requests_total',
            'Total number of requests',
            ['method', 'endpoint', 'status']
        )
        
        self.request_latency = Histogram(
            'flask_app_request_duration_seconds',
            'Request latency in seconds',
            ['method', 'endpoint']
        )
        
        self.request_size = Histogram(
            'flask_app_request_size_bytes',
            'Request size in bytes',
            ['method', 'endpoint']
        )
        
        # Business Metrics
        self.credit_transactions = Counter(
            'credit_system_transactions_total',
            'Total number of credit transactions',
            ['type', 'status']
        )
        
        self.credit_balance = Gauge(
            'credit_system_balance',
            'Current credit balance',
            ['user_id']
        )
        
        # System Metrics
        self.mongodb_connections = Gauge(
            'mongodb_connections',
            'Number of active MongoDB connections'
        )
        
        self.redis_connections = Gauge(
            'redis_connections',
            'Number of active Redis connections'
        )
        
        # User Metrics
        self.user_registrations = Counter(
            'user_registrations_total',
            'Total number of user registrations',
            ['registration_type', 'account_type']  # email/guest/google, normal/guest
        )
        
        self.user_logins = Counter(
            'user_logins_total',
            'Total number of user logins',
            ['auth_method', 'account_type']  # email/google, normal/guest
        )
        
        self.active_users = Gauge(
            'active_users_current',
            'Current number of active users',
            ['time_period']  # daily/weekly/monthly
        )
        
        self.guest_conversions = Counter(
            'guest_account_conversions_total',
            'Total number of guest account conversions',
            ['conversion_method']  # email/google
        )
        
        # Game Metrics
        self.games_created = Counter(
            'cleco_games_created_total',
            'Total number of Cleco games created',
            ['game_mode']  # practice/multiplayer
        )
        
        self.games_completed = Counter(
            'cleco_games_completed_total',
            'Total number of Cleco games completed',
            ['game_mode', 'result']  # practice/multiplayer, win/loss
        )
        
        self.game_duration = Histogram(
            'cleco_game_duration_seconds',
            'Cleco game duration in seconds',
            ['game_mode']  # practice/multiplayer
        )
        
        self.coin_transactions = Counter(
            'cleco_coin_transactions_total',
            'Total number of Cleco coin transactions',
            ['transaction_type', 'direction']  # earned/spent, credit/debit
        )
        
        self.special_card_used = Counter(
            'cleco_special_card_used_total',
            'Total number of special card uses',
            ['card_type']  # queen_peek/jack_swap
        )
        
        self.cleco_calls = Counter(
            'cleco_calls_total',
            'Total number of Cleco calls',
            ['game_mode']  # practice/multiplayer
        )
        
        # Start the metrics server
        try:
            start_http_server(port)
            self.logger.info(f"Metrics server started on port {port}")
        except Exception as e:
            self.logger.error(f"Failed to start metrics server: {e}")
    
    def track_request(self, method: str, endpoint: str, status: int, duration: float, size: int):
        """Track API request metrics."""
        self.request_count.labels(method=method, endpoint=endpoint, status=status).inc()
        self.request_latency.labels(method=method, endpoint=endpoint).observe(duration)
        self.request_size.labels(method=method, endpoint=endpoint).observe(size)
    
    def track_credit_transaction(self, transaction_type: str, status: str, amount: float):
        """Track credit transaction metrics."""
        self.credit_transactions.labels(type=transaction_type, status=status).inc()
    
    def update_credit_balance(self, user_id: str, balance: float):
        """Update credit balance metric."""
        self.credit_balance.labels(user_id=user_id).set(balance)
    
    def update_mongodb_connections(self, count: int):
        """Update MongoDB connections metric."""
        self.mongodb_connections.set(count)
    
    def update_redis_connections(self, count: int):
        """Update Redis connections metric."""
        self.redis_connections.set(count)
    
    # User Metrics Methods
    def track_user_registration(self, registration_type: str, account_type: str):
        """Track user registration."""
        self.user_registrations.labels(
            registration_type=registration_type,
            account_type=account_type
        ).inc()
    
    def track_user_login(self, auth_method: str, account_type: str):
        """Track user login."""
        self.user_logins.labels(
            auth_method=auth_method,
            account_type=account_type
        ).inc()
    
    def update_active_users(self, time_period: str, count: int):
        """Update active users count for a time period."""
        self.active_users.labels(time_period=time_period).set(count)
    
    def track_guest_conversion(self, conversion_method: str):
        """Track guest account conversion."""
        self.guest_conversions.labels(conversion_method=conversion_method).inc()
    
    # Game Metrics Methods
    def track_game_created(self, game_mode: str):
        """Track game creation."""
        self.games_created.labels(game_mode=game_mode).inc()
    
    def track_game_completed(self, game_mode: str, result: str, duration: float):
        """Track game completion."""
        self.games_completed.labels(
            game_mode=game_mode,
            result=result
        ).inc()
        self.game_duration.labels(game_mode=game_mode).observe(duration)
    
    def track_coin_transaction(self, transaction_type: str, direction: str, amount: float = 1.0):
        """Track coin transaction."""
        self.coin_transactions.labels(
            transaction_type=transaction_type,
            direction=direction
        ).inc(amount)
    
    def track_special_card_used(self, card_type: str):
        """Track special card usage."""
        self.special_card_used.labels(card_type=card_type).inc()
    
    def track_cleco_called(self, game_mode: str):
        """Track Cleco call."""
        self.cleco_calls.labels(game_mode=game_mode).inc()

# Global metrics collector instance
metrics_collector = MetricsCollector() 