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

# Global metrics collector instance
metrics_collector = MetricsCollector() 