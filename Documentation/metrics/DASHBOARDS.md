# Grafana Dashboards

This document describes the pre-configured Grafana dashboards for the Recall application.

## Dashboard Locations

**Provisioning Directory**: `python_base_04/grafana/provisioning/dashboards/`

**Dashboard Files**:
- `game_analytics.json` - Game metrics dashboard
- `user_analytics.json` - User metrics dashboard
- `credit_system.json` - Credit system metrics dashboard

## Dashboard Configuration

**Provisioning Config**: `python_base_04/grafana/provisioning/dashboards/dashboards.yml`

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

**Notes**:
- Dashboards are auto-loaded from provisioning directory
- `allowUiUpdates: true` allows manual edits in Grafana UI
- `updateIntervalSeconds: 10` checks for updates every 10 seconds

## Game Analytics Dashboard

**File**: `game_analytics.json`

**UID**: `game_analytics`

### Panels

#### 1. Games Created Over Time
- **Type**: Time series
- **Query**: `dutch_games_completed_total`
- **Legend**: `{{game_mode}} - {{result}}`
- **Unit**: `short` (count)
- **Description**: Shows cumulative games completed over time, grouped by game mode and result

#### 2. Games Completed Over Time
- **Type**: Time series
- **Query**: `dutch_games_completed_total`
- **Legend**: `{{game_mode}} - {{result}}`
- **Unit**: `short` (count)
- **Description**: Same as above (duplicate panel, can be customized)

#### 3. Win/Loss Ratio
- **Type**: Pie chart
- **Query**: `sum by (result) (dutch_games_completed_total)`
- **Legend**: `{{result}}`
- **Description**: Shows aggregate win/loss ratio across all games and users
- **Note**: Aggregates all player results (1 game with 1 winner, 3 losers = 1 win, 3 losses)

#### 4. Game Duration Distribution
- **Type**: Histogram
- **Query**: `dutch_game_duration_seconds`
- **Legend**: `{{game_mode}}`
- **Unit**: `s` (seconds)
- **Description**: Distribution of game durations by game mode

#### 5. Coin Transactions
- **Type**: Time series
- **Query**: `dutch_coin_transactions_total`
- **Legend**: `{{transaction_type}} - {{direction}}`
- **Unit**: `short` (count)
- **Description**: Total coin transactions over time, grouped by type and direction

#### 6. Special Card Usage
- **Type**: Time series
- **Query**: `dutch_special_card_used_total`
- **Legend**: `{{card_type}}`
- **Unit**: `short` (count)
- **Description**: Special card usage over time

#### 7. Dutch Calls
- **Type**: Time series
- **Query**: `dutch_calls_total`
- **Legend**: `{{game_mode}}`
- **Unit**: `short` (count)
- **Description**: Total Dutch calls (final round triggers) over time

### Query Notes

- **Counters**: Display raw values (not `rate()` or `increase()`)
- **Units**: Use `short` for counts, `s` for seconds
- **Time Range**: Default last 6 hours (configurable)

## User Analytics Dashboard

**File**: `user_analytics.json`

**UID**: `user_analytics`

### Panels

#### 1. User Registrations
- **Type**: Time series
- **Query**: `user_registrations_total`
- **Legend**: `{{registration_type}} - {{account_type}}`
- **Unit**: `short` (count)
- **Description**: Total user registrations over time

#### 2. User Logins
- **Type**: Time series
- **Query**: `user_logins_total`
- **Legend**: `{{auth_method}} - {{account_type}}`
- **Unit**: `short` (count)
- **Description**: Total user logins over time

#### 3. Active Users
- **Type**: Time series
- **Query**: `active_users_current`
- **Legend**: `{{time_period}}`
- **Unit**: `short` (count)
- **Description**: Current active users by time period (daily, weekly, monthly)

#### 4. Guest Conversions
- **Type**: Time series
- **Query**: `guest_account_conversions_total`
- **Legend**: `{{conversion_method}}`
- **Unit**: `short` (count)
- **Description**: Guest account conversions to full accounts

### Query Notes

- **Gauges**: `active_users_current` shows current values (not cumulative)
- **Counters**: `user_registrations_total`, `user_logins_total` are cumulative

## Credit System Dashboard

**File**: `credit_system.json`

**UID**: `credit_system`

### Panels

#### 1. Credit Transactions
- **Type**: Time series
- **Query**: `credit_system_transactions_total`
- **Legend**: `{{type}} - {{status}}`
- **Unit**: `short` (count)
- **Description**: Total credit transactions over time

#### 2. Credit Balance
- **Type**: Time series
- **Query**: `credit_system_balance`
- **Legend**: `{{user_id}}`
- **Unit**: `short` (balance)
- **Description**: Current credit balance per user

#### 3. Transaction Processing Time
- **Type**: Histogram
- **Query**: `credit_system_transaction_processing_seconds`
- **Legend**: `{{operation_type}}`
- **Unit**: `s` (seconds)
- **Description**: Distribution of transaction processing times

## Dashboard Access

### Via Grafana UI

1. **Open Grafana**: http://localhost:3001
2. **Login**: admin / admin
3. **Navigate**: Dashboards → Browse
4. **Select**: Dashboard from list

### Via Direct URL

- Game Analytics: http://localhost:3001/d/game_analytics
- User Analytics: http://localhost:3001/d/user_analytics
- Credit System: http://localhost:3001/d/credit_system

## Customization

### Editing Dashboards

1. **Via Grafana UI**:
   - Open dashboard
   - Click "Edit" (pencil icon)
   - Modify panels, queries, etc.
   - Click "Save"

2. **Via JSON Files**:
   - Edit JSON files in `grafana/provisioning/dashboards/`
   - Restart Grafana container or wait for auto-reload (10 seconds)

### Adding New Panels

1. **In Grafana UI**:
   - Edit dashboard
   - Click "Add panel"
   - Configure query, visualization, etc.
   - Save dashboard

2. **Export to JSON**:
   - Dashboard settings → JSON Model
   - Copy JSON
   - Update provisioning file

### Query Examples

```promql
# Total games completed
sum(dutch_games_completed_total)

# Games by result
sum by (result) (dutch_games_completed_total)

# Win rate (percentage)
sum(dutch_games_completed_total{result="win"}) / sum(dutch_games_completed_total) * 100

# Average game duration
rate(dutch_game_duration_seconds_sum[5m]) / rate(dutch_game_duration_seconds_count[5m])

# Request rate (requests per second)
rate(flask_app_requests_total[5m])

# Error rate
sum(rate(flask_app_requests_total{status=~"5.."}[5m]))
```

## Dashboard Refresh

### Auto-Refresh

- **Default**: 30 seconds
- **Configurable**: Dashboard settings → Time options → Auto refresh

### Manual Refresh

- Click refresh button (circular arrow icon) in dashboard toolbar

## Troubleshooting

### Dashboard Shows "No Data"

1. **Check Prometheus has data**:
   ```bash
   curl 'http://localhost:9090/api/v1/query?query=dutch_games_completed_total'
   ```

2. **Check time range**:
   - Ensure time range includes when data was collected
   - Try "Last 1 hour" or "Last 6 hours"

3. **Check query syntax**:
   - Verify metric name is correct
   - Check label names match actual labels

4. **Check datasource**:
   - Verify Prometheus datasource is configured
   - Test connection in Grafana UI

### Dashboard Not Loading

1. **Check file location**:
   - Verify JSON files are in `grafana/provisioning/dashboards/`
   - Check file permissions

2. **Check Grafana logs**:
   ```bash
   docker logs grafana | grep -i dashboard
   ```

3. **Restart Grafana**:
   ```bash
   docker restart grafana
   ```

### Queries Return Empty

1. **Verify metrics exist**:
   ```bash
   curl http://localhost:5001/metrics | grep dutch_games_completed_total
   ```

2. **Check label values**:
   - Use Prometheus UI to explore available labels
   - Adjust queries to match actual label values

3. **Check time range**:
   - Metrics may not exist for selected time range
   - Expand time range or check when metrics were created

## Best Practices

1. **Use appropriate units**: `short` for counts, `s` for seconds, `bytes` for sizes
2. **Group by relevant labels**: Use `by (label)` for meaningful groupings
3. **Set reasonable time ranges**: Default 6 hours, adjust based on data volume
4. **Use legends**: Make legends descriptive with label values
5. **Test queries**: Use Prometheus UI to test queries before adding to dashboard
6. **Document custom panels**: Add descriptions to panels for future reference

## Next Steps

- See [OVERVIEW.md](./OVERVIEW.md) for system architecture
- See [METRICS_DEFINITIONS.md](./METRICS_DEFINITIONS.md) for metric details
- See [CONFIGURATION.md](./CONFIGURATION.md) for setup instructions
