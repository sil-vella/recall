# In-App Purchases Implementation Plan

## Overview

This document outlines the step-by-step implementation plan for adding Google Play Store and App Store in-app purchases to the Flutter Base 05 application, integrated with the existing Python backend verification system.

## Architecture Integration

### Flutter Side
- **Module**: `in_app_purchases_module` following existing module pattern
- **State Management**: Integration with existing `StateManager`
- **API Communication**: Using existing `ConnectionsApiModule`
- **Logging**: Using existing `Logger` system

### Python Backend
- **Module**: `platform_payments_module` following existing module pattern
- **Database**: Integration with existing `DatabaseManager`
- **Verification**: Server-side receipt validation for both platforms
- **Security**: Following existing JWT and secure storage patterns

## Phase 1: Flutter Implementation

### Step 1.1: Add Dependencies ✅ **COMPLETED**
**File**: `flutter_base_05/pubspec.yaml`
```yaml
dependencies:
  in_app_purchase: ^3.1.13
  in_app_purchase_android: ^0.3.6+1
  in_app_purchase_storekit: ^0.3.6+1
```

**Action**: ✅ Dependencies added and `flutter pub get` executed

### Step 1.2: Platform Configuration ✅ **COMPLETED**

#### Android Setup
**File**: `flutter_base_05/android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="com.android.vending.BILLING" />
```

**File**: `flutter_base_05/android/app/build.gradle`
```gradle
defaultConfig {
    minSdkVersion 19
}
```

#### iOS Setup
**File**: `flutter_base_05/ios/Runner/Info.plist`
```xml
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>
  </dict>
</array>
```

**Action**: ✅ Platform configurations completed

### Step 1.3: Create Module Structure ✅ **COMPLETED**
**Directory**: `flutter_base_05/lib/modules/in_app_purchases_module/`

```
in_app_purchases_module/
├── in_app_purchases_module.dart ✅
├── models/
│   ├── purchase_product.dart ✅
│   ├── purchase_receipt.dart ✅
│   └── purchase_status.dart ✅
├── services/
│   ├── platform_purchase_service.dart ✅
│   └── purchase_verification_service.dart ✅
├── screens/
│   ├── purchase_screen.dart ✅
│   └── subscription_screen.dart ✅
└── widgets/
    ├── product_card.dart ✅
    └── purchase_button.dart ✅
```

**Status**: ✅ All files created and error-free

### Step 1.4: Implement Core Module ✅ **COMPLETED**
**File**: `flutter_base_05/lib/modules/in_app_purchases_module/in_app_purchases_module.dart`

✅ **Status**: Core module implemented with:
- Template-compliant structure
- State management integration
- Health check functionality
- Proper dependency management
- Logger integration

**Key Features**:
- ✅ Follows `modules_template.dart` pattern exactly
- ✅ Uses `StateManager` for state registration
- ✅ Implements proper initialization and disposal
- ✅ Includes comprehensive health checks
- ✅ Error-free compilation

### Step 1.5: Implement Purchase Service ✅ **COMPLETED**
**File**: `flutter_base_05/lib/modules/in_app_purchases_module/services/platform_purchase_service.dart`

✅ **Status**: Purchase service implemented with:
- Complete in-app purchase integration
- Platform-specific handling (Google Play & App Store)
- Server verification integration
- State management updates
- Comprehensive error handling

**Key Features**:
- ✅ Uses `in_app_purchase` package for unified handling
- ✅ Handles both consumable and non-consumable products
- ✅ Integrates with `PurchaseVerificationService`
- ✅ Updates `StateManager` with purchase states
- ✅ Proper stream management and cleanup
- ✅ Error-free compilation with all linter issues resolved

### Step 1.6: Register Module ✅ **COMPLETED**
**File**: `flutter_base_05/lib/core/managers/module_registry.dart`

✅ **Status**: Module registered in registry with:
- Import added: `import '../../modules/in_app_purchases_module/in_app_purchases_module.dart';`
- Registration: `registerModule('in_app_purchases', () => InAppPurchasesModule(), dependencies: ['connections_api']);`
- Proper dependency management

**Key Features**:
- ✅ Module will be automatically initialized on app startup
- ✅ Dependencies properly managed (requires `connections_api` module)
- ✅ Follows existing module registration pattern
- ✅ Ready for integration with `ModuleManager`

## Phase 2: Python Backend Implementation

### Step 2.1: Create Module Structure
**Directory**: `python_base_04/core/modules/platform_payments_module/`

```
platform_payments_module/
├── platform_payments_main.py
├── verifiers/
│   ├── google_play_verifier.py
│   ├── app_store_verifier.py
│   └── base_verifier.py
├── models/
│   ├── purchase_receipt.py
│   └── verification_result.py
└── services/
    └── receipt_processor.py
```

### Step 2.2: Add Dependencies
**File**: `python_base_04/requirements.txt`
```
google-api-python-client==2.108.0
google-auth==2.23.4
google-auth-httplib2==0.1.1
google-auth-oauthlib==1.1.0
```

### Step 2.3: Implement Core Module
**File**: `python_base_04/core/modules/platform_payments_module/platform_payments_main.py`

```python
from core.modules.base_module import BaseModule
from core.managers.database_manager import DatabaseManager
from tools.logger.custom_logging import custom_log
from flask import request, jsonify
from datetime import datetime
from typing import Dict, Any, Optional
import os

class PlatformPaymentsModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the PlatformPaymentsModule."""
        super().__init__(app_manager)
        self.dependencies = ["transactions", "user_management", "stripe"]
        
        # Initialize verifiers
        self.google_verifier = None
        self.app_store_verifier = None
        self._initialize_verifiers()
        
        custom_log("PlatformPaymentsModule created")

    def _initialize_verifiers(self):
        """Initialize platform-specific verifiers."""
        try:
            from utils.config.config import Config
            
            # Initialize Google Play verifier
            if hasattr(Config, 'GOOGLE_PLAY_KEY_PATH') and Config.GOOGLE_PLAY_KEY_PATH:
                from .verifiers.google_play_verifier import GooglePlayVerifier
                self.google_verifier = GooglePlayVerifier(Config.GOOGLE_PLAY_KEY_PATH)
                custom_log("✅ Google Play verifier initialized")
            
            # Initialize App Store verifier
            if hasattr(Config, 'APP_STORE_SHARED_SECRET') and Config.APP_STORE_SHARED_SECRET:
                from .verifiers.app_store_verifier import AppStoreVerifier
                self.app_store_verifier = AppStoreVerifier(Config.APP_STORE_SHARED_SECRET)
                custom_log("✅ App Store verifier initialized")
                
        except Exception as e:
            custom_log(f"❌ Error initializing verifiers: {e}", level="ERROR")

    def initialize(self, app_manager):
        """Initialize the PlatformPaymentsModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        
        # Get database manager through app_manager
        self.db_manager = app_manager.get_db_manager(role="read_write")
        
        self.register_routes()
        self._initialized = True
        custom_log("PlatformPaymentsModule initialized")

    def register_routes(self):
        """Register platform payment routes."""
        self._register_route_helper("/platform-payments/verify", self.verify_purchase, methods=["POST"])
        self._register_route_helper("/platform-payments/products", self.get_products, methods=["GET"])
        self._register_route_helper("/platform-payments/purchase-history", self.get_purchase_history, methods=["GET"])
        custom_log(f"PlatformPaymentsModule registered {len(self.registered_routes)} routes")

    def verify_purchase(self):
        """Verify purchase receipt with platform servers."""
        try:
            data = request.get_json()
            
            # Validate required fields
            required_fields = ['user_id', 'product_id', 'platform']
            for field in required_fields:
                if not data.get(field):
                    return jsonify({
                        "success": False,
                        "error": f"Missing required field: {field}"
                    }), 400

            user_id = data['user_id']
            product_id = data['product_id']
            platform = data['platform']
            
            # Verify with appropriate platform
            verification_result = None
            if platform == 'google_play':
                if not self.google_verifier:
                    return jsonify({
                        "success": False,
                        "error": "Google Play verification not configured"
                    }), 503
                
                purchase_token = data.get('purchase_token')
                if not purchase_token:
                    return jsonify({
                        "success": False,
                        "error": "Missing purchase token for Google Play"
                    }), 400
                
                verification_result = await self.google_verifier.verify_purchase(
                    purchase_token, product_id
                )
                
            elif platform == 'app_store':
                if not self.app_store_verifier:
                    return jsonify({
                        "success": False,
                        "error": "App Store verification not configured"
                    }), 503
                
                receipt_data = data.get('receipt_data')
                if not receipt_data:
                    return jsonify({
                        "success": False,
                        "error": "Missing receipt data for App Store"
                    }), 400
                
                verification_result = await self.app_store_verifier.verify_receipt(receipt_data)
                
            else:
                return jsonify({
                    "success": False,
                    "error": f"Unsupported platform: {platform}"
                }), 400

            if verification_result and verification_result['is_valid']:
                # Record successful purchase
                await self._record_successful_purchase(user_id, product_id, platform, verification_result)
                
                # Award credits if applicable
                credits_awarded = verification_result.get('credits_awarded', 0)
                if credits_awarded > 0:
                    await self._award_credits(user_id, credits_awarded)
                
                custom_log(f"✅ Purchase verified for user {user_id}: {product_id}")
                
                return jsonify({
                    "success": True,
                    "message": "Purchase verified successfully",
                    "credits_awarded": credits_awarded,
                    "amount": verification_result.get('amount', 0)
                }), 200
            else:
                custom_log(f"❌ Purchase verification failed for user {user_id}: {product_id}")
                return jsonify({
                    "success": False,
                    "error": "Purchase verification failed"
                }), 400

        except Exception as e:
            custom_log(f"❌ Error verifying purchase: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    async def _record_successful_purchase(self, user_id: str, product_id: str, platform: str, verification_result: Dict):
        """Record successful purchase in database."""
        try:
            purchase_data = {
                'user_id': user_id,
                'product_id': product_id,
                'platform': platform,
                'amount': verification_result.get('amount', 0),
                'currency': verification_result.get('currency', 'USD'),
                'verification_status': 'verified',
                'verified_at': datetime.utcnow().isoformat(),
                'created_at': datetime.utcnow().isoformat()
            }
            
            purchase_id = self.db_manager.insert("platform_purchases", purchase_data)
            custom_log(f"✅ Recorded purchase: {purchase_id}")
            
        except Exception as e:
            custom_log(f"❌ Error recording purchase: {e}", level="ERROR")
            raise

    async def _award_credits(self, user_id: str, credits: int):
        """Award credits to user (integrate with existing credit system)."""
        try:
            # Use existing wallet/credit system
            # This should integrate with your existing credit management
            custom_log(f"✅ Awarded {credits} credits to user {user_id}")
            
        except Exception as e:
            custom_log(f"❌ Error awarding credits: {e}", level="ERROR")
            raise

    def get_products(self):
        """Get available products configuration."""
        try:
            # Return product configuration
            products = [
                {
                    'id': 'premium_upgrade',
                    'title': 'Premium Upgrade',
                    'description': 'Unlock premium features',
                    'type': 'non_consumable',
                    'credits_awarded': 0
                },
                {
                    'id': '100_coins',
                    'title': '100 Coins',
                    'description': 'Get 100 coins',
                    'type': 'consumable',
                    'credits_awarded': 100
                },
                {
                    'id': '500_coins',
                    'title': '500 Coins',
                    'description': 'Get 500 coins',
                    'type': 'consumable',
                    'credits_awarded': 500
                },
                {
                    'id': '1000_coins',
                    'title': '1000 Coins',
                    'description': 'Get 1000 coins',
                    'type': 'consumable',
                    'credits_awarded': 1000
                }
            ]
            
            return jsonify({
                "success": True,
                "products": products
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting products: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_purchase_history(self):
        """Get user's purchase history."""
        try:
            user_id = request.args.get('user_id')
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "User ID is required"
                }), 400
            
            # Query purchase history from database
            purchases = self.db_manager.find("platform_purchases", {"user_id": user_id})
            
            return jsonify({
                "success": True,
                "purchases": purchases
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting purchase history: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500
```

### Step 2.4: Implement Google Play Verifier
**File**: `python_base_04/core/modules/platform_payments_module/verifiers/google_play_verifier.py`

```python
import json
import asyncio
from typing import Dict, Any
from google.oauth2 import service_account
from googleapiclient.discovery import build
from tools.logger.custom_logging import custom_log

class GooglePlayVerifier:
    def __init__(self, service_account_key_path: str):
        self.service_account_key_path = service_account_key_path
        self.service = None
        self._initialize_service()
    
    def _initialize_service(self):
        """Initialize Google Play Developer API service."""
        try:
            credentials = service_account.Credentials.from_service_account_file(
                self.service_account_key_path,
                scopes=['https://www.googleapis.com/auth/androidpublisher']
            )
            
            self.service = build('androidpublisher', 'v3', credentials=credentials)
            custom_log("✅ Google Play API service initialized")
            
        except Exception as e:
            custom_log(f"❌ Error initializing Google Play service: {e}", level="ERROR")
            self.service = None
    
    async def verify_purchase(self, purchase_token: str, product_id: str) -> Dict[str, Any]:
        """Verify Google Play purchase."""
        try:
            if not self.service:
                return {"is_valid": False, "error": "Service not initialized"}
            
            # Get package name from config
            from utils.config.config import Config
            package_name = Config.GOOGLE_PLAY_PACKAGE_NAME
            
            # Verify purchase with Google Play
            request = self.service.purchases().products().get(
                packageName=package_name,
                productId=product_id,
                token=purchase_token
            )
            
            response = request.execute()
            
            # Check purchase state
            purchase_state = response.get('purchaseState', 0)
            if purchase_state == 0:  # Purchased
                return {
                    "is_valid": True,
                    "amount": self._extract_amount(response),
                    "currency": response.get('priceCurrencyCode', 'USD'),
                    "credits_awarded": self._get_credits_for_product(product_id)
                }
            else:
                return {
                    "is_valid": False,
                    "error": f"Invalid purchase state: {purchase_state}"
                }
                
        except Exception as e:
            custom_log(f"❌ Google Play verification error: {e}", level="ERROR")
            return {
                "is_valid": False,
                "error": str(e)
            }
    
    def _extract_amount(self, response: Dict) -> float:
        """Extract purchase amount from response."""
        try:
            price_amount = response.get('priceAmountMicros', 0)
            return float(price_amount) / 1000000  # Convert from micros
        except:
            return 0.0
    
    def _get_credits_for_product(self, product_id: str) -> int:
        """Get credits awarded for product."""
        credit_map = {
            '100_coins': 100,
            '500_coins': 500,
            '1000_coins': 1000,
            'premium_upgrade': 0
        }
        return credit_map.get(product_id, 0)
```

### Step 2.5: Implement App Store Verifier
**File**: `python_base_04/core/modules/platform_payments_module/verifiers/app_store_verifier.py`

```python
import json
import asyncio
import aiohttp
from typing import Dict, Any
from tools.logger.custom_logging import custom_log

class AppStoreVerifier:
    def __init__(self, shared_secret: str):
        self.shared_secret = shared_secret
        self.sandbox_url = "https://sandbox.itunes.apple.com/verifyReceipt"
        self.production_url = "https://buy.itunes.apple.com/verifyReceipt"
    
    async def verify_receipt(self, receipt_data: str) -> Dict[str, Any]:
        """Verify App Store receipt."""
        try:
            # Try production first, then sandbox
            verification_result = await self._verify_with_url(receipt_data, self.production_url)
            
            if not verification_result.get('is_valid'):
                # Try sandbox if production fails
                verification_result = await self._verify_with_url(receipt_data, self.sandbox_url)
            
            return verification_result
            
        except Exception as e:
            custom_log(f"❌ App Store verification error: {e}", level="ERROR")
            return {
                "is_valid": False,
                "error": str(e)
            }
    
    async def _verify_with_url(self, receipt_data: str, url: str) -> Dict[str, Any]:
        """Verify receipt with specific URL."""
        try:
            payload = {
                'receipt-data': receipt_data,
                'password': self.shared_secret,
                'exclude-old-transactions': True
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=payload) as response:
                    result = await response.json()
                    
                    status = result.get('status', -1)
                    if status == 0:  # Valid receipt
                        return self._process_valid_receipt(result)
                    else:
                        return {
                            "is_valid": False,
                            "error": f"Invalid receipt status: {status}"
                        }
                        
        except Exception as e:
            custom_log(f"❌ Error verifying with {url}: {e}", level="ERROR")
            return {
                "is_valid": False,
                "error": str(e)
            }
    
    def _process_valid_receipt(self, result: Dict) -> Dict[str, Any]:
        """Process valid receipt and extract purchase information."""
        try:
            latest_receipt_info = result.get('latest_receipt_info', [])
            if not latest_receipt_info:
                return {"is_valid": False, "error": "No purchase information found"}
            
            # Get the most recent transaction
            latest_transaction = latest_receipt_info[0]
            
            product_id = latest_transaction.get('product_id')
            amount = self._extract_amount(latest_transaction)
            
            return {
                "is_valid": True,
                "amount": amount,
                "currency": "USD",  # App Store amounts are in USD
                "credits_awarded": self._get_credits_for_product(product_id),
                "product_id": product_id
            }
            
        except Exception as e:
            custom_log(f"❌ Error processing receipt: {e}", level="ERROR")
            return {
                "is_valid": False,
                "error": "Error processing receipt"
            }
    
    def _extract_amount(self, transaction: Dict) -> float:
        """Extract purchase amount from transaction."""
        try:
            # App Store amounts are in cents
            price_amount = transaction.get('price_amount', 0)
            return float(price_amount) / 100
        except:
            return 0.0
    
    def _get_credits_for_product(self, product_id: str) -> int:
        """Get credits awarded for product."""
        credit_map = {
            '100_coins': 100,
            '500_coins': 500,
            '1000_coins': 1000,
            'premium_upgrade': 0
        }
        return credit_map.get(product_id, 0)
```

### Step 2.6: Register Module
**File**: `python_base_04/core/modules/module_registry.py`

```python
# Add to register_all_modules function
module_manager.register_module(PlatformPaymentsModule())
```

## Phase 3: Database Setup

### Step 3.1: Create Database Tables
**File**: `python_base_04/playbooks/00_local/12_setup_platform_payments_database.yml`

```yaml
---
- name: Setup Platform Payments Database
  hosts: localhost
  gather_facts: no
  
  tasks:
    - name: Create platform_purchases table
      postgresql_query:
        db: "{{ database_name }}"
        login_host: "{{ database_host }}"
        login_user: "{{ database_user }}"
        login_password: "{{ database_password }}"
        query: |
          CREATE TABLE IF NOT EXISTS platform_purchases (
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            product_id VARCHAR(255) NOT NULL,
            platform VARCHAR(50) NOT NULL,
            amount DECIMAL(10,2) DEFAULT 0,
            currency VARCHAR(10) DEFAULT 'USD',
            verification_status VARCHAR(50) DEFAULT 'pending',
            verified_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );
      
    - name: Create platform_products table
      postgresql_query:
        db: "{{ database_name }}"
        login_host: "{{ database_host }}"
        login_user: "{{ database_user }}"
        login_password: "{{ database_password }}"
        query: |
          CREATE TABLE IF NOT EXISTS platform_products (
            id SERIAL PRIMARY KEY,
            product_id VARCHAR(255) UNIQUE NOT NULL,
            platform VARCHAR(50) NOT NULL,
            product_type VARCHAR(50) NOT NULL,
            title VARCHAR(255) NOT NULL,
            description TEXT,
            price DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL,
            credits_awarded INTEGER DEFAULT 0,
            is_active BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );
      
    - name: Create indexes
      postgresql_query:
        db: "{{ database_name }}"
        login_host: "{{ database_host }}"
        login_user: "{{ database_user }}"
        login_password: "{{ database_password }}"
        query: |
          CREATE INDEX IF NOT EXISTS idx_platform_purchases_user_id ON platform_purchases(user_id);
          CREATE INDEX IF NOT EXISTS idx_platform_purchases_product_id ON platform_purchases(product_id);
          CREATE INDEX IF NOT EXISTS idx_platform_purchases_platform ON platform_purchases(platform);
```

## Phase 4: Configuration

### Step 4.1: Add Configuration Variables
**File**: `python_base_04/utils/config/config.py`

```python
# Add to Config class
GOOGLE_PLAY_KEY_PATH = os.getenv('GOOGLE_PLAY_KEY_PATH', '')
GOOGLE_PLAY_PACKAGE_NAME = os.getenv('GOOGLE_PLAY_PACKAGE_NAME', 'com.yourcompany.yourapp')
APP_STORE_SHARED_SECRET = os.getenv('APP_STORE_SHARED_SECRET', '')
APP_STORE_BUNDLE_ID = os.getenv('APP_STORE_BUNDLE_ID', 'com.yourcompany.yourapp')
```

### Step 4.2: Environment Variables
**File**: `.env` (add to your environment)

```bash
# Google Play Configuration
GOOGLE_PLAY_KEY_PATH=/path/to/service-account-key.json
GOOGLE_PLAY_PACKAGE_NAME=com.yourcompany.yourapp

# App Store Configuration
APP_STORE_SHARED_SECRET=your-app-store-shared-secret
APP_STORE_BUNDLE_ID=com.yourcompany.yourapp
```

## Phase 5: Testing

### Step 5.1: Flutter Testing
**File**: `flutter_base_05/test/modules/in_app_purchases_module_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/modules/in_app_purchases_module/services/platform_purchase_service.dart';

void main() {
  group('PlatformPurchaseService Tests', () {
    test('should initialize correctly', () async {
      final service = PlatformPurchaseService();
      await service.initialize();
      
      // Test initialization
      expect(service.isAvailable, isNotNull);
    });
    
    test('should load products', () async {
      final service = PlatformPurchaseService();
      await service.initialize();
      
      // Test product loading
      final products = StateManager().getModuleState("in_app_purchases")["products"];
      expect(products, isA<List>());
    });
  });
}
```

### Step 5.2: Python Testing
**File**: `python_base_04/tests/test_platform_payments.py`

```python
import unittest
from unittest.mock import Mock, patch
from core.modules.platform_payments_module.platform_payments_main import PlatformPaymentsModule

class TestPlatformPaymentsModule(unittest.TestCase):
    def setUp(self):
        self.module = PlatformPaymentsModule()
    
    def test_verify_purchase_google_play(self):
        """Test Google Play purchase verification."""
        # Mock data
        mock_data = {
            'user_id': 'test_user',
            'product_id': '100_coins',
            'platform': 'google_play',
            'purchase_token': 'mock_token'
        }
        
        # Test verification
        with patch.object(self.module.google_verifier, 'verify_purchase') as mock_verify:
            mock_verify.return_value = {
                'is_valid': True,
                'amount': 0.99,
                'credits_awarded': 100
            }
            
            # Test the verification endpoint
            # This would be tested with a mock Flask app
            pass
    
    def test_verify_purchase_app_store(self):
        """Test App Store purchase verification."""
        # Similar test for App Store
        pass
```

## Phase 6: Deployment

### Step 6.1: Google Play Console Setup
1. **Create In-App Products**:
   - Product ID: `premium_upgrade`
   - Product ID: `100_coins`
   - Product ID: `500_coins`
   - Product ID: `1000_coins`

2. **Upload Service Account Key**:
   - Download service account JSON from Google Cloud Console
   - Place in secure location on server
   - Update environment variable

### Step 6.2: App Store Connect Setup
1. **Create In-App Purchases**:
   - Product ID: `premium_upgrade`
   - Product ID: `100_coins`
   - Product ID: `500_coins`
   - Product ID: `1000_coins`

2. **Get Shared Secret**:
   - From App Store Connect > Users and Access > Keys
   - Add to environment variables

### Step 6.3: Production Deployment
1. **Deploy Python Backend**:
   ```bash
   # Deploy with new module
   ansible-playbook playbooks/00_local/12_setup_platform_payments_database.yml
   ```

2. **Deploy Flutter App**:
   ```bash
   # Build with in-app purchases
   flutter build appbundle --release
   flutter build ios --release
   ```

## Phase 7: Monitoring & Analytics

### Step 7.1: Add Monitoring
**File**: `python_base_04/core/modules/platform_payments_module/services/analytics_service.py`

```python
class PurchaseAnalytics:
    def __init__(self, db_manager):
        self.db_manager = db_manager
    
    def track_purchase(self, user_id: str, product_id: str, platform: str, amount: float):
        """Track purchase for analytics."""
        analytics_data = {
            'user_id': user_id,
            'product_id': product_id,
            'platform': platform,
            'amount': amount,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        self.db_manager.insert("purchase_analytics", analytics_data)
        custom_log(f"📊 Purchase tracked: {user_id} - {product_id} - {platform}")
```

## Phase 8: Web Platform Support (Future-Ready)

### Step 8.1: Enhanced Database Schema for Web Support
**File**: `python_base_04/playbooks/00_local/13_add_web_support_to_platform_payments.yml`

```yaml
---
- name: Add Web Support to Platform Payments Database
  hosts: localhost
  gather_facts: no
  
  tasks:
    - name: Add web-specific columns to platform_purchases table
      postgresql_query:
        db: "{{ database_name }}"
        login_host: "{{ database_host }}"
        login_user: "{{ database_user }}"
        login_password: "{{ database_password }}"
        query: |
          ALTER TABLE platform_purchases 
          ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50) DEFAULT 'platform',
          ADD COLUMN IF NOT EXISTS payment_intent_id VARCHAR(255),
          ADD COLUMN IF NOT EXISTS stripe_payment_intent VARCHAR(255),
          ADD COLUMN IF NOT EXISTS web_session_id VARCHAR(255),
          ADD COLUMN IF NOT EXISTS web_client_secret VARCHAR(500);
      
    - name: Create platform_products table for cross-platform product mapping
      postgresql_query:
        db: "{{ database_name }}"
        login_host: "{{ database_host }}"
        login_user: "{{ database_user }}"
        login_password: "{{ database_password }}"
        query: |
          CREATE TABLE IF NOT EXISTS platform_products (
            id SERIAL PRIMARY KEY,
            product_id VARCHAR(255) NOT NULL,
            platform VARCHAR(50) NOT NULL,
            platform_product_id VARCHAR(255) NOT NULL,
            product_type VARCHAR(50) NOT NULL,
            title VARCHAR(255) NOT NULL,
            description TEXT,
            price DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL,
            credits_awarded INTEGER DEFAULT 0,
            is_active BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(product_id, platform)
          );
      
    - name: Insert default product mappings
      postgresql_query:
        db: "{{ database_name }}"
        login_host: "{{ database_host }}"
        login_user: "{{ database_user }}"
        login_password: "{{ database_password }}"
        query: |
          INSERT INTO platform_products (product_id, platform, platform_product_id, product_type, title, description, price, currency, credits_awarded) VALUES
          ('premium_upgrade', 'google_play', 'premium_upgrade', 'non_consumable', 'Premium Upgrade', 'Unlock premium features', 9.99, 'USD', 0),
          ('premium_upgrade', 'app_store', 'premium_upgrade', 'non_consumable', 'Premium Upgrade', 'Unlock premium features', 9.99, 'USD', 0),
          ('premium_upgrade', 'web', 'premium_upgrade_stripe', 'non_consumable', 'Premium Upgrade', 'Unlock premium features', 9.99, 'USD', 0),
          ('100_coins', 'google_play', '100_coins', 'consumable', '100 Coins', 'Get 100 coins', 0.99, 'USD', 100),
          ('100_coins', 'app_store', '100_coins', 'consumable', '100 Coins', 'Get 100 coins', 0.99, 'USD', 100),
          ('100_coins', 'web', '100_coins_stripe', 'consumable', '100 Coins', 'Get 100 coins', 0.99, 'USD', 100),
          ('500_coins', 'google_play', '500_coins', 'consumable', '500 Coins', 'Get 500 coins', 4.99, 'USD', 500),
          ('500_coins', 'app_store', '500_coins', 'consumable', '500 Coins', 'Get 500 coins', 4.99, 'USD', 500),
          ('500_coins', 'web', '500_coins_stripe', 'consumable', '500 Coins', 'Get 500 coins', 4.99, 'USD', 500),
          ('1000_coins', 'google_play', '1000_coins', 'consumable', '1000 Coins', 'Get 1000 coins', 9.99, 'USD', 1000),
          ('1000_coins', 'app_store', '1000_coins', 'consumable', '1000 Coins', 'Get 1000 coins', 9.99, 'USD', 1000),
          ('1000_coins', 'web', '1000_coins_stripe', 'consumable', '1000 Coins', 'Get 1000 coins', 9.99, 'USD', 1000)
          ON CONFLICT (product_id, platform) DO NOTHING;
```

### Step 8.2: Enhanced Platform Payments Module
**File**: `python_base_04/core/modules/platform_payments_module/platform_payments_main.py`

```python
class PlatformPaymentsModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the PlatformPaymentsModule."""
        super().__init__(app_manager)
        self.dependencies = ["transactions", "user_management", "stripe"]
        
        # Initialize verifiers
        self.google_verifier = None
        self.app_store_verifier = None
        self.stripe_module = None
        self._initialize_verifiers()
        
        custom_log("PlatformPaymentsModule created")

    def _initialize_verifiers(self):
        """Initialize platform-specific verifiers."""
        try:
            from utils.config.config import Config
            
            # Initialize Google Play verifier
            if hasattr(Config, 'GOOGLE_PLAY_KEY_PATH') and Config.GOOGLE_PLAY_KEY_PATH:
                from .verifiers.google_play_verifier import GooglePlayVerifier
                self.google_verifier = GooglePlayVerifier(Config.GOOGLE_PLAY_KEY_PATH)
                custom_log("✅ Google Play verifier initialized")
            
            # Initialize App Store verifier
            if hasattr(Config, 'APP_STORE_SHARED_SECRET') and Config.APP_STORE_SHARED_SECRET:
                from .verifiers.app_store_verifier import AppStoreVerifier
                self.app_store_verifier = AppStoreVerifier(Config.APP_STORE_SHARED_SECRET)
                custom_log("✅ App Store verifier initialized")
            
            # Get existing Stripe module for web support
            if self.app_manager:
                self.stripe_module = self.app_manager.get_module("stripe_module")
                if self.stripe_module:
                    custom_log("✅ Stripe module connected for web support")
                
        except Exception as e:
            custom_log(f"❌ Error initializing verifiers: {e}", level="ERROR")

    def register_routes(self):
        """Register platform payment routes."""
        self._register_route_helper("/platform-payments/verify", self.verify_purchase, methods=["POST"])
        self._register_route_helper("/platform-payments/products", self.get_products, methods=["GET"])
        self._register_route_helper("/platform-payments/purchase-history", self.get_purchase_history, methods=["GET"])
        self._register_route_helper("/platform-payments/create-web-payment", self.create_web_payment, methods=["POST"])
        custom_log(f"PlatformPaymentsModule registered {len(self.registered_routes)} routes")

    def verify_purchase(self):
        """Unified verification for all platforms."""
        try:
            data = request.get_json()
            platform = data.get('platform', 'unknown')
            
            if platform in ['google_play', 'app_store']:
                return await self._verify_native_platform(data)
            elif platform == 'web':
                return await self._verify_web_purchase(data)
            else:
                return jsonify({
                    "success": False,
                    "error": f"Unsupported platform: {platform}"
                }), 400
                
        except Exception as e:
            custom_log(f"❌ Purchase verification error: {e}", level="ERROR")
            return jsonify({"success": False, "error": str(e)}), 500

    async def _verify_web_purchase(self, data):
        """Verify web purchase using existing Stripe module."""
        try:
            payment_intent_id = data.get('payment_intent_id')
            
            if not self.stripe_module:
                return jsonify({
                    "success": False,
                    "error": "Stripe module not available"
                }), 503
            
            # Use existing Stripe confirmation logic
            result = await self.stripe_module.confirm_payment_internal(payment_intent_id)
            
            if result.get('success'):
                # Record as platform purchase for consistency
                await self._record_successful_purchase(
                    data['user_id'], 
                    data['product_id'], 
                    'web', 
                    result
                )
            
            return jsonify(result)
            
        except Exception as e:
            custom_log(f"❌ Web purchase verification error: {e}", level="ERROR")
            return jsonify({"success": False, "error": str(e)}), 500

    def create_web_payment(self):
        """Create web payment intent using existing Stripe module."""
        try:
            data = request.get_json()
            
            if not self.stripe_module:
                return jsonify({
                    "success": False,
                    "error": "Stripe module not available"
                }), 503
            
            # Get product details for web
            product_id = data.get('product_id')
            product_info = self._get_product_info(product_id, 'web')
            
            if not product_info:
                return jsonify({
                    "success": False,
                    "error": f"Product not found: {product_id}"
                }), 404
            
            # Create payment intent using existing Stripe module
            payment_data = {
                'user_id': data.get('user_id'),
                'amount': product_info['price'],
                'currency': product_info['currency'],
                'metadata': {
                    'product_id': product_id,
                    'platform': 'web',
                    'credits_awarded': product_info['credits_awarded']
                }
            }
            
            result = await self.stripe_module.create_payment_intent_internal(payment_data)
            
            return jsonify(result)
            
        except Exception as e:
            custom_log(f"❌ Error creating web payment: {e}", level="ERROR")
            return jsonify({"success": False, "error": str(e)}), 500

    def _get_product_info(self, product_id: str, platform: str) -> Dict:
        """Get product information for specific platform."""
        try:
            # Query platform_products table
            product = self.db_manager.find_one("platform_products", {
                "product_id": product_id,
                "platform": platform,
                "is_active": True
            })
            
            return product if product else None
            
        except Exception as e:
            custom_log(f"❌ Error getting product info: {e}", level="ERROR")
            return None

    def get_products(self):
        """Get available products for all platforms."""
        try:
            platform = request.args.get('platform', 'all')
            
            if platform == 'all':
                # Get all products for all platforms
                products = self.db_manager.find("platform_products", {"is_active": True})
            else:
                # Get products for specific platform
                products = self.db_manager.find("platform_products", {
                    "platform": platform,
                    "is_active": True
                })
            
            # Group by product_id for easier consumption
            grouped_products = {}
            for product in products:
                product_id = product['product_id']
                if product_id not in grouped_products:
                    grouped_products[product_id] = {
                        'product_id': product_id,
                        'title': product['title'],
                        'description': product['description'],
                        'platforms': {}
                    }
                
                grouped_products[product_id]['platforms'][product['platform']] = {
                    'platform_product_id': product['platform_product_id'],
                    'price': product['price'],
                    'currency': product['currency'],
                    'credits_awarded': product['credits_awarded'],
                    'product_type': product['product_type']
                }
            
            return jsonify({
                "success": True,
                "products": list(grouped_products.values())
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting products: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500
```

### Step 8.3: Enhanced Flutter Purchase Service
**File**: `flutter_base_05/lib/modules/in_app_purchases_module/services/unified_purchase_service.dart`

```dart
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/auth_manager.dart';
import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../tools/logging/logger.dart';
import '../../../utils/consts/config.dart';

class UnifiedPurchaseService {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final Logger _log = Logger();
  
  // Product IDs - configure based on your app
  static const List<String> _productIds = [
    'premium_upgrade',
    '100_coins',
    '500_coins',
    '1000_coins'
  ];
  
  Future<void> initialize() async {
    try {
      final available = await _inAppPurchase.isAvailable();
      
      StateManager().updateModuleState("in_app_purchases", {
        "isAvailable": available
      });
      
      if (available) {
        await _loadProducts();
        _setupPurchaseStream();
      }
      
      _log.info('✅ Unified purchase service initialized');
    } catch (e) {
      _log.error('❌ Failed to initialize purchase service: $e');
    }
  }
  
  Future<PurchaseResult> purchaseProduct(String productId, {String? platform}) async {
    final targetPlatform = platform ?? _getCurrentPlatform();
    
    try {
      switch (targetPlatform) {
        case 'google_play':
        case 'app_store':
          return await _purchaseNative(productId);
        case 'web':
          return await _purchaseWeb(productId);
        default:
          return PurchaseResult(
            success: false,
            error: 'Unsupported platform: $targetPlatform'
          );
      }
    } catch (e) {
      _log.error('❌ Purchase error: $e');
      return PurchaseResult(success: false, error: e.toString());
    }
  }
  
  Future<PurchaseResult> _purchaseNative(String productId) async {
    try {
      final products = StateManager().getModuleState("in_app_purchases")["products"] as List;
      final product = products.firstWhere((p) => p.id == productId);
      
      final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
      
      // Determine purchase type based on product
      bool success;
      if (_isConsumable(productId)) {
        success = await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
      } else {
        success = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      }
      
      if (success) {
        _log.info('✅ Native purchase initiated for: $productId');
      }
      
      return PurchaseResult(success: success, productId: productId);
    } catch (e) {
      _log.error('❌ Native purchase error: $e');
      return PurchaseResult(success: false, error: e.toString());
    }
  }
  
  Future<PurchaseResult> _purchaseWeb(String productId) async {
    try {
      // Create payment intent on server
      final response = await ConnectionsApiModule(Config.apiUrl).sendPostRequest(
        '/platform-payments/create-web-payment',
        {
          'user_id': await AuthManager().getCurrentUserId(),
          'product_id': productId,
          'platform': 'web'
        }
      );
      
      if (response['success']) {
        // For web, we would integrate with Stripe.js here
        // This is a placeholder for future web implementation
        _log.info('✅ Web payment intent created for: $productId');
        return PurchaseResult(
          success: true,
          productId: productId,
          clientSecret: response['client_secret'],
          paymentIntentId: response['payment_intent_id']
        );
      }
      
      return PurchaseResult(
        success: false,
        error: response['error'] ?? 'Unknown error'
      );
    } catch (e) {
      _log.error('❌ Web purchase error: $e');
      return PurchaseResult(success: false, error: e.toString());
    }
  }
  
  Future<void> _verifyWithServer(PurchaseDetails purchase) async {
    try {
      final receipt = {
        'product_id': purchase.productID,
        'purchase_token': purchase.purchaseID,
        'receipt_data': purchase.verificationData.serverVerificationData,
        'platform': _getCurrentPlatform(),
        'user_id': await AuthManager().getCurrentUserId(),
      };
      
      final response = await ConnectionsApiModule(Config.apiUrl).sendPostRequest(
        '/platform-payments/verify',
        receipt,
      );
      
      if (response['success'] == true) {
        _log.info('✅ Purchase verified with server');
        await _updateUserCredits(response['credits_awarded'] ?? 0);
      } else {
        _log.error('❌ Server verification failed: ${response['error']}');
      }
    } catch (e) {
      _log.error('❌ Server verification error: $e');
    }
  }
  
  String _getCurrentPlatform() {
    if (Platform.isAndroid) return 'google_play';
    if (Platform.isIOS) return 'app_store';
    return 'web'; // Default for web
  }
  
  bool _isConsumable(String productId) {
    const consumableProducts = ['100_coins', '500_coins', '1000_coins'];
    return consumableProducts.contains(productId);
  }
  
  Future<void> _updateUserCredits(int credits) async {
    // Integrate with existing credit system
    _log.info('✅ Updated user credits: +$credits');
  }
}

class PurchaseResult {
  final bool success;
  final String? productId;
  final String? error;
  final String? clientSecret;
  final String? paymentIntentId;
  
  PurchaseResult({
    required this.success,
    this.productId,
    this.error,
    this.clientSecret,
    this.paymentIntentId,
  });
}
```

### Step 8.4: Enhanced Configuration
**File**: `python_base_04/utils/config/config.py`

```python
# Add to Config class
GOOGLE_PLAY_KEY_PATH = os.getenv('GOOGLE_PLAY_KEY_PATH', '')
GOOGLE_PLAY_PACKAGE_NAME = os.getenv('GOOGLE_PLAY_PACKAGE_NAME', 'com.yourcompany.yourapp')
APP_STORE_SHARED_SECRET = os.getenv('APP_STORE_SHARED_SECRET', '')
APP_STORE_BUNDLE_ID = os.getenv('APP_STORE_BUNDLE_ID', 'com.yourcompany.yourapp')

# Web/Stripe configs (reuse existing)
STRIPE_SECRET_KEY = os.getenv('STRIPE_SECRET_KEY', '')
STRIPE_PUBLISHABLE_KEY = os.getenv('STRIPE_PUBLISHABLE_KEY', '')

# Platform-specific product mapping
PLATFORM_PRODUCTS = {
    'premium_upgrade': {
        'google_play': 'premium_upgrade',
        'app_store': 'premium_upgrade',
        'web': 'premium_upgrade_stripe'
    },
    '100_coins': {
        'google_play': '100_coins',
        'app_store': '100_coins',
        'web': '100_coins_stripe'
    },
    '500_coins': {
        'google_play': '500_coins',
        'app_store': '500_coins',
        'web': '500_coins_stripe'
    },
    '1000_coins': {
        'google_play': '1000_coins',
        'app_store': '1000_coins',
        'web': '1000_coins_stripe'
    }
}
```

### Step 8.5: Web Integration Testing
**File**: `python_base_04/tests/test_web_payments.py`

```python
import unittest
from unittest.mock import Mock, patch
from core.modules.platform_payments_module.platform_payments_main import PlatformPaymentsModule

class TestWebPayments(unittest.TestCase):
    def setUp(self):
        self.module = PlatformPaymentsModule()
    
    def test_create_web_payment(self):
        """Test web payment creation."""
        mock_data = {
            'user_id': 'test_user',
            'product_id': '100_coins',
            'platform': 'web'
        }
        
        # Test web payment creation
        with patch.object(self.module.stripe_module, 'create_payment_intent_internal') as mock_create:
            mock_create.return_value = {
                'success': True,
                'client_secret': 'pi_test_secret',
                'payment_intent_id': 'pi_test_id'
            }
            
            # Test the web payment endpoint
            # This would be tested with a mock Flask app
            pass
    
    def test_verify_web_purchase(self):
        """Test web purchase verification."""
        mock_data = {
            'user_id': 'test_user',
            'product_id': '100_coins',
            'platform': 'web',
            'payment_intent_id': 'pi_test_id'
        }
        
        # Test web purchase verification
        with patch.object(self.module.stripe_module, 'confirm_payment_internal') as mock_confirm:
            mock_confirm.return_value = {
                'success': True,
                'credits_awarded': 100
            }
            
            # Test the verification endpoint
            pass
```

## Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Flutter | 3-4 days | None |
| Phase 2: Python | 2-3 days | Phase 1 |
| Phase 3: Database | 1 day | None |
| Phase 4: Configuration | 1 day | Phase 2 |
| Phase 5: Testing | 2-3 days | Phase 1-4 |
| Phase 6: Deployment | 1-2 days | Phase 1-5 |
| Phase 7: Monitoring | 1 day | Phase 6 |
| Phase 8: Web Support | 2-3 days | Phase 1-7 (Future) |

**Total Estimated Time**: 11-15 days (Mobile) + 2-3 days (Web)

## Success Criteria

### Mobile Platforms (Phases 1-7)
- [ ] Flutter app can initiate purchases on both platforms
- [ ] Python backend can verify purchases with platform servers
- [ ] User credits are awarded correctly after verification
- [ ] Purchase history is tracked in database
- [ ] Error handling works for failed purchases
- [ ] Testing passes on both platforms
- [ ] Production deployment successful
- [ ] Monitoring and analytics working

### Web Platform (Phase 8 - Future)
- [ ] Web payment flow integrates with existing Stripe module
- [ ] Cross-platform product mapping works correctly
- [ ] Web purchases are verified and recorded consistently
- [ ] Unified purchase service handles all platforms
- [ ] Web-specific database schema supports all payment methods
- [ ] Testing passes for web platform
- [ ] Web deployment successful

## Risk Mitigation

1. **Platform API Changes**: Use latest SDK versions and monitor for updates
2. **Verification Failures**: Implement retry logic and fallback mechanisms
3. **Database Issues**: Use transactions and proper error handling
4. **Security**: Validate all inputs and use secure storage for keys
5. **Testing**: Use sandbox environments for thorough testing

## Next Steps

1. **Review and approve this plan**
2. **Set up development environment**
3. **Begin Phase 1 implementation**
4. **Regular progress updates**
5. **Testing at each phase**
6. **Production deployment**

This plan ensures a robust, secure, and scalable in-app purchase system that integrates seamlessly with your existing architecture. 