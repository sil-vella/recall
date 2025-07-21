#!/usr/bin/env python3
"""
Simple test for Stripe module functionality.
This tests the module without requiring actual Stripe keys.
"""

import os
import sys
import json
from unittest.mock import Mock, patch

# Add the project root to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..'))

from system.modules.stripe_module.stripe_main import StripeModule


def test_stripe_module_creation():
    """Test that Stripe module can be created without Stripe keys."""
    print("🧪 Testing Stripe module creation...")
    
    # Create module without Stripe keys
    module = StripeModule()
    
    # Should be created but Stripe should be None
    assert module.stripe is None
    assert module.webhook_secret is None
    
    print("✅ Stripe module creation test passed")


def test_credit_packages_endpoint():
    """Test the credit packages endpoint."""
    print("🧪 Testing credit packages endpoint...")
    
    module = StripeModule()
    
    # Mock Flask request context
    with patch('flask.jsonify') as mock_jsonify:
        module.get_credit_packages()
        
        # Verify jsonify was called with correct data
        mock_jsonify.assert_called_once()
        call_args = mock_jsonify.call_args[0][0]
        
        assert call_args['success'] is True
        assert 'packages' in call_args
        assert len(call_args['packages']) > 0
        
        # Check package structure
        package = call_args['packages'][0]
        assert 'id' in package
        assert 'name' in package
        assert 'credits' in package
        assert 'price_usd' in package
        assert 'description' in package
    
    print("✅ Credit packages endpoint test passed")


def test_credit_calculation():
    """Test credit calculation from USD."""
    print("🧪 Testing credit calculation...")
    
    module = StripeModule()
    
    # Test credit calculation
    credits = module._calculate_credits_from_usd(10.0)
    assert credits == 100  # $10 = 100 credits
    
    credits = module._calculate_credits_from_usd(5.0)
    assert credits == 50   # $5 = 50 credits
    
    credits = module._calculate_credits_from_usd(0.0)
    assert credits == 0    # $0 = 0 credits
    
    print("✅ Credit calculation test passed")


def test_webhook_signature_validation():
    """Test webhook signature validation logic."""
    print("🧪 Testing webhook signature validation...")
    
    module = StripeModule()
    
    # Test with no webhook secret
    module.webhook_secret = None
    
    # Mock request
    mock_request = Mock()
    mock_request.get_data.return_value = b'test_payload'
    mock_request.headers.get.return_value = None
    
    with patch('flask.request', mock_request):
        with patch('flask.jsonify') as mock_jsonify:
            module.handle_webhook()
            
            # Should return error for missing signature
            mock_jsonify.assert_called_once()
            call_args = mock_jsonify.call_args[0][0]
            assert call_args['success'] is False
            assert 'Missing Stripe signature' in call_args['error']
    
    print("✅ Webhook signature validation test passed")


def test_payment_intent_creation_without_stripe():
    """Test payment intent creation when Stripe is not configured."""
    print("🧪 Testing payment intent creation without Stripe...")
    
    module = StripeModule()
    
    # Mock request data
    mock_request = Mock()
    mock_request.get_json.return_value = {
        'user_id': 'test_user',
        'amount': 10.0,
        'currency': 'usd'
    }
    
    with patch('flask.request', mock_request):
        with patch('flask.jsonify') as mock_jsonify:
            module.create_payment_intent()
            
            # Should return error for unconfigured Stripe
            mock_jsonify.assert_called_once()
            call_args = mock_jsonify.call_args[0][0]
            assert call_args['success'] is False
            assert 'Stripe is not configured' in call_args['error']
    
    print("✅ Payment intent creation test passed")


def main():
    """Run all tests."""
    print("🚀 Starting Stripe module tests...\n")
    
    try:
        test_stripe_module_creation()
        test_credit_packages_endpoint()
        test_credit_calculation()
        test_webhook_signature_validation()
        test_payment_intent_creation_without_stripe()
        
        print("\n🎉 All Stripe module tests passed!")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main()) 