from prometheus_client import Counter, Gauge, Histogram, start_http_server, REGISTRY
from typing import Dict, Any

# Global switch for metrics collection (set False when Prometheus/Grafana are not used)
METRICS_COLLECTION_ENABLED = False

class MetricsCollector:
    _instance = None

    def __new__(cls, port: int = 8000):
        """Singleton pattern using __new__."""
        if cls._instance is not None:
            return cls._instance
        cls._instance = super(MetricsCollector, cls).__new__(cls)
        return cls._instance

    def __init__(self, port: int = 8000):
        """Initialize the metrics collector."""
        if hasattr(self, '_initialized'):
            return

        self._initialized = True

        self._metric_handlers = {
            'request': self._handle_request,
            'credit_transaction': self._handle_credit_transaction,
            'credit_balance': self._handle_credit_balance,
            'mongodb_connections': self._handle_mongodb_connections,
            'redis_connections': self._handle_redis_connections,
            'user_registration': self._handle_user_registration,
            'user_login': self._handle_user_login,
            'active_users': self._handle_active_users,
            'guest_conversion': self._handle_guest_conversion,
            'game_created': self._handle_game_created,
            'game_completed': self._handle_game_completed,
            'coin_transaction': self._handle_coin_transaction,
            'special_card_used': self._handle_special_card_used,
            'dutch_called': self._handle_dutch_called,
        }

        self._create_metrics()

        if METRICS_COLLECTION_ENABLED:
            try:
                start_http_server(port, addr='0.0.0.0', registry=REGISTRY)
            except OSError:
                pass
            except Exception:
                pass

    def _create_metrics(self):
        """Create all Prometheus metrics."""

        def _get_or_create_metric(name, metric_type, description, labels=None):
            try:
                if labels:
                    return metric_type(name, description, labels)
                return metric_type(name, description)
            except ValueError:
                for collector, names in REGISTRY._collector_to_names.items():
                    if name in names and isinstance(collector, metric_type):
                        return collector
                raise

        self.request_count = _get_or_create_metric('flask_app_requests_total', Counter, 'Total number of requests', ['method', 'endpoint', 'status'])
        self.request_latency = _get_or_create_metric('flask_app_request_duration_seconds', Histogram, 'Request latency in seconds', ['method', 'endpoint'])
        self.request_size = _get_or_create_metric('flask_app_request_size_bytes', Histogram, 'Request size in bytes', ['method', 'endpoint'])

        self.credit_transactions = _get_or_create_metric('credit_system_transactions_total', Counter, 'Total number of credit transactions', ['type', 'status'])
        self.credit_balance = _get_or_create_metric('credit_system_balance', Gauge, 'Current credit balance', ['user_id'])

        self.mongodb_connections = _get_or_create_metric('mongodb_connections', Gauge, 'Number of active MongoDB connections')
        self.redis_connections = _get_or_create_metric('redis_connections', Gauge, 'Number of active Redis connections')

        self.user_registrations = _get_or_create_metric('user_registrations_total', Counter, 'Total number of user registrations', ['registration_type', 'account_type'])
        self._verify_metric_in_registry('user_registrations_total', self.user_registrations, Counter)

        self.user_logins = _get_or_create_metric('user_logins_total', Counter, 'Total number of user logins', ['auth_method', 'account_type'])
        self._verify_metric_in_registry('user_logins_total', self.user_logins, Counter)

        self.active_users = _get_or_create_metric('active_users_current', Gauge, 'Current number of active users', ['time_period'])
        self.guest_conversions = _get_or_create_metric('guest_account_conversions_total', Counter, 'Total number of guest account conversions', ['conversion_method'])

        self.games_created = _get_or_create_metric('dutch_games_created_total', Counter, 'Total number of Dutch games created', ['game_mode'])
        self.games_completed = _get_or_create_metric('dutch_games_completed_total', Counter, 'Total number of Dutch games completed', ['game_mode', 'result'])
        self.game_duration = _get_or_create_metric('dutch_game_duration_seconds', Histogram, 'Dutch game duration in seconds', ['game_mode'])
        self.coin_transactions = _get_or_create_metric('dutch_coin_transactions_total', Counter, 'Total number of Dutch coin transactions', ['transaction_type', 'direction'])
        self.special_card_used = _get_or_create_metric('dutch_special_card_used_total', Counter, 'Total number of special card uses', ['card_type'])
        self.dutch_calls = _get_or_create_metric('dutch_calls_total', Counter, 'Total number of Dutch calls', ['game_mode'])

    def _verify_metric_in_registry(self, metric_name: str, metric_object, metric_type):
        """Verify that a metric object is registered in REGISTRY."""
        try:
            registry_metric = None
            for collector, names in REGISTRY._collector_to_names.items():
                if metric_name in names and isinstance(collector, metric_type):
                    registry_metric = collector
                    break

            if registry_metric is None:
                return False

            if registry_metric is metric_object:
                return True
            return False
        except Exception:
            return False

    def verify_http_server_registry(self):
        """Return sample lines from REGISTRY for user login/registration counters."""
        try:
            from prometheus_client import generate_latest
            registry_output = generate_latest(REGISTRY).decode('utf-8')

            user_logins_lines = [l for l in registry_output.split('\n')
                                if 'user_logins_total' in l and not l.startswith('#') and l.strip()]
            user_regs_lines = [l for l in registry_output.split('\n')
                              if 'user_registrations_total' in l and not l.startswith('#') and l.strip()]

            return {
                'user_logins_count': len(user_logins_lines),
                'user_registrations_count': len(user_regs_lines),
                'user_logins_lines': user_logins_lines[:10],
                'user_registrations_lines': user_regs_lines[:10]
            }
        except Exception:
            return None

    def collect_metric(self, metric_type: str, payload: Dict[str, Any], isOn: bool = True):
        """Collect a metric when global and local switches allow."""
        if not METRICS_COLLECTION_ENABLED:
            return

        if not isOn:
            return

        if not hasattr(self, '_metric_handlers') or self._metric_handlers is None:
            return

        handler = self._metric_handlers.get(metric_type)
        if not handler:
            return

        try:
            handler(payload)
        except Exception:
            raise

    _metric_handlers = None

    def _handle_request(self, payload: Dict[str, Any]):
        method = payload.get('method')
        endpoint = payload.get('endpoint')
        status = payload.get('status')
        duration = payload.get('duration', 0.0)
        size = payload.get('size', 0)

        self.request_count.labels(method=method, endpoint=endpoint, status=status).inc()
        self.request_latency.labels(method=method, endpoint=endpoint).observe(duration)
        self.request_size.labels(method=method, endpoint=endpoint).observe(size)

    def _handle_credit_transaction(self, payload: Dict[str, Any]):
        transaction_type = payload.get('transaction_type')
        status = payload.get('status')
        amount = payload.get('amount', 0.0)

        self.credit_transactions.labels(type=transaction_type, status=status).inc()

    def _handle_credit_balance(self, payload: Dict[str, Any]):
        user_id = payload.get('user_id')
        balance = payload.get('balance', 0.0)

        self.credit_balance.labels(user_id=user_id).set(balance)

    def _handle_mongodb_connections(self, payload: Dict[str, Any]):
        count = payload.get('count', 0)
        self.mongodb_connections.set(count)

    def _handle_redis_connections(self, payload: Dict[str, Any]):
        count = payload.get('count', 0)
        self.redis_connections.set(count)

    def _handle_user_registration(self, payload: Dict[str, Any]):
        registration_type = payload.get('registration_type')
        account_type = payload.get('account_type')

        self._verify_metric_in_registry('user_registrations_total', self.user_registrations, Counter)

        labeled_metric = self.user_registrations.labels(registration_type=registration_type, account_type=account_type)
        labeled_metric.inc()

    def _handle_user_login(self, payload: Dict[str, Any]):
        auth_method = payload.get('auth_method')
        account_type = payload.get('account_type')

        self._verify_metric_in_registry('user_logins_total', self.user_logins, Counter)

        labeled_metric = self.user_logins.labels(auth_method=auth_method, account_type=account_type)
        labeled_metric.inc()

    def _handle_active_users(self, payload: Dict[str, Any]):
        time_period = payload.get('time_period')
        count = payload.get('count', 0)

        self.active_users.labels(time_period=time_period).set(count)

    def _handle_guest_conversion(self, payload: Dict[str, Any]):
        conversion_method = payload.get('conversion_method')
        self.guest_conversions.labels(conversion_method=conversion_method).inc()

    def _handle_game_created(self, payload: Dict[str, Any]):
        game_mode = payload.get('game_mode')
        self.games_created.labels(game_mode=game_mode).inc()

    def _handle_game_completed(self, payload: Dict[str, Any]):
        game_mode = payload.get('game_mode')
        result = payload.get('result')
        duration = payload.get('duration', 0.0)

        self.games_completed.labels(game_mode=game_mode, result=result).inc()
        self.game_duration.labels(game_mode=game_mode).observe(duration)

    def _handle_coin_transaction(self, payload: Dict[str, Any]):
        transaction_type = payload.get('transaction_type')
        direction = payload.get('direction')
        amount = payload.get('amount', 1.0)

        self.coin_transactions.labels(transaction_type=transaction_type, direction=direction).inc(amount)

    def _handle_special_card_used(self, payload: Dict[str, Any]):
        card_type = payload.get('card_type')
        self.special_card_used.labels(card_type=card_type).inc()

    def _handle_dutch_called(self, payload: Dict[str, Any]):
        game_mode = payload.get('game_mode')
        self.dutch_calls.labels(game_mode=game_mode).inc()
