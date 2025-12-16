"""
Analytics Service

This service handles tracking and storing user events in MongoDB for analytics purposes.
"""

from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta
from tools.logger.custom_logging import custom_log


class AnalyticsService:
    """Service for tracking and querying user analytics events."""
    
    LOGGING_SWITCH = True
    
    def __init__(self, app_manager=None):
        """Initialize Analytics Service."""
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
        platform: Optional[str] = None,
        metrics_enabled: bool = True
    ) -> bool:
        """
        Track a user event in MongoDB and automatically update Prometheus metrics.
        
        Args:
            user_id: User ID who performed the event
            event_type: Type of event (e.g., 'user_registered', 'screen_viewed')
            event_data: Additional event data as dictionary
            session_id: Optional session ID for tracking user sessions
            platform: Optional platform identifier ('web', 'android', 'ios')
            metrics_enabled: Whether to update Prometheus metrics (default: True)
                            Typically pass the module's METRICS_SWITCH value
            
        Returns:
            True if event was tracked successfully, False otherwise
        """
        custom_log(f"AnalyticsService.track_event: Called - event_type={event_type}, user_id={user_id}, metrics_enabled={metrics_enabled}", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
        
        if not self.db_manager:
            custom_log("AnalyticsService: Database manager not available", level="WARNING", isOn=AnalyticsService.LOGGING_SWITCH)
            return False
        
        try:
            event = {
                'user_id': user_id,
                'event_type': event_type,
                'event_data': event_data,
                'session_id': session_id,
                'platform': platform,
                'timestamp': datetime.utcnow().isoformat(),
                'created_at': datetime.utcnow()
            }
            
            result = self.db_manager.insert("user_events", event)
            if result:
                custom_log(f"AnalyticsService: Event inserted to MongoDB - event_type={event_type}, user_id={user_id}", level="INFO", isOn=AnalyticsService.LOGGING_SWITCH)
                # Automatically update Prometheus metrics for relevant events
                if metrics_enabled:
                    custom_log(f"AnalyticsService: Metrics enabled, calling _update_metrics_from_event for {event_type}", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
                    self._update_metrics_from_event(event_type, event_data)
                else:
                    custom_log(f"AnalyticsService: Metrics disabled (metrics_enabled=False), skipping metric update for {event_type}", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
                return True
            else:
                custom_log(f"AnalyticsService: Failed to insert event: {event_type}", level="ERROR", isOn=AnalyticsService.LOGGING_SWITCH)
                return False
                
        except Exception as e:
            custom_log(f"AnalyticsService: Error tracking event {event_type}: {e}", level="ERROR", isOn=AnalyticsService.LOGGING_SWITCH)
            return False
    
    def _update_metrics_from_event(self, event_type: str, event_data: Dict[str, Any]):
        """
        Automatically update Prometheus metrics based on event type.
        
        This eliminates duplication - events tracked in MongoDB also update metrics.
        
        Args:
            event_type: Type of event
            event_data: Event data dictionary
        """
        custom_log(f"AnalyticsService._update_metrics_from_event: Called - event_type={event_type}, event_data={event_data}", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
        
        if not self.app_manager:
            custom_log("AnalyticsService._update_metrics_from_event: app_manager not available", level="WARNING", isOn=AnalyticsService.LOGGING_SWITCH)
            return
        
        metrics_collector = self.app_manager.get_metrics_collector()
        if not metrics_collector:
            custom_log("AnalyticsService._update_metrics_from_event: metrics_collector not available", level="WARNING", isOn=AnalyticsService.LOGGING_SWITCH)
            return
        
        custom_log(f"AnalyticsService._update_metrics_from_event: metrics_collector obtained, looking up mapping for {event_type}", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
        
        # Map event types to metric types and extract payload
        event_to_metric_map = {
            'user_logged_in': {
                'metric_type': 'user_login',
                'payload': {
                    'auth_method': event_data.get('auth_method', 'unknown'),
                    'account_type': event_data.get('account_type', 'normal')
                }
            },
            'google_sign_in': {
                'metric_type': 'user_login',
                'payload': {
                    'auth_method': 'google',
                    'account_type': event_data.get('account_type', 'normal')
                }
            },
            'user_registered': {
                'metric_type': 'user_registration',
                'payload': {
                    'registration_type': event_data.get('registration_type', 'unknown'),
                    'account_type': event_data.get('account_type', 'normal')
                }
            },
            'guest_account_converted': {
                'metric_type': 'guest_conversion',
                'payload': {
                    'conversion_method': event_data.get('conversion_method', 'unknown')
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
            'coin_transaction': {
                'metric_type': 'coin_transaction',
                'payload': {
                    'transaction_type': event_data.get('transaction_type', 'unknown'),
                    'direction': event_data.get('direction', 'unknown'),
                    'amount': event_data.get('amount', 1.0)
                }
            },
            'special_card_used': {
                'metric_type': 'special_card_used',
                'payload': {
                    'card_type': event_data.get('card_type', 'unknown')
                }
            },
            'cleco_called': {
                'metric_type': 'cleco_called',
                'payload': {
                    'game_mode': event_data.get('game_mode', 'unknown')
                }
            }
        }
        
        # Check if this event type should update metrics
        metric_config = event_to_metric_map.get(event_type)
        if metric_config:
            custom_log(f"AnalyticsService._update_metrics_from_event: Found mapping - event_type={event_type} → metric_type={metric_config['metric_type']}, payload={metric_config['payload']}", level="INFO", isOn=AnalyticsService.LOGGING_SWITCH)
            try:
                # Metrics are enabled at track_event() level via metrics_enabled parameter
                # This respects the module's METRICS_SWITCH when passed
                custom_log(f"AnalyticsService._update_metrics_from_event: Calling metrics_collector.collect_metric(metric_type={metric_config['metric_type']}, payload={metric_config['payload']})", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
                metrics_collector.collect_metric(
                    metric_config['metric_type'],
                    metric_config['payload'],
                    isOn=True  # Already checked at track_event() level
                )
                custom_log(f"AnalyticsService._update_metrics_from_event: Successfully called collect_metric for {metric_config['metric_type']}", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
            except Exception as e:
                custom_log(f"AnalyticsService: Error updating metrics for event {event_type}: {e}", level="ERROR", isOn=AnalyticsService.LOGGING_SWITCH)
        else:
            custom_log(f"AnalyticsService._update_metrics_from_event: No metric mapping found for event_type={event_type} (not a metric-tracked event)", level="DEBUG", isOn=AnalyticsService.LOGGING_SWITCH)
    
    def get_user_events(
        self,
        user_id: str,
        event_type: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """
        Query user events from MongoDB.
        
        Args:
            user_id: User ID to query events for
            event_type: Optional filter by event type
            start_date: Optional start date for filtering
            end_date: Optional end date for filtering
            limit: Maximum number of events to return
            
        Returns:
            List of event documents
        """
        if not self.db_manager:
            return []
        
        try:
            query = {'user_id': user_id}
            
            if event_type:
                query['event_type'] = event_type
            
            if start_date or end_date:
                query['timestamp'] = {}
                if start_date:
                    query['timestamp']['$gte'] = start_date.isoformat()
                if end_date:
                    query['timestamp']['$lte'] = end_date.isoformat()
            
            events = self.db_manager.find("user_events", query, limit=limit)
            return events if events else []
            
        except Exception as e:
            custom_log(f"AnalyticsService: Error querying events: {e}", level="ERROR")
            return []
    
    def get_event_summary(
        self,
        event_type: str,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> Dict[str, Any]:
        """
        Get summary statistics for an event type.
        
        Args:
            event_type: Event type to summarize
            start_date: Optional start date for filtering
            end_date: Optional end date for filtering
            
        Returns:
            Dictionary with summary statistics
        """
        if not self.db_manager:
            return {'count': 0, 'unique_users': 0}
        
        try:
            query = {'event_type': event_type}
            
            if start_date or end_date:
                query['timestamp'] = {}
                if start_date:
                    query['timestamp']['$gte'] = start_date.isoformat()
                if end_date:
                    query['timestamp']['$lte'] = end_date.isoformat()
            
            # Count total events
            count = self.db_manager.count("user_events", query)
            
            # Count unique users (would need aggregation for accurate count)
            # For now, return count and approximate unique users
            events = self.db_manager.find("user_events", query, limit=1000)
            unique_users = len(set(event.get('user_id') for event in events if event.get('user_id')))
            
            return {
                'count': count,
                'unique_users': unique_users,
                'event_type': event_type
            }
            
        except Exception as e:
            custom_log(f"AnalyticsService: Error getting event summary: {e}", level="ERROR")
            return {'count': 0, 'unique_users': 0}
    
    def health_check(self) -> Dict[str, Any]:
        """
        Check service health.
        
        Returns:
            Dictionary with health status
        """
        return {
            'service': 'analytics_service',
            'status': 'healthy' if self.db_manager else 'unhealthy',
            'db_manager_available': self.db_manager is not None,
            'details': 'Analytics service for tracking user events'
        }
