# Metrics System Configuration

This document explains how to configure and set up the metrics system.

## Prerequisites

1. **Docker & Docker Compose**: For running Prometheus and Grafana containers
2. **Python Dependencies**: `prometheus_client` (installed via requirements.txt)
3. **Flask Application**: Running on port 5001 (or configured port)

## File Structure

```
python_base_04/
├── core/
│   ├── monitoring/
│   │   └── metrics_collector.py      # Metrics collection logic
│   └── services/
│       └── analytics_service.py       # Event tracking service
├── grafana/
│   ├── prometheus/
│   │   └── prometheus.yml            # Prometheus configuration
│   └── provisioning/
│       ├── datasources/
│       │   └── prometheus.yml        # Grafana datasource config
│       └── dashboards/
│           ├── game_analytics.json   # Game metrics dashboard
│           ├── user_analytics.json   # User metrics dashboard
│           └── credit_system.json    # Credit system dashboard
└── app.debug.py                      # Flask app with /metrics endpoint
```

## Configuration Files

### 1. Prometheus Configuration

**File**: `python_base_04/grafana/prometheus/prometheus.yml`

**Key Settings**:
```yaml
global:
  scrape_interval: 15s          # How often to scrape metrics
  evaluation_interval: 15s      # How often to evaluate rules

scrape_configs:
  - job_name: 'flask-app-metrics'
    scrape_interval: 15s
    static_configs:
      # Primary: Flask route endpoint (recommended for development)
      - targets: ['host.docker.internal:5001']
        labels:
          instance: 'flask-app'
          service: 'flask-app-metrics'
          endpoint: 'flask-route'
      # Fallback: Separate HTTP server (for production)
      - targets: ['host.docker.internal:8000']
        labels:
          instance: 'flask-app'
          service: 'flask-app-metrics'
          endpoint: 'http-server'
```

**Notes**:
- `host.docker.internal` allows container to access host machine
- Flask runs locally (not in container), so use `host.docker.internal`
- Scrape interval: 15 seconds (adjust based on needs)

### 2. Grafana Datasource Configuration

**File**: `python_base_04/grafana/provisioning/datasources/prometheus.yml`

**Configuration**:
```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    version: 1
```

**Notes**:
- `url: http://prometheus:9090` uses Docker service name
- `isDefault: true` makes it the default datasource
- `editable: true` allows manual editing in Grafana UI

### 3. Grafana Dashboard Configuration

**File**: `python_base_04/grafana/provisioning/dashboards/dashboards.yml`

**Configuration**:
```yaml
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
```

**Dashboard Files**:
- `game_analytics.json` - Game metrics dashboard
- `user_analytics.json` - User metrics dashboard
- `credit_system.json` - Credit system metrics dashboard

## Docker Compose Configuration

**File**: `docker-compose.debug.yml`

**Prometheus Service**:
```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./python_base_04/grafana/prometheus:/etc/prometheus
    - prometheus_data:/prometheus
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
  networks:
    - app-network
```

**Grafana Service**:
```yaml
grafana:
  image: grafana/grafana:latest
  container_name: grafana
  ports:
    - "3001:3000"
  environment:
    - GF_SECURITY_ADMIN_USER=admin
    - GF_SECURITY_ADMIN_PASSWORD=admin
  volumes:
    - grafana_data:/var/lib/grafana
    - ./python_base_04/grafana/provisioning:/etc/grafana/provisioning
    - ./python_base_04/grafana/dashboards:/var/lib/grafana/dashboards
  depends_on:
    - prometheus
  networks:
    - app-network
```

## Application Configuration

### 1. MetricsCollector Initialization

**Location**: `core/managers/app_manager.py`

**Code**:
```python
# Initialize metrics collector (singleton)
self.metrics_collector = MetricsCollector(port=8000)
```

**Port Configuration**:
- Default: 8000 (separate HTTP server)
- Flask route: 5001 (configured in Flask app)

### 2. Flask Metrics Endpoint

**Location**: `app.debug.py`

**Code**:
```python
@app.route('/metrics')
def metrics_endpoint():
    from prometheus_client import generate_latest, REGISTRY
    return Response(
        generate_latest(REGISTRY),
        mimetype='text/plain; version=0.0.4; charset=utf-8'
    )
```

### 3. Module-Level Switches

**Location**: Each module file

**Example**:
```python
# In user_management_main.py
METRICS_SWITCH = True
LOGGING_SWITCH = True

# Usage
analytics_service.track_event(
    ...,
    metrics_enabled=UserManagementModule.METRICS_SWITCH
)
```

## Setup Steps

### 1. Start Docker Containers

```bash
cd /Users/sil/Documents/Work/reignofplay/Recall/app_dev
docker-compose -f docker-compose.debug.yml up -d prometheus grafana
```

### 2. Verify Containers

```bash
docker ps | grep -E "prometheus|grafana"
```

### 3. Start Flask Application

```bash
cd python_base_04
python app.debug.py
```

### 4. Verify Metrics Endpoint

```bash
curl http://localhost:5001/metrics | head -20
```

### 5. Check Prometheus

- Open: http://localhost:9090
- Go to: Status → Targets
- Verify: `flask-app-metrics` target is UP

### 6. Check Grafana

- Open: http://localhost:3001
- Login: admin / admin
- Verify: Dashboards are loaded
- Verify: Prometheus datasource is configured

## Configuration Switches

### Global Switches

**METRICS_COLLECTION_ENABLED**
- **Location**: `core/monitoring/metrics_collector.py`
- **Default**: `True`
- **Purpose**: Master switch for all metrics collection
- **Usage**: Set to `False` to disable all metrics

### Module Switches

**METRICS_SWITCH**
- **Location**: Each module file (e.g., `user_management_main.py`)
- **Default**: `True` (in configured modules)
- **Purpose**: Control metrics collection per module
- **Usage**: Pass to `track_event(metrics_enabled=MODULE.METRICS_SWITCH)`

**LOGGING_SWITCH**
- **Location**: Each module file
- **Default**: `True` (in configured modules)
- **Purpose**: Control debug logging for metrics
- **Usage**: Automatically used in logging calls

## Environment Variables

### Flask Application

No specific environment variables required for metrics. Flask runs on:
- Port 5001 (configured in Flask app)
- Port 8000 (separate HTTP server, optional)

### Prometheus

No environment variables required. Configuration via `prometheus.yml`.

### Grafana

**Environment Variables** (in docker-compose):
```yaml
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=admin
GF_SERVER_ROOT_URL=http://localhost:3001
```

## Troubleshooting

### Metrics Not Appearing

1. **Check Flask is running**:
   ```bash
   curl http://localhost:5001/metrics
   ```

2. **Check Prometheus can scrape**:
   - Open: http://localhost:9090/targets
   - Verify: Target status is UP

3. **Check metrics in Prometheus**:
   ```bash
   curl 'http://localhost:9090/api/v1/query?query=user_logins_total'
   ```

4. **Check logs**:
   ```bash
   tail -f python_base_04/tools/logger/server.log | grep -i metric
   ```

### Grafana "No Data"

1. **Check datasource connection**:
   - Grafana UI → Configuration → Data Sources → Prometheus → Test

2. **Check dashboard queries**:
   - Verify queries use correct metric names
   - Check time range (last 5 minutes, etc.)

3. **Check Prometheus has data**:
   ```bash
   curl 'http://localhost:9090/api/v1/query?query=cleco_games_completed_total'
   ```

### Port Conflicts

1. **Port 8000 in use**:
   ```bash
   lsof -i :8000
   kill <PID>
   ```

2. **Port 5001 in use**:
   - Change Flask port or kill conflicting process

3. **Port 9090 in use**:
   - Change Prometheus port in docker-compose.yml

## Production Considerations

1. **Use Flask route endpoint** (port 5001) for development
2. **Use separate HTTP server** (port 8000) for production
3. **Adjust scrape intervals** based on load
4. **Configure retention** in Prometheus (default: 15 days)
5. **Set up alerts** in Grafana for critical metrics
6. **Use authentication** for Grafana in production
7. **Backup Grafana dashboards** regularly

## Next Steps

- See [OVERVIEW.md](./OVERVIEW.md) for system architecture
- See [METRICS_DEFINITIONS.md](./METRICS_DEFINITIONS.md) for metric details
- See [DASHBOARDS.md](./DASHBOARDS.md) for dashboard configuration
