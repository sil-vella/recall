from prometheus_client import Counter, Gauge, Histogram, start_http_server, REGISTRY
from typing import Dict, Any
from tools.logger.custom_logging import custom_log

# Global switch for metrics collection
METRICS_COLLECTION_ENABLED = True

class MetricsCollector:
    LOGGING_SWITCH = False  # Enabled for debugging
    _instance = None
    
    def __new__(cls, port: int = 8000):
        """Singleton pattern using __new__."""
        if cls._instance is not None:
            return cls._instance
        cls._instance = super(MetricsCollector, cls).__new__(cls)
        return cls._instance
    
    def __init__(self, port: int = 8000):
        """Initialize the metrics collector."""
        # Prevent re-initialization
        if hasattr(self, '_initialized'):
            return
        
        self._initialized = True
        custom_log(f"MetricsCollector: Initializing on port {port}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Initialize metric handlers registry
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
        custom_log(f"MetricsCollector: Registered {len(self._metric_handlers)} metric handlers: {list(self._metric_handlers.keys())}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Create all metrics with simple try/except for duplicates
        self._create_metrics()
        
        # Log registry state
        try:
            registered_metrics = []
            for collector, names in REGISTRY._collector_to_names.items():
                for name in names:
                    registered_metrics.append(name)
            custom_log(f"MetricsCollector: Registry contains {len(registered_metrics)} metrics: {registered_metrics}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"MetricsCollector: Error inspecting registry: {e}", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Start HTTP server
        # IMPORTANT: Explicitly pass REGISTRY to ensure we use the current process's REGISTRY
        # Flask's debug reloader creates new processes, so we need to ensure the HTTP server
        # uses the REGISTRY from the current process, not a stale one from a previous process
        try:
            start_http_server(port, addr='0.0.0.0', registry=REGISTRY)
            custom_log(f"MetricsCollector: Metrics server started on 0.0.0.0:{port} with current REGISTRY (id={id(REGISTRY)})", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
            custom_log(f"MetricsCollector: Metrics endpoint available at http://0.0.0.0:{port}/metrics", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
        except OSError as e:
            if "Address already in use" in str(e) or "already in use" in str(e).lower():
                # Port is in use - this happens when Flask reloader creates a new process
                # The old HTTP server is still running from the previous process
                # SAFETY: Don't kill processes automatically - it's too dangerous (might kill Flask itself)
                # Instead, log a warning and let the user manually restart if needed
                custom_log(f"MetricsCollector: Port {port} already in use - metrics HTTP server from previous process may still be running", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
                custom_log(f"MetricsCollector: The old HTTP server may be serving stale metrics. To fix: manually kill the process on port {port} and restart Flask", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
                custom_log(f"MetricsCollector: Command to check: lsof -i :{port}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
                custom_log(f"MetricsCollector: Metrics will still be collected in REGISTRY, but HTTP endpoint may not reflect current values", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
            else:
                custom_log(f"MetricsCollector: Failed to start metrics server: {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"MetricsCollector: Failed to start metrics server: {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Log registry state after server start
        try:
            registered_metrics = []
            metric_objects = {}
            for collector, names in REGISTRY._collector_to_names.items():
                for name in names:
                    registered_metrics.append(name)
                    if name in ['user_logins_total', 'user_registrations_total']:
                        metric_objects[name] = collector
            custom_log(f"MetricsCollector: After server start, registry contains {len(registered_metrics)} metrics", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
            
            # Verify our Counter objects match what's in REGISTRY
            if hasattr(self, 'user_logins'):
                registry_user_logins = metric_objects.get('user_logins_total')
                if registry_user_logins:
                    is_same = registry_user_logins is self.user_logins
                    custom_log(f"MetricsCollector: user_logins in REGISTRY matches self.user_logins? {is_same} (registry_id={id(registry_user_logins)}, self_id={id(self.user_logins)})", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
                else:
                    custom_log(f"MetricsCollector: WARNING - user_logins_total not found in REGISTRY after server start!", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            
            if hasattr(self, 'user_registrations'):
                registry_user_registrations = metric_objects.get('user_registrations_total')
                if registry_user_registrations:
                    is_same = registry_user_registrations is self.user_registrations
                    custom_log(f"MetricsCollector: user_registrations in REGISTRY matches self.user_registrations? {is_same} (registry_id={id(registry_user_registrations)}, self_id={id(self.user_registrations)})", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
                else:
                    custom_log(f"MetricsCollector: WARNING - user_registrations_total not found in REGISTRY after server start!", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"MetricsCollector: Error inspecting registry after server start: {e}", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
            import traceback
            custom_log(f"MetricsCollector: Traceback: {traceback.format_exc()}", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _create_metrics(self):
        """Create all Prometheus metrics."""
        custom_log("MetricsCollector._create_metrics: Starting metric creation", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Helper to create metric or get existing from registry
        def _get_or_create_metric(name, metric_type, description, labels=None):
            try:
                # Try to create new metric
                if labels:
                    metric = metric_type(name, description, labels)
                    custom_log(f"MetricsCollector._create_metrics: Created new metric '{name}' with labels {labels}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
                    return metric
                else:
                    metric = metric_type(name, description)
                    custom_log(f"MetricsCollector._create_metrics: Created new metric '{name}' without labels", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
                    return metric
            except ValueError as e:
                # Metric already exists, find it in registry
                custom_log(f"MetricsCollector._create_metrics: Metric '{name}' already exists (ValueError: {e}), searching registry", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
                found_collectors = []
                for collector, names in REGISTRY._collector_to_names.items():
                    if name in names:
                        found_collectors.append((collector, type(collector), id(collector)))
                        if isinstance(collector, metric_type):
                            custom_log(f"MetricsCollector._create_metrics: Found existing metric '{name}' in registry (type={type(collector).__name__}, id={id(collector)}), reusing", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
                            return collector
                
                # Log all found collectors for debugging
                if found_collectors:
                    custom_log(f"MetricsCollector._create_metrics: Found {len(found_collectors)} collector(s) with name '{name}' but wrong type:", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
                    for collector, col_type, col_id in found_collectors:
                        custom_log(f"MetricsCollector._create_metrics:   - {col_type.__name__} (id={col_id}), expected {metric_type.__name__}", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
                
                # If not found, raise (shouldn't happen)
                custom_log(f"MetricsCollector._create_metrics: Metric '{name}' exists but not found in registry with correct type {metric_type.__name__}, raising error", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
                raise
        
        # API Metrics
        self.request_count = _get_or_create_metric('flask_app_requests_total', Counter, 'Total number of requests', ['method', 'endpoint', 'status'])
        self.request_latency = _get_or_create_metric('flask_app_request_duration_seconds', Histogram, 'Request latency in seconds', ['method', 'endpoint'])
        self.request_size = _get_or_create_metric('flask_app_request_size_bytes', Histogram, 'Request size in bytes', ['method', 'endpoint'])
        
        # Business Metrics
        self.credit_transactions = _get_or_create_metric('credit_system_transactions_total', Counter, 'Total number of credit transactions', ['type', 'status'])
        self.credit_balance = _get_or_create_metric('credit_system_balance', Gauge, 'Current credit balance', ['user_id'])
        
        # System Metrics
        self.mongodb_connections = _get_or_create_metric('mongodb_connections', Gauge, 'Number of active MongoDB connections')
        self.redis_connections = _get_or_create_metric('redis_connections', Gauge, 'Number of active Redis connections')
        
        # User Metrics
        self.user_registrations = _get_or_create_metric('user_registrations_total', Counter, 'Total number of user registrations', ['registration_type', 'account_type'])
        custom_log(f"MetricsCollector._create_metrics: user_registrations = {self.user_registrations}, type={type(self.user_registrations)}, id={id(self.user_registrations)}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        self._verify_metric_in_registry('user_registrations_total', self.user_registrations, Counter)
        
        self.user_logins = _get_or_create_metric('user_logins_total', Counter, 'Total number of user logins', ['auth_method', 'account_type'])
        custom_log(f"MetricsCollector._create_metrics: user_logins = {self.user_logins}, type={type(self.user_logins)}, id={id(self.user_logins)}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        self._verify_metric_in_registry('user_logins_total', self.user_logins, Counter)
        
        self.active_users = _get_or_create_metric('active_users_current', Gauge, 'Current number of active users', ['time_period'])
        self.guest_conversions = _get_or_create_metric('guest_account_conversions_total', Counter, 'Total number of guest account conversions', ['conversion_method'])
        
        # Game Metrics
        self.games_created = _get_or_create_metric('dutch_games_created_total', Counter, 'Total number of Dutch games created', ['game_mode'])
        self.games_completed = _get_or_create_metric('dutch_games_completed_total', Counter, 'Total number of Dutch games completed', ['game_mode', 'result'])
        self.game_duration = _get_or_create_metric('dutch_game_duration_seconds', Histogram, 'Dutch game duration in seconds', ['game_mode'])
        self.coin_transactions = _get_or_create_metric('dutch_coin_transactions_total', Counter, 'Total number of Dutch coin transactions', ['transaction_type', 'direction'])
        self.special_card_used = _get_or_create_metric('dutch_special_card_used_total', Counter, 'Total number of special card uses', ['card_type'])
        self.dutch_calls = _get_or_create_metric('dutch_calls_total', Counter, 'Total number of Dutch calls', ['game_mode'])
        
        custom_log("MetricsCollector._create_metrics: Completed metric creation", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _verify_metric_in_registry(self, metric_name: str, metric_object, metric_type):
        """
        Verify that a metric object is the same instance registered in REGISTRY.
        
        This helps debug issues where metrics are incremented but not appearing in /metrics endpoint.
        """
        try:
            # Find the metric in REGISTRY
            registry_metric = None
            for collector, names in REGISTRY._collector_to_names.items():
                if metric_name in names and isinstance(collector, metric_type):
                    registry_metric = collector
                    break
            
            if registry_metric is None:
                custom_log(f"MetricsCollector._verify_metric_in_registry: WARNING - '{metric_name}' NOT FOUND in REGISTRY!", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
                return False
            
            # Check if it's the same object
            if registry_metric is metric_object:
                custom_log(f"MetricsCollector._verify_metric_in_registry: ✅ '{metric_name}' - SAME object in REGISTRY (id={id(metric_object)})", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
                return True
            else:
                custom_log(f"MetricsCollector._verify_metric_in_registry: ❌ '{metric_name}' - DIFFERENT objects! stored_id={id(metric_object)}, registry_id={id(registry_metric)}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
                custom_log(f"MetricsCollector._verify_metric_in_registry: stored={metric_object}, registry={registry_metric}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
                return False
        except Exception as e:
            custom_log(f"MetricsCollector._verify_metric_in_registry: Error verifying '{metric_name}': {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            import traceback
            custom_log(f"MetricsCollector._verify_metric_in_registry: Traceback: {traceback.format_exc()}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            return False
    
    def verify_http_server_registry(self):
        """
        Verify that the HTTP server is using the same REGISTRY as our metrics.
        This helps debug why metrics might not appear in the /metrics endpoint.
        """
        try:
            from prometheus_client import generate_latest
            registry_output = generate_latest(REGISTRY).decode('utf-8')
            
            # Check for our metrics
            user_logins_lines = [l for l in registry_output.split('\n') 
                                if 'user_logins_total' in l and not l.startswith('#') and l.strip()]
            user_regs_lines = [l for l in registry_output.split('\n') 
                              if 'user_registrations_total' in l and not l.startswith('#') and l.strip()]
            
            custom_log(f"MetricsCollector.verify_http_server_registry: REGISTRY output check - user_logins_total: {len(user_logins_lines)} lines, user_registrations_total: {len(user_regs_lines)} lines", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
            
            if user_logins_lines:
                custom_log(f"MetricsCollector.verify_http_server_registry: user_logins_total values:", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
                for line in user_logins_lines[:5]:
                    custom_log(f"MetricsCollector.verify_http_server_registry:   {line}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
            else:
                custom_log(f"MetricsCollector.verify_http_server_registry: WARNING - No user_logins_total values in REGISTRY output!", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
            
            return {
                'user_logins_count': len(user_logins_lines),
                'user_registrations_count': len(user_regs_lines),
                'user_logins_lines': user_logins_lines[:10],
                'user_registrations_lines': user_regs_lines[:10]
            }
        except Exception as e:
            custom_log(f"MetricsCollector.verify_http_server_registry: Error: {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            import traceback
            custom_log(f"MetricsCollector.verify_http_server_registry: Traceback: {traceback.format_exc()}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            return None
    
    def collect_metric(self, metric_type: str, payload: Dict[str, Any], isOn: bool = True):
        """
        Unified method to collect metrics.
        
        Args:
            metric_type: Type of metric to collect (e.g., 'user_login', 'game_created')
            payload: Dictionary containing metric data
            isOn: Whether metrics collection is enabled (typically from module's METRICS_SWITCH)
        """
        custom_log(f"MetricsCollector.collect_metric: Called - metric_type={metric_type}, payload={payload}, isOn={isOn}, METRICS_COLLECTION_ENABLED={METRICS_COLLECTION_ENABLED}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        custom_log(f"MetricsCollector.collect_metric: self._metric_handlers exists? {hasattr(self, '_metric_handlers')}, type: {type(getattr(self, '_metric_handlers', None))}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Check global and local switches
        if not METRICS_COLLECTION_ENABLED:
            custom_log(f"MetricsCollector.collect_metric: Global switch METRICS_COLLECTION_ENABLED is False, skipping {metric_type}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            return
        
        if not isOn:
            custom_log(f"MetricsCollector.collect_metric: Local switch isOn is False, skipping {metric_type}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            return
        
        # Get handler from registry
        if not hasattr(self, '_metric_handlers') or self._metric_handlers is None:
            custom_log(f"MetricsCollector.collect_metric: ERROR - _metric_handlers not initialized! Available handlers: None", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            return
        
        handler = self._metric_handlers.get(metric_type)
        if not handler:
            custom_log(f"MetricsCollector.collect_metric: Unknown metric type '{metric_type}'. Available handlers: {list(self._metric_handlers.keys())}", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
            return
        
        custom_log(f"MetricsCollector.collect_metric: Found handler for {metric_type} (handler={handler}, handler_id={id(handler)}), calling handler with payload={payload}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Call handler
        try:
            handler(payload)
            custom_log(f"MetricsCollector.collect_metric: Successfully executed handler for {metric_type}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"MetricsCollector.collect_metric: Error collecting metric '{metric_type}': {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            import traceback
            custom_log(f"MetricsCollector.collect_metric: Traceback: {traceback.format_exc()}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
    
    # Metric handlers registry - initialized in __init__
    _metric_handlers = None
    
    # Private handler functions (converted from track_* methods)
    def _handle_request(self, payload: Dict[str, Any]):
        """Handle request metrics."""
        method = payload.get('method')
        endpoint = payload.get('endpoint')
        status = payload.get('status')
        duration = payload.get('duration', 0.0)
        size = payload.get('size', 0)
        
        self.request_count.labels(method=method, endpoint=endpoint, status=status).inc()
        self.request_latency.labels(method=method, endpoint=endpoint).observe(duration)
        self.request_size.labels(method=method, endpoint=endpoint).observe(size)
        custom_log(f"MetricsCollector: Tracked request - {method} {endpoint} status={status} duration={duration:.3f}s", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_credit_transaction(self, payload: Dict[str, Any]):
        """Handle credit transaction metrics."""
        transaction_type = payload.get('transaction_type')
        status = payload.get('status')
        amount = payload.get('amount', 0.0)
        
        self.credit_transactions.labels(type=transaction_type, status=status).inc()
        custom_log(f"MetricsCollector: Tracked credit transaction - type={transaction_type} status={status} amount={amount}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_credit_balance(self, payload: Dict[str, Any]):
        """Handle credit balance update."""
        user_id = payload.get('user_id')
        balance = payload.get('balance', 0.0)
        
        self.credit_balance.labels(user_id=user_id).set(balance)
        custom_log(f"MetricsCollector: Updated credit balance - user_id={user_id} balance={balance}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_mongodb_connections(self, payload: Dict[str, Any]):
        """Handle MongoDB connections update."""
        count = payload.get('count', 0)
        
        self.mongodb_connections.set(count)
        custom_log(f"MetricsCollector: Updated MongoDB connections - count={count}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_redis_connections(self, payload: Dict[str, Any]):
        """Handle Redis connections update."""
        count = payload.get('count', 0)
        
        self.redis_connections.set(count)
        custom_log(f"MetricsCollector: Updated Redis connections - count={count}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_user_registration(self, payload: Dict[str, Any]):
        """Handle user registration metrics."""
        registration_type = payload.get('registration_type')
        account_type = payload.get('account_type')
        
        custom_log(f"MetricsCollector._handle_user_registration: Called with payload={payload}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        custom_log(f"MetricsCollector._handle_user_registration: user_registrations metric object: {self.user_registrations}, id: {id(self.user_registrations)}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Verify the Counter is still in REGISTRY before incrementing
        self._verify_metric_in_registry('user_registrations_total', self.user_registrations, Counter)
        
        try:
            labeled_metric = self.user_registrations.labels(registration_type=registration_type, account_type=account_type)
            custom_log(f"MetricsCollector._handle_user_registration: Got labeled metric: {labeled_metric}, type: {type(labeled_metric)}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            
            # Increment the labeled metric (Counter handles the labeled instance internally)
            labeled_metric.inc()
            
            custom_log(f"MetricsCollector._handle_user_registration: Successfully incremented labeled metric", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            custom_log(f"MetricsCollector: Tracked user registration - type={registration_type} account_type={account_type}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"MetricsCollector._handle_user_registration: Error: {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            import traceback
            custom_log(f"MetricsCollector._handle_user_registration: Traceback: {traceback.format_exc()}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            raise
    
    def _handle_user_login(self, payload: Dict[str, Any]):
        """Handle user login metrics."""
        auth_method = payload.get('auth_method')
        account_type = payload.get('account_type')
        
        custom_log(f"MetricsCollector._handle_user_login: Called with payload={payload}, auth_method={auth_method}, account_type={account_type}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        custom_log(f"MetricsCollector._handle_user_login: user_logins metric object: {self.user_logins}, type: {type(self.user_logins)}, id: {id(self.user_logins)}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
        
        # Verify the Counter is still in REGISTRY before incrementing
        self._verify_metric_in_registry('user_logins_total', self.user_logins, Counter)
        
        try:
            labeled_metric = self.user_logins.labels(auth_method=auth_method, account_type=account_type)
            custom_log(f"MetricsCollector._handle_user_login: Got labeled metric: {labeled_metric}, type: {type(labeled_metric)}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            
            # In Prometheus client, .labels() returns the Counter itself (configured with label values)
            # The Counter manages labeled instances internally via _metrics dict
            custom_log(f"MetricsCollector._handle_user_login: labeled_metric is same as self.user_logins? {labeled_metric is self.user_logins}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            
            # Increment the labeled metric (Counter handles the labeled instance internally)
            labeled_metric.inc()
            
            custom_log(f"MetricsCollector._handle_user_login: Successfully incremented labeled metric", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            
            # Check what REGISTRY would serve
            try:
                from prometheus_client import generate_latest
                registry_output = generate_latest(REGISTRY).decode('utf-8')
                user_logins_lines = [l for l in registry_output.split('\n') 
                                    if 'user_logins_total' in l and not l.startswith('#') and l.strip()]
                custom_log(f"MetricsCollector._handle_user_login: REGISTRY output for user_logins_total: {len(user_logins_lines)} lines", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
                for line in user_logins_lines[:3]:
                    custom_log(f"MetricsCollector._handle_user_login:   {line}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
            except Exception as e:
                custom_log(f"MetricsCollector._handle_user_login: Could not check REGISTRY output: {e}", level="WARNING", isOn=MetricsCollector.LOGGING_SWITCH)
            
            custom_log(f"MetricsCollector: Tracked user login - auth_method={auth_method} account_type={account_type}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"MetricsCollector._handle_user_login: Error incrementing metric: {e}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            import traceback
            custom_log(f"MetricsCollector._handle_user_login: Traceback: {traceback.format_exc()}", level="ERROR", isOn=MetricsCollector.LOGGING_SWITCH)
            raise
    
    def _handle_active_users(self, payload: Dict[str, Any]):
        """Handle active users update."""
        time_period = payload.get('time_period')
        count = payload.get('count', 0)
        
        self.active_users.labels(time_period=time_period).set(count)
        custom_log(f"MetricsCollector: Updated active users - period={time_period} count={count}", level="DEBUG", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_guest_conversion(self, payload: Dict[str, Any]):
        """Handle guest conversion metrics."""
        conversion_method = payload.get('conversion_method')
        
        self.guest_conversions.labels(conversion_method=conversion_method).inc()
        custom_log(f"MetricsCollector: Tracked guest conversion - method={conversion_method}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_game_created(self, payload: Dict[str, Any]):
        """Handle game creation metrics."""
        game_mode = payload.get('game_mode')
        
        self.games_created.labels(game_mode=game_mode).inc()
        custom_log(f"MetricsCollector: Tracked game created - mode={game_mode}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_game_completed(self, payload: Dict[str, Any]):
        """Handle game completion metrics."""
        game_mode = payload.get('game_mode')
        result = payload.get('result')
        duration = payload.get('duration', 0.0)
        
        self.games_completed.labels(game_mode=game_mode, result=result).inc()
        self.game_duration.labels(game_mode=game_mode).observe(duration)
        custom_log(f"MetricsCollector: Tracked game completed - mode={game_mode} result={result} duration={duration:.2f}s", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_coin_transaction(self, payload: Dict[str, Any]):
        """Handle coin transaction metrics."""
        transaction_type = payload.get('transaction_type')
        direction = payload.get('direction')
        amount = payload.get('amount', 1.0)
        
        self.coin_transactions.labels(transaction_type=transaction_type, direction=direction).inc(amount)
        custom_log(f"MetricsCollector: Tracked coin transaction - type={transaction_type} direction={direction} amount={amount}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_special_card_used(self, payload: Dict[str, Any]):
        """Handle special card usage metrics."""
        card_type = payload.get('card_type')
        
        self.special_card_used.labels(card_type=card_type).inc()
        custom_log(f"MetricsCollector: Tracked special card used - card_type={card_type}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)
    
    def _handle_dutch_called(self, payload: Dict[str, Any]):
        """Handle Dutch call metrics."""
        game_mode = payload.get('game_mode')
        
        self.dutch_calls.labels(game_mode=game_mode).inc()
        custom_log(f"MetricsCollector: Tracked Dutch called - mode={game_mode}", level="INFO", isOn=MetricsCollector.LOGGING_SWITCH)


# Note: metrics_collector instance is now managed by AppManager
# Do not create a module-level instance here to avoid multiple instances
# Access through app_manager.get_metrics_collector() instead
