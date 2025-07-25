# Google Play Developer API Integration Plan

## Overview

This document outlines the implementation plan for integrating Google Play Developer API into the existing in_app_purchases_module to enable real-time product synchronization and purchase verification.

## Current State Analysis

### ✅ What's Already Implemented
- Complete module architecture with verifiers and sync manager
- Database schema for storing synced products
- API endpoints for manual sync and product retrieval
- Placeholder implementations for Google Play API calls
- Simulated product data for development
- Purchase verification framework

### ❌ What's Missing
- Google Play Developer API client implementation
- Service account authentication setup
- Real product synchronization from Google Play Console
- Google API dependencies
- Configuration management for Google credentials

## Implementation Phases

### Phase 1: Dependencies and Setup (Priority: High)

#### 1.1 Add Google API Dependencies
**File:** `python_base_04/requirements.txt`
```python
# Add these dependencies
google-api-python-client==2.108.0
google-auth==2.23.4
google-auth-httplib2==0.1.1
google-auth-oauthlib==1.1.0
```

#### 1.2 Create Google Play API Configuration
**File:** `python_base_04/utils/config/config.py`
```python
# Add Google Play API configuration
GOOGLE_PLAY_PACKAGE_NAME = get_file_first_config_value("google_play_package_name", "GOOGLE_PLAY_PACKAGE_NAME", "com.yourcompany.yourapp")
GOOGLE_PLAY_SERVICE_ACCOUNT_FILE = get_sensitive_config_value("flask-app/google-play", "service_account_file", "google_play_service_account", "GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", "")
GOOGLE_PLAY_API_QUOTA_LIMIT = int(get_file_first_config_value("google_play_api_quota_limit", "GOOGLE_PLAY_API_QUOTA_LIMIT", "1000"))
GOOGLE_PLAY_SYNC_INTERVAL_HOURS = int(get_file_first_config_value("google_play_sync_interval_hours", "GOOGLE_PLAY_SYNC_INTERVAL_HOURS", "24"))
```

### Phase 2: Google Play API Client (Priority: High)

#### 2.1 Create Google Play API Client
**File:** `python_base_04/core/modules/in_app_purchases_module/sync/google_play_api_client.py`
```python
"""
Google Play Developer API Client

Handles authentication and API calls to Google Play Developer API.
"""

import json
import time
from typing import Dict, List, Any, Optional
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from tools.logger.custom_logging import custom_log

class GooglePlayAPIClient:
    """Client for Google Play Developer API."""
    
    def __init__(self, app_manager):
        self.app_manager = app_manager
        self.service = None
        self.package_name = None
        self.credentials = None
        
    def initialize(self):
        """Initialize the Google Play API client."""
        try:
            # Load configuration
            self.package_name = self.app_manager.config.GOOGLE_PLAY_PACKAGE_NAME
            service_account_file = self.app_manager.config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE
            
            # Load service account credentials
            self.credentials = service_account.Credentials.from_service_account_file(
                service_account_file,
                scopes=['https://www.googleapis.com/auth/androidpublisher']
            )
            
            # Build the service
            self.service = build('androidpublisher', 'v3', credentials=self.credentials)
            
            custom_log("✅ Google Play API client initialized successfully", level="INFO")
            return True
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize Google Play API client: {e}", level="ERROR")
            return False
    
    def get_in_app_products(self) -> List[Dict[str, Any]]:
        """Get all in-app products from Google Play Console."""
        try:
            if not self.service:
                raise Exception("Google Play API client not initialized")
            
            # Call the API
            request = self.service.inappproducts().list(
                packageName=self.package_name
            )
            response = request.execute()
            
            products = []
            for product in response.get('inappproduct', []):
                products.append(self._parse_product(product))
            
            custom_log(f"✅ Retrieved {len(products)} in-app products from Google Play", level="INFO")
            return products
            
        except HttpError as e:
            custom_log(f"❌ Google Play API error: {e}", level="ERROR")
            return []
        except Exception as e:
            custom_log(f"❌ Error getting in-app products: {e}", level="ERROR")
            return []
    
    def get_subscriptions(self) -> List[Dict[str, Any]]:
        """Get all subscriptions from Google Play Console."""
        try:
            if not self.service:
                raise Exception("Google Play API client not initialized")
            
            # Call the API
            request = self.service.monetization().subscriptions().list(
                packageName=self.package_name
            )
            response = request.execute()
            
            subscriptions = []
            for subscription in response.get('subscriptions', []):
                subscriptions.append(self._parse_subscription(subscription))
            
            custom_log(f"✅ Retrieved {len(subscriptions)} subscriptions from Google Play", level="INFO")
            return subscriptions
            
        except HttpError as e:
            custom_log(f"❌ Google Play API error: {e}", level="ERROR")
            return []
        except Exception as e:
            custom_log(f"❌ Error getting subscriptions: {e}", level="ERROR")
            return []
    
    def verify_purchase(self, purchase_token: str, product_id: str) -> Dict[str, Any]:
        """Verify a purchase using Google Play Developer API."""
        try:
            if not self.service:
                raise Exception("Google Play API client not initialized")
            
            # Call the API
            request = self.service.purchases().products().get(
                packageName=self.package_name,
                productId=product_id,
                token=purchase_token
            )
            response = request.execute()
            
            return self._parse_purchase_verification(response)
            
        except HttpError as e:
            custom_log(f"❌ Google Play API error: {e}", level="ERROR")
            return {"valid": False, "error": str(e)}
        except Exception as e:
            custom_log(f"❌ Error verifying purchase: {e}", level="ERROR")
            return {"valid": False, "error": str(e)}
    
    def _parse_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parse Google Play product data into our format."""
        return {
            "product_id": product_data.get("sku"),
            "product_type": "consumable",  # or "non_consumable" based on product type
            "title": product_data.get("defaultLanguage", {}).get("title"),
            "description": product_data.get("defaultLanguage", {}).get("description"),
            "price": self._extract_price(product_data),
            "currency": self._extract_currency(product_data),
            "localized_price": self._extract_localized_price(product_data),
            "available": product_data.get("status") == "active",
            "last_synced": time.time()
        }
    
    def _parse_subscription(self, subscription_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parse Google Play subscription data into our format."""
        return {
            "product_id": subscription_data.get("productId"),
            "product_type": "subscription",
            "title": subscription_data.get("title"),
            "description": subscription_data.get("description"),
            "price": self._extract_subscription_price(subscription_data),
            "currency": self._extract_subscription_currency(subscription_data),
            "subscription_period": subscription_data.get("subscriptionPeriod"),
            "introductory_price": subscription_data.get("introductoryPriceInfo", {}).get("introductoryPriceAmountMicros"),
            "introductory_period": subscription_data.get("introductoryPriceInfo", {}).get("introductoryPricePeriod"),
            "available": subscription_data.get("status") == "active",
            "last_synced": time.time()
        }
    
    def _parse_purchase_verification(self, verification_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parse purchase verification response."""
        return {
            "valid": verification_data.get("purchaseState") == 0,  # 0 = purchased
            "platform": "google_play",
            "product_id": verification_data.get("productId"),
            "transaction_id": verification_data.get("orderId"),
            "purchase_date": verification_data.get("purchaseTime"),
            "amount": verification_data.get("priceAmountMicros", 0) / 1000000,
            "currency": verification_data.get("priceCurrencyCode"),
            "purchase_state": verification_data.get("purchaseState"),
            "acknowledgement_state": verification_data.get("acknowledgementState"),
            "purchase_token": verification_data.get("purchaseToken"),
            "order_id": verification_data.get("orderId"),
            "purchase_time": verification_data.get("purchaseTime"),
            "developer_payload": verification_data.get("developerPayload", ""),
            "purchase_type": verification_data.get("purchaseType")
        }
    
    def _extract_price(self, product_data: Dict[str, Any]) -> float:
        """Extract price from product data."""
        # Implementation depends on Google Play API response structure
        return 0.0
    
    def _extract_currency(self, product_data: Dict[str, Any]) -> str:
        """Extract currency from product data."""
        return "USD"
    
    def _extract_localized_price(self, product_data: Dict[str, Any]) -> str:
        """Extract localized price from product data."""
        return "$0.00"
    
    def _extract_subscription_price(self, subscription_data: Dict[str, Any]) -> float:
        """Extract price from subscription data."""
        return 0.0
    
    def _extract_subscription_currency(self, subscription_data: Dict[str, Any]) -> str:
        """Extract currency from subscription data."""
        return "USD"
```

### Phase 3: Enhanced Product Sync Manager (Priority: High)

#### 3.1 Update Product Sync Manager
**File:** `python_base_04/core/modules/in_app_purchases_module/sync/product_sync_manager.py`

Replace the `_simulate_google_play_sync()` method with real API calls:

```python
def sync_google_play_products(self) -> Dict[str, Any]:
    """Sync products from Google Play Console using real API."""
    sync_start = time.time()
    sync_id = None
    
    try:
        custom_log("🤖 Starting Google Play product sync", level="INFO")
        
        # Create sync history record
        sync_id = self._create_sync_history("google_play", "full")
        
        # Initialize Google Play API client
        from .google_play_api_client import GooglePlayAPIClient
        api_client = GooglePlayAPIClient(self.app_manager)
        
        if not api_client.initialize():
            raise Exception("Failed to initialize Google Play API client")
        
        # Get products from Google Play
        in_app_products = api_client.get_in_app_products()
        subscriptions = api_client.get_subscriptions()
        
        # Combine all products
        google_play_products = in_app_products + subscriptions
        
        # Process and store products
        sync_result = self._process_products("google_play", google_play_products)
        
        # Update sync history
        sync_duration = int((time.time() - sync_start) * 1000)
        self._update_sync_history(sync_id, sync_result, sync_duration)
        
        custom_log(f"✅ Google Play sync completed: {sync_result['products_synced']} products", level="INFO")
        return sync_result
        
    except Exception as e:
        error_msg = f"Google Play sync failed: {e}"
        custom_log(f"❌ {error_msg}", level="ERROR")
        
        if sync_id:
            self._update_sync_history(sync_id, {"error": error_msg}, 0)
        
        return {"error": error_msg}
```

### Phase 4: Enhanced Google Play Verifier (Priority: High)

#### 4.1 Update Google Play Verifier
**File:** `python_base_04/core/modules/in_app_purchases_module/verifiers/google_play_verifier.py`

Replace the `_call_google_play_api()` method with real API calls:

```python
def _call_google_play_api(self, purchase_token: str, product_id: str) -> Dict[str, Any]:
    """Call the actual Google Play Developer API."""
    try:
        # Initialize Google Play API client
        from ..sync.google_play_api_client import GooglePlayAPIClient
        api_client = GooglePlayAPIClient(self.app_manager)
        
        if not api_client.initialize():
            raise Exception("Failed to initialize Google Play API client")
        
        # Verify purchase using real API
        verification_result = api_client.verify_purchase(purchase_token, product_id)
        
        return verification_result
        
    except Exception as e:
        custom_log(f"❌ Google Play API call failed: {e}", level="ERROR")
        return {
            "valid": False,
            "error": f"Google Play API error: {str(e)}",
            "platform": "google_play"
        }
```

### Phase 5: Configuration and Security (Priority: Medium)

#### 5.1 Add Google Play Secrets to Vault
**File:** `python_base_04/secrets/google_play_service_account.json`
```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "your-private-key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "your-service-account@your-project.iam.gserviceaccount.com",
  "client_id": "your-client-id",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/your-service-account%40your-project.iam.gserviceaccount.com"
}
```

#### 5.2 Add Vault Configuration
**File:** `python_base_04/core/managers/vault_manager.py`

Add method to get Google Play secrets:

```python
def get_google_play_secrets(self) -> Dict[str, Any]:
    """Get Google Play API secrets from Vault."""
    try:
        return self.get_secret("flask-app/google-play")
    except Exception as e:
        custom_log(f"Failed to get Google Play secrets from Vault: {e}", level="ERROR")
        return {}
```

### Phase 6: Testing and Validation (Priority: Medium)

#### 6.1 Create Test Suite
**File:** `python_base_04/tests/test_google_play_integration.py`
```python
"""
Test suite for Google Play API integration.
"""

import unittest
from unittest.mock import Mock, patch
from core.modules.in_app_purchases_module.sync.google_play_api_client import GooglePlayAPIClient

class TestGooglePlayAPIIntegration(unittest.TestCase):
    """Test Google Play API integration."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.mock_app_manager = Mock()
        self.api_client = GooglePlayAPIClient(self.mock_app_manager)
    
    @patch('google.oauth2.service_account.Credentials.from_service_account_file')
    @patch('googleapiclient.discovery.build')
    def test_api_client_initialization(self, mock_build, mock_credentials):
        """Test Google Play API client initialization."""
        # Test implementation
        pass
    
    @patch('googleapiclient.discovery.build')
    def test_get_in_app_products(self, mock_build):
        """Test getting in-app products from Google Play."""
        # Test implementation
        pass
    
    @patch('googleapiclient.discovery.build')
    def test_verify_purchase(self, mock_build):
        """Test purchase verification."""
        # Test implementation
        pass

if __name__ == '__main__':
    unittest.main()
```

### Phase 7: Documentation and Monitoring (Priority: Low)

#### 7.1 Update Module Documentation
**File:** `Documentation/python_base_04/IN_APP_PURCHASES_MODULE.md`
```markdown
# In-App Purchases Module

## Google Play Integration

### Setup
1. Create Google Play Developer account
2. Create service account with Android Publisher API access
3. Download service account JSON key
4. Configure package name in environment variables
5. Add service account file to Vault or secrets directory

### API Quotas
- Google Play Developer API has rate limits
- Monitor usage in Google Cloud Console
- Implement exponential backoff for retries

### Testing
- Use test accounts for development
- Test with sandbox purchases
- Validate with real purchases in production
```

#### 7.2 Add Monitoring
**File:** `python_base_04/core/modules/in_app_purchases_module/monitoring/google_play_metrics.py`
```python
"""
Google Play API metrics and monitoring.
"""

from prometheus_client import Counter, Histogram, Gauge
from tools.logger.custom_logging import custom_log

# Metrics
google_play_api_calls = Counter('google_play_api_calls_total', 'Total Google Play API calls', ['endpoint', 'status'])
google_play_api_duration = Histogram('google_play_api_duration_seconds', 'Google Play API call duration', ['endpoint'])
google_play_products_synced = Gauge('google_play_products_synced', 'Number of products synced from Google Play')
google_play_purchases_verified = Counter('google_play_purchases_verified_total', 'Total purchases verified', ['status'])

def track_api_call(endpoint: str, duration: float, success: bool):
    """Track Google Play API call metrics."""
    status = 'success' if success else 'error'
    google_play_api_calls.labels(endpoint=endpoint, status=status).inc()
    google_play_api_duration.labels(endpoint=endpoint).observe(duration)
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Add Google API dependencies
- [ ] Create Google Play API client
- [ ] Add configuration management
- [ ] Set up service account authentication

### Week 2: Core Integration
- [ ] Implement real product sync
- [ ] Update purchase verification
- [ ] Add error handling and retries
- [ ] Create test suite

### Week 3: Security and Monitoring
- [ ] Add Vault integration for secrets
- [ ] Implement API quota management
- [ ] Add monitoring and metrics
- [ ] Update documentation

### Week 4: Testing and Deployment
- [ ] Comprehensive testing
- [ ] Performance optimization
- [ ] Production deployment
- [ ] Monitoring setup

## Risk Assessment

### High Risk
- **Google API Quotas**: Risk of hitting rate limits
- **Service Account Security**: Risk of credential exposure
- **API Changes**: Google may change API endpoints

### Medium Risk
- **Network Issues**: API calls may fail due to network problems
- **Data Consistency**: Sync may fail, leaving stale data

### Low Risk
- **Performance**: API calls may be slow
- **Dependencies**: Google API client library updates

## Mitigation Strategies

### For High Risk Items
1. **API Quotas**: Implement exponential backoff and circuit breaker
2. **Security**: Use Vault for credential management
3. **API Changes**: Monitor Google API changelog and implement versioning

### For Medium Risk Items
1. **Network Issues**: Implement retry logic with exponential backoff
2. **Data Consistency**: Add sync status tracking and manual sync triggers

### For Low Risk Items
1. **Performance**: Implement caching for frequently accessed data
2. **Dependencies**: Pin dependency versions and monitor updates

## Success Criteria

### Functional Requirements
- [ ] Successfully sync products from Google Play Console
- [ ] Verify purchases using Google Play Developer API
- [ ] Handle API errors gracefully
- [ ] Maintain data consistency

### Performance Requirements
- [ ] Sync completes within 5 minutes
- [ ] Purchase verification completes within 10 seconds
- [ ] API quota usage stays under 80%

### Security Requirements
- [ ] Service account credentials stored securely
- [ ] API calls authenticated properly
- [ ] No sensitive data logged

## Rollback Plan

If issues arise during implementation:

1. **Immediate Rollback**: Disable Google Play integration and use simulated data
2. **Gradual Rollback**: Reduce sync frequency and add more monitoring
3. **Partial Rollback**: Keep product sync but disable purchase verification

## Post-Implementation

### Monitoring
- Monitor API quota usage
- Track sync success rates
- Monitor purchase verification success rates
- Alert on API errors

### Maintenance
- Regular dependency updates
- Monitor Google API changes
- Review and update service account permissions
- Update documentation as needed

## Conclusion

This implementation plan provides a comprehensive approach to integrating Google Play Developer API into the existing in_app_purchases_module. The phased approach ensures minimal disruption to existing functionality while adding robust Google Play integration capabilities.

The implementation will enable:
- Real-time product synchronization from Google Play Console
- Secure purchase verification using Google's official API
- Comprehensive monitoring and error handling
- Scalable architecture for future enhancements

By following this plan, we can successfully integrate Google Play Developer API while maintaining the existing module's functionality and security standards. 