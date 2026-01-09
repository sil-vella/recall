# Metrics Collection Flow

This document explains how metrics are collected, from application events to Prometheus storage.

## Collection Architecture

### 1. Event Trigger

Metrics collection starts when an application event occurs:

**Example: User Login**
```python
# In user_management_main.py
analytics_service.track_event(
    user_id=user_id,
    event_type='user_logged_in',
    event_data={
        'auth_method': 'email',
        'account_type': 'normal'
    },
    metrics_enabled=UserManagementModule.METRICS_SWITCH
)
```

### 2. AnalyticsService.track_event()

**Location**: `core/services/analytics_service.py`

**Process**:
1. Validates database manager availability
2. Creates event document with timestamp
3. Inserts event into MongoDB `user_events` collection
4. If `metrics_enabled=True`, calls `_update_metrics_from_event()`

**Code Flow**:
```python
def track_event(self, user_id, event_type, event_data, metrics_enabled=True):
    # 1. Store in MongoDB
    event = {
        'user_id': user_id,
        'event_type': event_type,
        'event_data': event_data,
        'timestamp': datetime.utcnow().isoformat()
    }
    self.db_manager.insert("user_events", event)
    
    # 2. Update metrics if enabled
    if metrics_enabled:
        self._update_metrics_from_event(event_type, event_data)
```

### 3. AnalyticsService._update_metrics_from_event()

**Location**: `core/services/analytics_service.py`

**Process**:
1. Maps event type to metric type using `event_to_metric_map`
2. Extracts payload from event_data
3. Gets MetricsCollector from AppManager
4. Calls `metrics_collector.collect_metric()`

**Event-to-Metric Mapping**:
```python
event_to_metric_map = {
    'user_logged_in': {
        'metric_type': 'user_login',
        'payload': {
            'auth_method': event_data.get('auth_method', 'unknown'),
            'account_type': event_data.get('account_type', 'normal')
        }
    },
    'game_completed': {
        'metric_type': 'game_completed',
        'payload': {
            'game_mode': event_data.get('game_mode', 'unknown'),
            'result': event_data.get('result', 'unknown'),
            'duration': event_data.get('duration', 0.0)
        }
    },
    # ... more mappings
}
```

### 4. MetricsCollector.collect_metric()

**Location**: `core/monitoring/metrics_collector.py`

**Process**:
1. Checks global switch `METRICS_COLLECTION_ENABLED`
2. Checks local switch `isOn` parameter
3. Looks up handler from `_metric_handlers` registry
4. Calls handler function with payload

**Code Flow**:
```python
def collect_metric(self, metric_type, payload, isOn=True):
    # Check switches
    if not METRICS_COLLECTION_ENABLED or not isOn:
        return
    
    # Get handler
    handler = self._metric_handlers.get(metric_type)
    if not handler:
        return
    
    # Call handler
    handler(payload)
```

### 5. Metric Handler

**Location**: `core/monitoring/metrics_collector.py`

Each metric type has a dedicated handler function that:
1. Extracts label values from payload
2. Gets labeled metric instance
3. Updates metric (inc(), set(), observe())

**Example Handler**:
```python
def _handle_user_login(self, payload):
    auth_method = payload.get('auth_method')
    account_type = payload.get('account_type')
    
    # Get labeled counter instance
    labeled_metric = self.user_logins.labels(
        auth_method=auth_method,
        account_type=account_type
    )
    
    # Increment counter
    labeled_metric.inc()
```

### 6. Prometheus REGISTRY

**Location**: `prometheus_client.REGISTRY`

**Process**:
- All metrics are registered in the global `REGISTRY`
- Prometheus client library manages metric storage
- Metrics are stored in memory until scraped

### 7. Metrics Exposure

#### Option A: Flask Route (Primary - Development)
**Location**: `app.debug.py` - `/metrics` endpoint

**Process**:
1. Flask route handler receives request
2. Calls `generate_latest(REGISTRY)`
3. Returns Prometheus-formatted text
4. Prometheus scrapes from `http://localhost:5001/metrics`

**Why**: Ensures metrics are from current Flask process (avoids Flask debug reloader issues)

#### Option B: HTTP Server (Fallback - Production)
**Location**: `metrics_collector.py` - `start_http_server()`

**Process**:
1. Separate HTTP server starts on port 8000
2. Serves metrics from `REGISTRY`
3. Prometheus scrapes from `http://localhost:8000/metrics`

**Why**: Separate process for production environments

### 8. Prometheus Scraping

**Location**: `grafana/prometheus/prometheus.yml`

**Process**:
1. Prometheus scrapes Flask endpoint every 15 seconds
2. Parses Prometheus text format
3. Stores metrics in time-series database
4. Labels are preserved as time-series labels

**Configuration**:
```yaml
scrape_configs:
  - job_name: 'flask-app-metrics'
    scrape_interval: 15s
    static_configs:
      - targets: ['host.docker.internal:5001']  # Flask route
      - targets: ['host.docker.internal:8000']  # HTTP server (fallback)
```

### 9. Grafana Visualization

**Location**: Grafana dashboards in `grafana/provisioning/dashboards/`

**Process**:
1. Grafana queries Prometheus via PromQL
2. Displays metrics in dashboard panels
3. Auto-refreshes every 30 seconds (configurable)

## Direct Metric Collection (Bypassing AnalyticsService)

Some metrics are collected directly without going through AnalyticsService:

### System Metrics (AppManager)

**Location**: `core/managers/app_manager.py`

**Examples**:
- Request metrics (via Flask middleware)
- MongoDB/Redis connections (periodic updates)
- Active users (periodic calculations)

**Code Flow**:
```python
# In AppManager middleware
self.metrics_collector.collect_metric('request', {
    'method': request.method,
    'endpoint': request.endpoint,
    'status': response.status_code,
    'duration': duration
}, isOn=AppManager.METRICS_SWITCH)
```

### Periodic Updates

**Location**: `core/managers/app_manager.py` - `_setup_system_metrics()`

**Scheduled Tasks**:
- MongoDB connections: Every 60 seconds
- Redis connections: Every 60 seconds
- Active users: Every 60 seconds (daily, weekly, monthly)

## Collection Switches

### Global Switch
```python
# In metrics_collector.py
METRICS_COLLECTION_ENABLED = True  # Master switch
```

### Module Switches
```python
# In each module
METRICS_SWITCH = True  # Module-specific switch
```

### Usage
```python
# Pass module switch to track_event
analytics_service.track_event(
    ...,
    metrics_enabled=MODULE.METRICS_SWITCH
)

# Or pass to collect_metric directly
metrics_collector.collect_metric(
    ...,
    isOn=MODULE.METRICS_SWITCH
)
```

## Error Handling

### Metrics Collection Errors
- Errors in handlers are logged but don't crash the application
- Missing handlers log warnings
- Invalid payloads are handled gracefully

### Prometheus Scraping Errors
- If Flask endpoint is down, Prometheus logs errors but continues
- Fallback to HTTP server if Flask route fails
- Missing metrics appear as "No data" in Grafana

## Performance Considerations

1. **Synchronous Collection**: Metrics collection is synchronous (blocks request)
2. **MongoDB Write**: Event storage happens before metric update
3. **Memory Storage**: Metrics stored in memory until scraped
4. **Scrape Interval**: 15 seconds (configurable in prometheus.yml)
5. **Dashboard Refresh**: 30 seconds (configurable in Grafana)

## Debugging

### Enable Logging
```python
# In metrics_collector.py
LOGGING_SWITCH = false

# In analytics_service.py
LOGGING_SWITCH = false

# In modules
LOGGING_SWITCH = false
```

### Check Metrics Endpoint
```bash
curl http://localhost:5001/metrics | grep user_logins_total
```

### Check Prometheus
```bash
curl 'http://localhost:9090/api/v1/query?query=user_logins_total'
```

### Check Logs
```bash
tail -f python_base_04/tools/logger/server.log | grep -i metric
```
