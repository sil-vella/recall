# Metrics System Documentation

This directory contains comprehensive documentation for the Recall application's metrics and monitoring system.

## Documentation Index

### [OVERVIEW.md](./OVERVIEW.md)
Complete overview of the metrics system architecture, components, data flow, and configuration.

**Topics**:
- System architecture
- Component descriptions
- Data flow diagram
- Configuration switches
- File locations
- Access points

### [METRICS_DEFINITIONS.md](./METRICS_DEFINITIONS.md)
Complete reference of all metrics collected by the system.

**Topics**:
- API metrics (requests, latency, size)
- User metrics (registrations, logins, active users)
- Game metrics (games created, completed, duration, coins, cards)
- Business metrics (credit transactions, balances)
- System metrics (MongoDB, Redis connections)
- Event-to-metric mappings
- Prometheus query examples

### [COLLECTION_FLOW.md](./COLLECTION_FLOW.md)
Detailed explanation of how metrics are collected from application events to Prometheus storage.

**Topics**:
- Event trigger → AnalyticsService → MetricsCollector flow
- Handler functions and metric updates
- Metrics exposure (Flask route vs HTTP server)
- Prometheus scraping
- Direct metric collection
- Error handling
- Performance considerations
- Debugging tips

### [CONFIGURATION.md](./CONFIGURATION.md)
Setup and configuration guide for the metrics system.

**Topics**:
- File structure
- Prometheus configuration
- Grafana datasource configuration
- Docker Compose setup
- Application configuration
- Setup steps
- Configuration switches
- Troubleshooting

### [DASHBOARDS.md](./DASHBOARDS.md)
Grafana dashboard documentation and customization guide.

**Topics**:
- Dashboard locations and configuration
- Game Analytics dashboard panels
- User Analytics dashboard panels
- Credit System dashboard panels
- Dashboard access
- Customization guide
- Query examples
- Troubleshooting

## Quick Start

1. **Read Overview**: Start with [OVERVIEW.md](./OVERVIEW.md) to understand the system
2. **Check Metrics**: See [METRICS_DEFINITIONS.md](./METRICS_DEFINITIONS.md) for available metrics
3. **Setup**: Follow [CONFIGURATION.md](./CONFIGURATION.md) for setup instructions
4. **View Dashboards**: See [DASHBOARDS.md](./DASHBOARDS.md) for dashboard details

## System Components

- **MetricsCollector**: Core metrics collection class
- **AnalyticsService**: Event tracking and metric updates
- **Prometheus**: Time-series database for metrics storage
- **Grafana**: Visualization platform for dashboards

## Key Concepts

- **Metrics are collected in Python backend only**
- **Flutter frontend sends events to backend via API/WebSocket**
- **Metrics exposed via Flask route (port 5001) and HTTP server (port 8000)**
- **Prometheus scrapes every 15 seconds**
- **Grafana dashboards auto-refresh every 30 seconds**

## Access Points

- **Prometheus UI**: http://localhost:9090
- **Grafana UI**: http://localhost:3001 (admin/admin)
- **Metrics Endpoint**: http://localhost:5001/metrics
- **Metrics HTTP Server**: http://localhost:8000/metrics

## Support

For issues or questions:
1. Check [CONFIGURATION.md](./CONFIGURATION.md) troubleshooting section
2. Review logs: `python_base_04/tools/logger/server.log`
3. Check Prometheus targets: http://localhost:9090/targets
4. Verify metrics endpoint: `curl http://localhost:5001/metrics`
