"""
Analytics Service

This service handles tracking and storing user events in MongoDB for analytics purposes.
"""

from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta
from tools.logger.custom_logging import custom_log


class AnalyticsService:
    """Service for tracking and querying user analytics events."""
    
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
        platform: Optional[str] = None
    ) -> bool:
        """
        Track a user event in MongoDB.
        
        Args:
            user_id: User ID who performed the event
            event_type: Type of event (e.g., 'user_registered', 'screen_viewed')
            event_data: Additional event data as dictionary
            session_id: Optional session ID for tracking user sessions
            platform: Optional platform identifier ('web', 'android', 'ios')
            
        Returns:
            True if event was tracked successfully, False otherwise
        """
        if not self.db_manager:
            custom_log("AnalyticsService: Database manager not available", level="WARNING")
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
                return True
            else:
                custom_log(f"AnalyticsService: Failed to insert event: {event_type}", level="ERROR")
                return False
                
        except Exception as e:
            custom_log(f"AnalyticsService: Error tracking event {event_type}: {e}", level="ERROR")
            return False
    
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
