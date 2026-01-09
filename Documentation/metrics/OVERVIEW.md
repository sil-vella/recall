# Metrics System Overview

## Introduction

The Dutch application uses a comprehensive metrics and monitoring system built on **Prometheus** and **Grafana**. This system tracks application performance, user behavior, game analytics, and system health metrics.

## Architecture

### Components

1. **MetricsCollector** (`core/monitoring/metrics_collector.py`)
   - Singleton class managing all Prometheus metrics
   - Handles metric creation, registration, and collection
   - Exposes metrics via HTTP server (port 8000) and Flask route (port 5001)

2. **AnalyticsService** (`core/services/analytics_service.py`)
   - Unified service for tracking user events
   - Automatically updates Prometheus metrics when events are tracked
   - Stores events in MongoDB for historical analysis

3. **Prometheus** (Container)
   - Time-series database for metrics storage
   - Scrapes metrics from Flask application every 15 seconds
   - Configuration: `python_base_04/grafana/prometheus/prometheus.yml`

4. **Grafana** (Container)
   - Visualization platform for metrics
   - Pre-configured dashboards for game analytics, user analytics, and credit system
   - Configuration: `python_base_04/grafana/provisioning/`

### Data Flow

```
Application Event
    ↓
analytics_service.track_event()
    ↓
MongoDB (user_events collection)
    ↓
AnalyticsService._update_metrics_from_event()
    ↓
MetricsCollector.collect_metric()
    ↓
Prometheus Metric (in REGISTRY)
    ↓
Flask /metrics endpoint (port 5001)
    ↓
Prometheus Scraper (every 15s)
    ↓
Prometheus Time-Series DB
    ↓
Grafana Dashboards (visualization)
```

## Metrics Exposure

### Primary Endpoint (Development)
- **Flask Route**: `http://localhost:5001/metrics`
- **Why**: Ensures metrics are always from the current Flask process
- **Use Case**: Development with Flask debug reloader

### Fallback Endpoint (Production)
- **HTTP Server**: `http://localhost:8000/metrics`
- **Why**: Separate HTTP server for production environments
- **Use Case**: Production deployments without Flask debug mode

## Configuration Switches

### Global Switches

1. **METRICS_COLLECTION_ENABLED** (`metrics_collector.py`)
   - Global master switch for all metrics collection
   - Default: `True`

2. **METRICS_SWITCH** (Module-level)
   - Each module has its own `METRICS_SWITCH = True/False`
   - Controls whether that module's events update metrics
   - Passed to `analytics_service.track_event(metrics_enabled=MODULE.METRICS_SWITCH)`

3. **LOGGING_SWITCH** (Module-level)
   - Controls debug logging for metrics collection
   - Useful for troubleshooting metric collection issues

### Module-Level Switches

- `AppManager.METRICS_SWITCH = True`
- `UserManagementModule.METRICS_SWITCH = True`
- `DutchGameModule.METRICS_SWITCH = True`

## Metric Types

The system uses three Prometheus metric types:

1. **Counter**: Monotonically increasing values (e.g., total logins, games completed)
2. **Gauge**: Values that can go up or down (e.g., active users, connection counts)
3. **Histogram**: Distribution of values over time (e.g., request latency, game duration)

## Platforms

### Python Backend (Primary)
- All metrics are collected in the Python Flask backend
- Metrics are exposed via Flask route and separate HTTP server
- Event tracking happens through `AnalyticsService`

### Flutter Frontend
- **No direct metrics collection**
- Frontend sends events to backend via API/WebSocket
- Backend tracks events and updates metrics

## File Locations

### Configuration Files (Host Filesystem)
- Prometheus: `python_base_04/grafana/prometheus/prometheus.yml`
- Grafana Datasource: `python_base_04/grafana/provisioning/datasources/prometheus.yml`
- Grafana Dashboards: `python_base_04/grafana/provisioning/dashboards/*.json`

### Code Files
- MetricsCollector: `python_base_04/core/monitoring/metrics_collector.py`
- AnalyticsService: `python_base_04/core/services/analytics_service.py`
- Flask Metrics Route: `python_base_04/app.debug.py` (line 95-145)

## Access Points

- **Prometheus UI**: http://localhost:9090
- **Grafana UI**: http://localhost:3001 (admin/admin)
- **Metrics Endpoint**: http://localhost:5001/metrics
- **Metrics HTTP Server**: http://localhost:8000/metrics

## Next Steps

- See [METRICS_DEFINITIONS.md](./METRICS_DEFINITIONS.md) for complete list of metrics
- See [COLLECTION_FLOW.md](./COLLECTION_FLOW.md) for how metrics are collected
- See [CONFIGURATION.md](./CONFIGURATION.md) for setup and configuration
- See [DASHBOARDS.md](./DASHBOARDS.md) for Grafana dashboard details
