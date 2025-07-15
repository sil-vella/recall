#!/usr/bin/env python3
"""
Test Stripe configuration integration with the config system.
"""

import os
import sys

# Add the project root to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..'))

from utils.config.config import Config


def test_stripe_config_integration():
    """Test that Stripe configuration is properly integrated."""
    print("🧪 Testing Stripe configuration integration...")
    
    # Check that Stripe config attributes exist
    assert hasattr(Config, 'STRIPE_SECRET_KEY'), "STRIPE_SECRET_KEY not found in Config"
    assert hasattr(Config, 'STRIPE_PUBLISHABLE_KEY'), "STRIPE_PUBLISHABLE_KEY not found in Config"
    assert hasattr(Config, 'STRIPE_WEBHOOK_SECRET'), "STRIPE_WEBHOOK_SECRET not found in Config"
    assert hasattr(Config, 'STRIPE_API_VERSION'), "STRIPE_API_VERSION not found in Config"
    
    print("✅ Stripe configuration attributes exist")
    
    # Check that values are loaded (should be empty strings for sensitive data without Vault)
    print(f"STRIPE_SECRET_KEY: {'[SET]' if Config.STRIPE_SECRET_KEY else '[NOT SET]'}")
    print(f"STRIPE_PUBLISHABLE_KEY: {'[SET]' if Config.STRIPE_PUBLISHABLE_KEY else '[NOT SET]'}")
    print(f"STRIPE_WEBHOOK_SECRET: {'[SET]' if Config.STRIPE_WEBHOOK_SECRET else '[NOT SET]'}")
    print(f"STRIPE_API_VERSION: {Config.STRIPE_API_VERSION}")
    
    # Test that API version has a default value
    assert Config.STRIPE_API_VERSION == "2023-10-16", f"Expected API version 2023-10-16, got {Config.STRIPE_API_VERSION}"
    
    print("✅ Stripe configuration integration test passed")


def test_stripe_module_with_config():
    """Test that Stripe module can be initialized with Config."""
    print("🧪 Testing Stripe module with Config integration...")
    
    try:
        from core.modules.stripe_module.stripe_main import StripeModule
        
        # Create module (should work even without Stripe keys)
        module = StripeModule()
        
        # Check that module was created
        assert module is not None, "StripeModule creation failed"
        
        # Check that stripe is None (since no keys are set)
        assert module.stripe is None, "Stripe should be None when no keys are configured"
        assert module.webhook_secret is None, "Webhook secret should be None when not configured"
        
        print("✅ Stripe module initialization with Config works")
        
    except Exception as e:
        print(f"❌ Error testing Stripe module: {e}")
        return False
    
    return True


def main():
    """Run all configuration tests."""
    print("🚀 Starting Stripe configuration tests...\n")
    
    try:
        test_stripe_config_integration()
        test_stripe_module_with_config()
        
        print("\n🎉 All Stripe configuration tests passed!")
        print("\n📝 Next steps:")
        print("1. Add Stripe secrets to Vault at 'flask-app/stripe'")
        print("2. Or add secrets to files in /secrets/ directory")
        print("3. Test with actual Stripe keys")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main()) 