# Metrics and User Analytics Recommendation

## Overview

This document provides recommendations for implementing comprehensive metrics and user app usage monitoring for the Recall application. The solution builds upon the existing Prometheus infrastructure and integrates with the manager-based architecture.

## Current State

### ✅ Existing Infrastructure

**Backend (Python)**:
- Prometheus client (`prometheus-client==0.19.0`)
- Prometheus Flask Exporter (`prometheus-flask-exporter==0.23.2`)
- `MetricsCollector` class in `core/monitoring/metrics_collector.py`
- Grafana dashboards configured
- System metrics (MongoDB/Redis connections)
- API metrics (request count, latency, size)
- Credit system metrics

**Frontend (Flutter)**:
- No analytics packages currently installed
- Event system exists for game actions
- State management via StateManager

### ❌ Missing Components

- User behavior analytics
- App usage tracking
- User engagement metrics
- Feature adoption tracking
- User journey/flow tracking
- Game-specific user metrics
- Authentication/registration analytics

---

## Recommended Solution Architecture

### 1. Backend: Extend Prometheus Metrics

**Approach**: Extend existing `MetricsCollector` to include user and business metrics.

**Benefits**:
- ✅ Leverages existing infrastructure
- ✅ No additional dependencies
- ✅ Integrates with Grafana dashboards
- ✅ Privacy-compliant (data stays in your infrastructure)
- ✅ Cost-effective (no third-party service fees)

**Metrics to Add**:

#### User Metrics
- User registrations (by type: email, guest, Google)
- User logins (by auth method)
- Active users (daily/weekly/monthly)
- User retention (day 1, day 7, day 30)
- Guest account conversions
- Account linking events

#### Game Metrics
- Games created
- Games completed
- Average game duration
- Games per user
- Win/loss ratios
- Coin transactions (earned/spent)
- Special card usage (Queen peek, Jack swap)
- Cleco calls

#### Feature Usage Metrics
- Feature adoption rates
- Screen views/navigation
- Button clicks/interactions
- Error rates by feature

### 2. Backend: User Event Tracking Service

**Approach**: Create a new `AnalyticsService` that stores user events in MongoDB.

**Benefits**:
- ✅ Detailed user journey tracking
- ✅ Queryable event history
- ✅ Custom analytics queries
- ✅ Privacy-compliant (data in your database)
- ✅ No external dependencies

**Event Storage**:
- Collection: `user_events`
- Structure: `{user_id, event_type, event_data, timestamp, session_id, platform, ...}`
- Indexed for fast queries
- Retention policy (e.g., 90 days for detailed events, aggregated metrics forever)

### 3. Frontend: Custom Analytics Module

**Approach**: Create a Flutter `AnalyticsModule` that tracks events and sends to backend.

**Benefits**:
- ✅ Integrated with existing module system
- ✅ Consistent with architecture patterns
- ✅ Privacy-compliant (user controls data)
- ✅ No third-party SDKs required
- ✅ Works offline (queue events, send when online)

**Event Types to Track**:
- Screen views
- Button clicks
- Feature usage
- Game actions
- Authentication events
- Errors/exceptions

### 4. Optional: Third-Party Analytics (Future)

**Options** (if needed later):
- **Firebase Analytics**: Free, Google-owned, good Flutter support
- **Mixpanel**: Powerful, user-friendly, paid
- **Amplitude**: Great for product analytics, paid
- **PostHog**: Open-source, self-hostable, privacy-focused

**Recommendation**: Start with custom solution, add third-party only if needed for advanced features.

---

## Implementation Plan

### Phase 1: Backend User Metrics (Prometheus)

**Extend `MetricsCollector`** with user and business metrics:

```python
# User Registration Metrics
self.user_registrations = Counter(
    'user_registrations_total',
    'Total user registrations',
    ['registration_type', 'account_type']  # email/guest/google, normal/guest
)

self.user_logins = Counter(
    'user_logins_total',
    'Total user logins',
    ['auth_method', 'account_type']  # email/google, normal/guest
)

self.active_users = Gauge(
    'active_users_current',
    'Current number of active users',
    ['time_period']  # daily/weekly/monthly
)

# Game Metrics
self.games_created = Counter(
    'cleco_games_created_total',
    'Total games created',
    ['game_mode']  # practice/multiplayer
)

self.games_completed = Counter(
    'cleco_games_completed_total',
    'Total games completed',
    ['game_mode', 'result']  # practice/multiplayer, win/loss
)

self.game_duration = Histogram(
    'cleco_game_duration_seconds',
    'Game duration in seconds',
    ['game_mode']
)

# Guest Conversion Metrics
self.guest_conversions = Counter(
    'guest_account_conversions_total',
    'Total guest account conversions',
    ['conversion_method']  # email/google
)
```

**Integration Points**:
- `UserManagementModule`: Track registrations, logins, conversions
- `ClecoGameMain`: Track game events, coin transactions
- `LoginModule`: Track authentication events

### Phase 2: Backend Event Tracking Service

**Create `AnalyticsService`**:

```python
# core/services/analytics_service.py
class AnalyticsService:
    def track_event(
        self,
        user_id: str,
        event_type: str,
        event_data: Dict[str, Any],
        session_id: str = None,
        platform: str = None
    ):
        """Track user event in MongoDB."""
        event = {
            'user_id': user_id,
            'event_type': event_type,
            'event_data': event_data,
            'session_id': session_id,
            'platform': platform,
            'timestamp': datetime.utcnow().isoformat(),
            'created_at': datetime.utcnow()
        }
        # Store in MongoDB user_events collection
        # Index on: user_id, event_type, timestamp
```

**Event Types**:
- `user_registered` - User registration
- `user_logged_in` - User login
- `user_logged_out` - User logout
- `guest_account_created` - Guest account creation
- `guest_account_converted` - Guest account conversion
- `google_sign_in` - Google Sign-In
- `screen_viewed` - Screen navigation
- `feature_used` - Feature usage
- `game_created` - Game creation
- `game_started` - Game start
- `game_completed` - Game completion
- `card_played` - Card play action
- `cleco_called` - Cleco call
- `error_occurred` - Error/exception

### Phase 3: Frontend Analytics Module

**Create `AnalyticsModule`**:

```dart
// lib/modules/analytics_module/analytics_module.dart
class AnalyticsModule extends ModuleBase {
  Future<void> trackEvent({
    required String eventType,
    Map<String, dynamic>? eventData,
  }) async {
    // Get current user ID
    final userId = await _getCurrentUserId();
    if (userId == null) return;
    
    // Queue event (for offline support)
    await _queueEvent(userId, eventType, eventData);
    
    // Send to backend
    await _sendEventToBackend(userId, eventType, eventData);
  }
  
  Future<void> trackScreenView(String screenName) async {
    await trackEvent(
      eventType: 'screen_viewed',
      eventData: {'screen_name': screenName},
    );
  }
  
  Future<void> trackButtonClick(String buttonName, {String? screenName}) async {
    await trackEvent(
      eventType: 'button_clicked',
      eventData: {
        'button_name': buttonName,
        'screen_name': screenName,
      },
    );
  }
}
```

**Integration Points**:
- `AccountScreen`: Track registration, login, Google Sign-In
- `ClecoGameModule`: Track game events
- `NavigationManager`: Track screen views
- `PlayerAction`: Track game actions

### Phase 4: Analytics Dashboard

**Grafana Dashboards**:
1. **User Analytics Dashboard**
   - User registrations over time
   - Login trends
   - Active users (DAU/WAU/MAU)
   - Guest account conversions
   - Auth method distribution

2. **Game Analytics Dashboard**
   - Games created/completed
   - Average game duration
   - Win/loss ratios
   - Coin transactions
   - Popular features

3. **System Health Dashboard** (extend existing)
   - API performance
   - Error rates
   - Database performance
   - WebSocket connections

---

## Recommended Metrics to Track

### User Metrics

#### Registration & Authentication
- Total registrations (by type: email, guest, Google)
- Registration conversion rate
- Login frequency
- Session duration
- Guest account conversion rate
- Account linking events

#### User Engagement
- Daily Active Users (DAU)
- Weekly Active Users (WAU)
- Monthly Active Users (MAU)
- User retention (Day 1, Day 7, Day 30)
- Average sessions per user
- Average session duration

### Game Metrics

#### Game Activity
- Games created per day
- Games completed per day
- Average game duration
- Games per user
- Abandoned games rate

#### Gameplay
- Win/loss ratio
- Average points per game
- Coin earnings/spending
- Special card usage (Queen peek, Jack swap)
- Cleco calls per game
- Out-of-turn plays

### Feature Usage

#### Navigation
- Screen views (most visited screens)
- Navigation paths
- Time spent per screen
- Feature discovery rate

#### Interactions
- Button clicks (most used features)
- Feature adoption rate
- Error rates by feature
- User drop-off points

### Technical Metrics

#### Performance
- API response times
- Screen load times
- Game state update latency
- WebSocket message latency

#### Errors
- Error rate by endpoint
- Error rate by feature
- Crash rate
- Network error rate

---

## Implementation Details

### Backend: MetricsCollector Extension

**File**: `python_base_04/core/monitoring/metrics_collector.py`

**Add Methods**:
```python
def track_user_registration(self, registration_type: str, account_type: str):
    """Track user registration."""
    self.user_registrations.labels(
        registration_type=registration_type,
        account_type=account_type
    ).inc()

def track_user_login(self, auth_method: str, account_type: str):
    """Track user login."""
    self.user_logins.labels(
        auth_method=auth_method,
        account_type=account_type
    ).inc()

def track_guest_conversion(self, conversion_method: str):
    """Track guest account conversion."""
    self.guest_conversions.labels(
        conversion_method=conversion_method
    ).inc()

def track_game_created(self, game_mode: str):
    """Track game creation."""
    self.games_created.labels(game_mode=game_mode).inc()

def track_game_completed(self, game_mode: str, result: str, duration: float):
    """Track game completion."""
    self.games_completed.labels(
        game_mode=game_mode,
        result=result
    ).inc()
    self.game_duration.labels(game_mode=game_mode).observe(duration)
```

### Backend: AnalyticsService

**File**: `python_base_04/core/services/analytics_service.py` (new)

**Implementation**:
```python
from core.managers.database_manager import DatabaseManager
from datetime import datetime
from typing import Dict, Any, Optional

class AnalyticsService:
    def __init__(self, app_manager=None):
        self.app_manager = app_manager
        self.db_manager = None
        if app_manager:
            self.db_manager = app_manager.get_db_manager(role="read_write")
    
    def track_event(
        self,
        user_id: str,
        event_type: str,
        event_data: Dict[str, Any],
        session_id: Optional[str] = None,
        platform: Optional[str] = None
    ):
        """Track user event in MongoDB."""
        if not self.db_manager:
            return
        
        event = {
            'user_id': user_id,
            'event_type': event_type,
            'event_data': event_data,
            'session_id': session_id,
            'platform': platform,
            'timestamp': datetime.utcnow().isoformat(),
            'created_at': datetime.utcnow()
        }
        
        try:
            self.db_manager.insert("user_events", event)
        except Exception as e:
            custom_log(f"AnalyticsService: Error tracking event: {e}", level="ERROR")
    
    def get_user_events(
        self,
        user_id: str,
        event_type: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        limit: int = 100
    ):
        """Query user events."""
        if not self.db_manager:
            return []
        
        query = {'user_id': user_id}
        if event_type:
            query['event_type'] = event_type
        if start_date or end_date:
            query['timestamp'] = {}
            if start_date:
                query['timestamp']['$gte'] = start_date.isoformat()
            if end_date:
                query['timestamp']['$lte'] = end_date.isoformat()
        
        return self.db_manager.find("user_events", query, limit=limit)
```

### Frontend: AnalyticsModule

**File**: `flutter_base_05/lib/modules/analytics_module/analytics_module.dart` (new)

**Implementation**:
```dart
class AnalyticsModule extends ModuleBase {
  AnalyticsModule() : super("analytics_module", dependencies: ["connections_api_module"]);
  
  ConnectionsApiModule? _connectionModule;
  SharedPrefManager? _sharedPref;
  List<Map<String, dynamic>> _eventQueue = [];
  
  Future<void> trackEvent({
    required String eventType,
    Map<String, dynamic>? eventData,
  }) async {
    final userId = await _getCurrentUserId();
    if (userId == null) {
      // Queue for later if user not logged in
      _eventQueue.add({
        'event_type': eventType,
        'event_data': eventData ?? {},
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }
    
    await _sendEventToBackend(userId, eventType, eventData);
  }
  
  Future<void> trackScreenView(String screenName) async {
    await trackEvent(
      eventType: 'screen_viewed',
      eventData: {'screen_name': screenName},
    );
  }
  
  Future<void> trackButtonClick(String buttonName, {String? screenName}) async {
    await trackEvent(
      eventType: 'button_clicked',
      eventData: {
        'button_name': buttonName,
        'screen_name': screenName,
      },
    );
  }
  
  Future<void> _sendEventToBackend(
    String userId,
    String eventType,
    Map<String, dynamic>? eventData,
  ) async {
    try {
      await _connectionModule?.sendPostRequest(
        '/userauth/analytics/track',
        {
          'user_id': userId,
          'event_type': eventType,
          'event_data': eventData ?? {},
          'platform': _getPlatform(),
        },
      );
    } catch (e) {
      // Queue event for retry
      _eventQueue.add({
        'user_id': userId,
        'event_type': eventType,
        'event_data': eventData ?? {},
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
}
```

### Backend: Analytics Endpoint

**File**: `python_base_04/core/modules/analytics_module/analytics_main.py` (new module)

**Implementation**:
```python
class AnalyticsModule(BaseModule):
    def register_routes(self):
        self._register_auth_route_helper(
            "/userauth/analytics/track",
            self.track_event,
            methods=["POST"]
        )
    
    def track_event(self):
        """Track user event."""
        data = request.get_json()
        user_id = data.get('user_id')
        event_type = data.get('event_type')
        event_data = data.get('event_data', {})
        platform = data.get('platform')
        
        # Track in MongoDB
        analytics_service = self.app_manager.get_service('analytics_service')
        analytics_service.track_event(
            user_id=user_id,
            event_type=event_type,
            event_data=event_data,
            platform=platform
        )
        
        # Update Prometheus metrics
        metrics_collector.track_user_event(event_type)
        
        return jsonify({"success": True}), 200
```

---

## Privacy Considerations

### Data Collection
- ✅ Only collect necessary data
- ✅ Anonymize user IDs in aggregated metrics
- ✅ Allow users to opt-out (future enhancement)
- ✅ Comply with GDPR/CCPA (if applicable)

### Data Retention
- **Detailed Events**: 90 days (for debugging/analysis)
- **Aggregated Metrics**: Forever (for trends)
- **User-specific Events**: Configurable retention

### Data Storage
- ✅ All data stored in your infrastructure
- ✅ No third-party data sharing
- ✅ Encrypted at rest (MongoDB encryption)
- ✅ Access controlled (authentication required)

---

## Recommended Tools Comparison

### Option 1: Custom Solution (Recommended)

**Pros**:
- ✅ Full control over data
- ✅ Privacy-compliant
- ✅ No third-party costs
- ✅ Integrates with existing infrastructure
- ✅ Customizable to your needs

**Cons**:
- ⚠️ Requires development time
- ⚠️ Need to build dashboards
- ⚠️ Need to maintain infrastructure

**Best For**: Privacy-focused apps, custom requirements, cost-sensitive projects

### Option 2: Firebase Analytics

**Pros**:
- ✅ Free tier available
- ✅ Good Flutter support
- ✅ Easy setup
- ✅ Google ecosystem integration

**Cons**:
- ⚠️ Data stored on Google servers
- ⚠️ Privacy concerns
- ⚠️ Limited customization
- ⚠️ Vendor lock-in

**Best For**: Quick setup, Google ecosystem apps, MVP stage

### Option 3: Mixpanel

**Pros**:
- ✅ Powerful analytics
- ✅ User-friendly interface
- ✅ Great for product analytics
- ✅ Good Flutter SDK

**Cons**:
- ⚠️ Paid service (expensive at scale)
- ⚠️ Data stored externally
- ⚠️ Privacy concerns

**Best For**: Product-focused apps, when budget allows, need advanced features

### Option 4: PostHog (Self-Hosted)

**Pros**:
- ✅ Open-source
- ✅ Self-hostable
- ✅ Privacy-focused
- ✅ Feature flags + analytics

**Cons**:
- ⚠️ Requires infrastructure
- ⚠️ Setup complexity
- ⚠️ Maintenance overhead

**Best For**: Privacy-focused apps, need feature flags, have DevOps resources

---

## Recommendation Summary

### Immediate Implementation (Phase 1-2)

**Start with Custom Solution**:
1. ✅ Extend existing `MetricsCollector` with user/game metrics
2. ✅ Create `AnalyticsService` for event tracking
3. ✅ Integrate with existing modules (UserManagement, ClecoGame)
4. ✅ Build Grafana dashboards

**Why**:
- Leverages existing Prometheus infrastructure
- Privacy-compliant (data stays in your system)
- Cost-effective (no third-party fees)
- Full control and customization
- Aligns with your architecture patterns

### Future Enhancements (Phase 3-4)

1. **Frontend Analytics Module**: Track screen views, button clicks, feature usage
2. **Advanced Dashboards**: User journey, funnel analysis, cohort analysis
3. **Real-time Analytics**: Live user activity monitoring
4. **A/B Testing**: Feature flag integration for experiments

### Optional: Third-Party Integration

**If needed later**, consider:
- **PostHog** (self-hosted) for advanced product analytics
- **Firebase Analytics** for quick insights (if privacy allows)
- **Custom solution** remains primary (most control)

---

## Implementation Priority

### High Priority (Immediate Value)
1. ✅ User registration/login metrics
2. ✅ Game creation/completion metrics
3. ✅ Active users tracking
4. ✅ Guest account conversion tracking

### Medium Priority (Next Sprint)
1. ✅ Screen view tracking
2. ✅ Feature usage tracking
3. ✅ Error tracking
4. ✅ User event history

### Low Priority (Future)
1. ⏳ Advanced user journey analysis
2. ⏳ Cohort analysis
3. ⏳ A/B testing infrastructure
4. ⏳ Real-time dashboards

---

## Next Steps

1. **Review this recommendation** and decide on approach
2. **Extend MetricsCollector** with user/game metrics
3. **Create AnalyticsService** for event tracking
4. **Integrate tracking** in UserManagementModule and ClecoGameMain
5. **Build Grafana dashboards** for visualization
6. **Create Flutter AnalyticsModule** (Phase 3)
7. **Test and iterate** based on insights

---

## Questions to Consider

1. **Privacy Requirements**: Do you need GDPR/CCPA compliance? (affects data retention)
2. **Budget**: Can you afford third-party services? (affects tool choice)
3. **Infrastructure**: Can you maintain self-hosted solutions? (affects PostHog option)
4. **Timeline**: Need quick setup or can invest in custom solution? (affects approach)
5. **Team Skills**: Comfortable with Prometheus/Grafana? (affects implementation)

---

**Recommendation**: Start with **Custom Solution (Phases 1-2)** - extend Prometheus metrics and create AnalyticsService. This gives you immediate value, privacy compliance, and full control, while leveraging your existing infrastructure.
