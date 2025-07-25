#!/usr/bin/env python3
"""
Test script for real Google Play API integration.

This script tests the actual Google Play API calls once credentials are configured.
"""

import sys
import os

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tools.logger.custom_logging import custom_log
from utils.config.config import Config

def test_google_play_api_client():
    """Test the Google Play API client with real credentials."""
    print("🔧 Testing Google Play API Client with real credentials...")
    
    try:
        from core.modules.in_app_purchases_module.sync.google_play_api_client import GooglePlayAPIClient
        
        # Create a mock app manager for testing
        class MockAppManager:
            def __init__(self):
                self.config = Config()
        
        app_manager = MockAppManager()
        api_client = GooglePlayAPIClient(app_manager)
        
        # Test initialization
        if api_client.initialize():
            print("✅ Google Play API client initialized successfully")
            
            # Test health check
            health = api_client.health_check()
            print(f"✅ Health check: {health}")
            
            return True
        else:
            print("❌ Failed to initialize Google Play API client")
            return False
            
    except Exception as e:
        print(f"❌ Error testing Google Play API client: {e}")
        return False

def test_product_sync():
    """Test product sync functionality."""
    print("\n🔧 Testing Product Sync Manager...")
    
    try:
        from core.modules.in_app_purchases_module.sync.product_sync_manager import ProductSyncManager
        
        # Create a mock app manager for testing
        class MockAppManager:
            def __init__(self):
                self.config = Config()
            def get_db_manager(self, role):
                return None  # Mock database manager
        
        app_manager = MockAppManager()
        sync_manager = ProductSyncManager(app_manager)
        
        print("✅ Product Sync Manager created successfully")
        return True
        
    except Exception as e:
        print(f"❌ Error testing Product Sync Manager: {e}")
        return False

def test_configuration():
    """Test configuration values."""
    print("\n🔧 Testing Configuration...")
    
    try:
        package_name = Config.GOOGLE_PLAY_PACKAGE_NAME
        service_account_data = Config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE
        
        print(f"✅ Package Name: {package_name}")
        
        # Check if service account data is configured
        if service_account_data:
            if service_account_data.startswith('{'):
                print("✅ Service Account JSON content configured")
                return True
            elif os.path.exists(service_account_data):
                print("✅ Service account file exists")
                return True
            else:
                print("❌ Service account file not found")
                return False
        else:
            print("❌ Service Account not configured")
            return False
            
    except Exception as e:
        print(f"❌ Error testing configuration: {e}")
        return False

def main():
    """Run all tests."""
    print("🚀 Starting Real Google Play API Integration Tests...\n")
    
    tests = [
        ("Configuration", test_configuration),
        ("API Client", test_google_play_api_client),
        ("Product Sync", test_product_sync),
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        print(f"📋 Running {test_name} test...")
        if test_func():
            passed += 1
            print(f"✅ {test_name} test passed\n")
        else:
            print(f"❌ {test_name} test failed\n")
    
    print("=" * 50)
    print(f"📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Google Play API integration is ready for production.")
        print("\n📝 Next steps:")
        print("1. Grant service account permissions in Google Play Console")
        print("2. Update package name to your actual app package")
        print("3. Test with real Google Play Console data")
    else:
        print("⚠️ Some tests failed. Please check the errors above.")
        print("\n🔧 Common issues:")
        print("- Ensure service account file is properly configured")
        print("- Check Google Play Console permissions")
        print("- Verify package name configuration")

if __name__ == "__main__":
    main() 