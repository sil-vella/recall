#!/usr/bin/env python3
"""
Test script for Google Play API integration.

This script tests the Google Play API client and integration without requiring
actual Google Play credentials. It will show the structure and verify imports.
"""

import sys
import os

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tools.logger.custom_logging import custom_log
from utils.config.config import Config

def test_google_play_config():
    """Test Google Play configuration loading."""
    print("🔧 Testing Google Play Configuration...")
    
    try:
        # Test configuration values
        package_name = Config.GOOGLE_PLAY_PACKAGE_NAME
        service_account_file = Config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE
        api_quota_limit = Config.GOOGLE_PLAY_API_QUOTA_LIMIT
        sync_interval = Config.GOOGLE_PLAY_SYNC_INTERVAL_HOURS
        
        print(f"✅ Package Name: {package_name}")
        print(f"✅ Service Account File: {service_account_file}")
        print(f"✅ API Quota Limit: {api_quota_limit}")
        print(f"✅ Sync Interval: {sync_interval} hours")
        
        return True
        
    except Exception as e:
        print(f"❌ Configuration test failed: {e}")
        return False

def test_google_play_api_client_import():
    """Test Google Play API client import."""
    print("\n🔧 Testing Google Play API Client Import...")
    
    try:
        from core.modules.in_app_purchases_module.sync.google_play_api_client import GooglePlayAPIClient
        print("✅ Google Play API Client imported successfully")
        return True
        
    except ImportError as e:
        print(f"❌ Import failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_product_sync_manager_import():
    """Test Product Sync Manager import."""
    print("\n🔧 Testing Product Sync Manager Import...")
    
    try:
        from core.modules.in_app_purchases_module.sync.product_sync_manager import ProductSyncManager
        print("✅ Product Sync Manager imported successfully")
        return True
        
    except ImportError as e:
        print(f"❌ Import failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_google_play_verifier_import():
    """Test Google Play Verifier import."""
    print("\n🔧 Testing Google Play Verifier Import...")
    
    try:
        from core.modules.in_app_purchases_module.verifiers.google_play_verifier import GooglePlayVerifier
        print("✅ Google Play Verifier imported successfully")
        return True
        
    except ImportError as e:
        print(f"❌ Import failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_dependencies():
    """Test Google API dependencies."""
    print("\n🔧 Testing Google API Dependencies...")
    
    try:
        import google.oauth2.service_account
        print("✅ google.oauth2.service_account imported successfully")
        
        import googleapiclient.discovery
        print("✅ googleapiclient.discovery imported successfully")
        
        import googleapiclient.errors
        print("✅ googleapiclient.errors imported successfully")
        
        return True
        
    except ImportError as e:
        print(f"❌ Google API dependency import failed: {e}")
        print("💡 Make sure to install Google API dependencies:")
        print("   pip install google-api-python-client google-auth google-auth-httplib2 google-auth-oauthlib")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def main():
    """Run all tests."""
    print("🚀 Starting Google Play API Integration Tests...\n")
    
    tests = [
        ("Configuration", test_google_play_config),
        ("Dependencies", test_dependencies),
        ("API Client Import", test_google_play_api_client_import),
        ("Product Sync Manager Import", test_product_sync_manager_import),
        ("Google Play Verifier Import", test_google_play_verifier_import),
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
        print("🎉 All tests passed! Google Play API integration is ready.")
        print("\n📝 Next steps:")
        print("1. Set up Google Play service account credentials")
        print("2. Configure GOOGLE_PLAY_SERVICE_ACCOUNT_FILE in environment")
        print("3. Update GOOGLE_PLAY_PACKAGE_NAME to your app's package name")
        print("4. Test with real Google Play Console data")
    else:
        print("⚠️ Some tests failed. Please check the errors above.")
        print("\n🔧 Common issues:")
        print("- Install Google API dependencies: pip install google-api-python-client google-auth google-auth-httplib2 google-auth-oauthlib")
        print("- Check Python path and imports")
        print("- Verify configuration values")

if __name__ == "__main__":
    main() 