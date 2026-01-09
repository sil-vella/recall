# Metrics Definitions

This document provides a complete reference of all metrics collected by the Dutch application.

## Metric Naming Convention

- **Format**: `{component}_{metric_name}_{unit}`
- **Examples**: `user_logins_total`, `flask_app_request_duration_seconds`
- **Units**: `_total` for counters, `_seconds` for duration, `_bytes` for size

## API Metrics

### `flask_app_requests_total`
- **Type**: Counter
- **Labels**: `method`, `endpoint`, `status`
- **Description**: Total number of HTTP requests to Flask application
- **Triggered**: Every Flask request (via AppManager middleware)
- **Example Labels**:
  - `method="POST"`, `endpoint="/api/users/register"`, `status="201"`

### `flask_app_request_duration_seconds`
- **Type**: Histogram
- **Labels**: `method`, `endpoint`
- **Description**: Request latency distribution in seconds
- **Triggered**: Every Flask request (via AppManager middleware)
- **Buckets**: Default Prometheus histogram buckets

### `flask_app_request_size_bytes`
- **Type**: Histogram
- **Labels**: `method`, `endpoint`
- **Description**: Request size distribution in bytes
- **Triggered**: Every Flask request (via AppManager middleware)

## User Metrics

### `user_registrations_total`
- **Type**: Counter
- **Labels**: `registration_type`, `account_type`
- **Description**: Total number of user registrations
- **Triggered**: `user_registered` event via AnalyticsService
- **Label Values**:
  - `registration_type`: `"email"`, `"google"`, `"guest"`
  - `account_type`: `"normal"`, `"premium"`, `"admin"`

### `user_logins_total`
- **Type**: Counter
- **Labels**: `auth_method`, `account_type`
- **Description**: Total number of user logins
- **Triggered**: `user_logged_in` or `google_sign_in` event via AnalyticsService
- **Label Values**:
  - `auth_method`: `"email"`, `"google"`, `"jwt"`, `"session"`
  - `account_type`: `"normal"`, `"premium"`, `"admin"`

### `active_users_current`
- **Type**: Gauge
- **Labels**: `time_period`
- **Description**: Current number of active users
- **Triggered**: Periodic update (every 60 seconds) via AppManager scheduler
- **Label Values**:
  - `time_period`: `"daily"` (last 24h), `"weekly"` (last 7d), `"monthly"` (last 30d)

### `guest_account_conversions_total`
- **Type**: Counter
- **Labels**: `conversion_method`
- **Description**: Total number of guest account conversions to full accounts
- **Triggered**: `guest_account_converted` event via AnalyticsService
- **Label Values**:
  - `conversion_method`: `"email"`, `"google"`, `"phone"`

## Game Metrics

### `dutch_games_created_total`
- **Type**: Counter
- **Labels**: `game_mode`
- **Description**: Total number of Dutch games created
- **Triggered**: `game_created` event (currently not implemented in codebase)
- **Label Values**:
  - `game_mode`: `"practice"`, `"multiplayer"`, `"tournament"`

### `dutch_games_completed_total`
- **Type**: Counter
- **Labels**: `game_mode`, `result`
- **Description**: Total number of Dutch games completed (per player)
- **Triggered**: `game_completed` event via AnalyticsService
- **Label Values**:
  - `game_mode`: `"practice"`, `"multiplayer"`, `"tournament"`
  - `result`: `"win"`, `"loss"`
- **Note**: One game completion creates one metric per player (1 winner = 1 win, 3 losers = 3 losses)

### `dutch_game_duration_seconds`
- **Type**: Histogram
- **Labels**: `game_mode`
- **Description**: Distribution of game duration in seconds
- **Triggered**: `game_completed` event via AnalyticsService
- **Label Values**:
  - `game_mode`: `"practice"`, `"multiplayer"`, `"tournament"`

### `dutch_coin_transactions_total`
- **Type**: Counter
- **Labels**: `transaction_type`, `direction`
- **Description**: Total number of Dutch coin transactions
- **Triggered**: `coin_transaction` event via AnalyticsService
- **Label Values**:
  - `transaction_type`: `"game_reward"`, `"purchase"`, `"refund"`, `"bonus"`
  - `direction`: `"credit"` (coins added), `"debit"` (coins spent)
- **Increment Amount**: Can be incremented by amount (e.g., `inc(amount)`)

### `dutch_special_card_used_total`
- **Type**: Counter
- **Labels**: `card_type`
- **Description**: Total number of special card uses
- **Triggered**: `special_card_used` event (currently not implemented in codebase)
- **Label Values**:
  - `card_type`: `"queen"`, `"jack"`, `"joker"`, `"red_king"`

### `dutch_calls_total`
- **Type**: Counter
- **Labels**: `game_mode`
- **Description**: Total number of "Dutch" calls (final round triggers)
- **Triggered**: `dutch_called` event (currently not implemented in codebase)
- **Label Values**:
  - `game_mode`: `"practice"`, `"multiplayer"`, `"tournament"`

## Business Metrics

### `credit_system_transactions_total`
- **Type**: Counter
- **Labels**: `type`, `status`
- **Description**: Total number of credit system transactions
- **Triggered**: `credit_transaction` metric type via MetricsCollector
- **Label Values**:
  - `type`: Transaction type (e.g., `"purchase"`, `"refund"`)
  - `status`: `"success"`, `"failed"`, `"pending"`

### `credit_system_balance`
- **Type**: Gauge
- **Labels**: `user_id`
- **Description**: Current credit balance for a user
- **Triggered**: `credit_balance` metric type via MetricsCollector
- **Label Values**:
  - `user_id`: User ID string

## System Metrics

### `mongodb_connections`
- **Type**: Gauge
- **Labels**: None
- **Description**: Number of active MongoDB connections
- **Triggered**: Periodic update (every 60 seconds) via AppManager scheduler
- **Method**: `db_manager.get_connection_count()`

### `redis_connections`
- **Type**: Gauge
- **Labels**: None
- **Description**: Number of active Redis connections
- **Triggered**: Periodic update (every 60 seconds) via AppManager scheduler
- **Method**: `redis_manager.get_connection_count()`

## Metric Handlers

Each metric type has a corresponding handler in `MetricsCollector`:

- `_handle_request()` - API metrics
- `_handle_user_registration()` - User registration
- `_handle_user_login()` - User login
- `_handle_active_users()` - Active users gauge
- `_handle_guest_conversion()` - Guest conversions
- `_handle_game_created()` - Game creation
- `_handle_game_completed()` - Game completion
- `_handle_coin_transaction()` - Coin transactions
- `_handle_special_card_used()` - Special card usage
- `_handle_dutch_called()` - Dutch calls
- `_handle_credit_transaction()` - Credit transactions
- `_handle_credit_balance()` - Credit balance
- `_handle_mongodb_connections()` - MongoDB connections
- `_handle_redis_connections()` - Redis connections

## Event-to-Metric Mapping

The `AnalyticsService` automatically maps events to metrics:

| Event Type | Metric Type | Handler |
|------------|-------------|---------|
| `user_registered` | `user_registration` | `_handle_user_registration()` |
| `user_logged_in` | `user_login` | `_handle_user_login()` |
| `google_sign_in` | `user_login` | `_handle_user_login()` |
| `guest_account_converted` | `guest_conversion` | `_handle_guest_conversion()` |
| `game_completed` | `game_completed` | `_handle_game_completed()` |
| `coin_transaction` | `coin_transaction` | `_handle_coin_transaction()` |
| `special_card_used` | `special_card_used` | `_handle_special_card_used()` |
| `dutch_called` | `dutch_called` | `_handle_dutch_called()` |

## Query Examples

### Prometheus Queries

```promql
# Total user logins
sum(user_logins_total)

# User logins by auth method
sum by (auth_method) (user_logins_total)

# Win/Loss ratio
sum by (result) (dutch_games_completed_total)

# Active users (daily)
active_users_current{time_period="daily"}

# Request rate (requests per second)
rate(flask_app_requests_total[5m])

# Average game duration
rate(dutch_game_duration_seconds_sum[5m]) / rate(dutch_game_duration_seconds_count[5m])
```

## Notes

1. **Counters are cumulative**: They only increase, never decrease (except on restart)
2. **Gauges are current values**: They can go up or down
3. **Histograms track distributions**: They create multiple time series (sum, count, buckets)
4. **Labels create separate time series**: Each unique label combination is a separate metric
5. **Metrics persist in Prometheus**: Data is stored in Prometheus time-series database
