from prometheus_client import Counter, Histogram, Gauge
from prometheus_flask_exporter import PrometheusMetrics
from flask import Flask

# Initialize metrics with app name from config
from utils.config.config import Config
metrics = PrometheusMetrics.for_app_factory(app_name=Config.APP_NAME)

def init_metrics(app: Flask):
    """Initialize metrics for the Flask application."""
    # Initialize metrics with the app
    metrics.init_app(app)
    
    # Create custom metrics
    metrics.info('credit_system_info', 'Credit System Information', version='1.0.0')
    
    # Create counters
    metrics.counter(
        'credit_system_transaction_operations_total',
        'Total number of credit transaction operations',
        labels={'operation_type': str, 'status': str}
    )
    
    # Create gauges
    metrics.gauge(
        'credit_system_user_balance_current',
        'Current credit balance for users',
        labels={'user_id': str}
    )
    
    # Create histograms
    metrics.histogram(
        'credit_system_transaction_processing_seconds',
        'Duration of credit transaction processing',
        labels={'operation_type': str}
    )
    
    return metrics 