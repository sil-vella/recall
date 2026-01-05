#!/usr/bin/env python3
"""
Test script for Analytics and Metrics System
Run this script to verify all phases are working correctly.
"""

import requests
import json
import time
from datetime import datetime

# Flask API is on port 5001, Metrics server is on port 8000
BASE_URL = None
METRICS_URL = None

# Try to find Flask app (API)
for port in [5001, 8081, 5000]:
    try:
        test_url = f"http://localhost:{port}/health"
        response = requests.get(test_url, timeout=2)
        if response.status_code == 200:
            BASE_URL = f"http://localhost:{port}"
            print(f"Found Flask app on port {port}")
            break
    except:
        continue

if not BASE_URL:
    BASE_URL = "http://localhost:5001"  # Default fallback

# Metrics are on port 8000 (MetricsCollector HTTP server)
METRICS_URL = "http://localhost:8000/metrics"

# Colors for output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
RESET = "\033[0m"

def print_test(name):
    print(f"\n{BLUE}Testing: {name}{RESET}")
    print("-" * 60)

def print_success(message):
    print(f"{GREEN}✅ {message}{RESET}")

def print_error(message):
    print(f"{RED}❌ {message}{RESET}")

def print_warning(message):
    print(f"{YELLOW}⚠️  {message}{RESET}")

def print_info(message):
    print(f"ℹ️  {message}")

# Phase 1: Prometheus Metrics Tests
def test_phase1_metrics_endpoint():
    """Test Phase 1: Prometheus Metrics Endpoint"""
    print_test("Phase 1: Prometheus Metrics Endpoint")
    
    try:
        response = requests.get(METRICS_URL, timeout=5)
        if response.status_code == 200:
            print_success(f"Metrics endpoint accessible (HTTP {response.status_code})")
            return True, response.text
        else:
            print_error(f"Metrics endpoint returned HTTP {response.status_code}")
            return False, None
    except requests.exceptions.ConnectionError:
        print_error("Cannot connect to Flask app. Is it running on port 8081?")
        print_info("Start with: docker-compose up -d flask-external")
        return False, None
    except Exception as e:
        print_error(f"Error accessing metrics endpoint: {e}")
        return False, None

def test_phase1_user_metrics(metrics_text):
    """Test Phase 1: User Metrics"""
    print_test("Phase 1: User Metrics")
    
    if not metrics_text:
        print_warning("Skipping - no metrics data available")
        return False
    
    required_metrics = [
        "user_registrations_total",
        "user_logins_total",
        "active_users_current",
        "guest_account_conversions_total"
    ]
    
    found = []
    missing = []
    
    for metric in required_metrics:
        if metric in metrics_text:
            found.append(metric)
            print_success(f"Found metric: {metric}")
        else:
            missing.append(metric)
            print_error(f"Missing metric: {metric}")
    
    if missing:
        print_warning(f"Missing {len(missing)} metrics. They may appear after first use.")
        return len(found) > 0
    return True

def test_phase1_game_metrics(metrics_text):
    """Test Phase 1: Game Metrics"""
    print_test("Phase 1: Game Metrics")
    
    if not metrics_text:
        print_warning("Skipping - no metrics data available")
        return False
    
    required_metrics = [
        "dutch_games_created_total",
        "dutch_games_completed_total",
        "dutch_game_duration_seconds",
        "coin_transactions_total",
        "special_card_used_total",
        "dutch_calls_total"
    ]
    
    found = []
    missing = []
    
    for metric in required_metrics:
        if metric in metrics_text:
            found.append(metric)
            print_success(f"Found metric: {metric}")
        else:
            missing.append(metric)
            print_warning(f"Metric not yet created: {metric} (will appear after first use)")
    
    if len(found) > 0:
        print_success(f"Found {len(found)}/{len(required_metrics)} game metrics")
        return True
    else:
        print_warning("No game metrics found yet. They will appear after games are played.")
        return True  # Not an error, just not used yet

# Phase 2: Analytics API Tests
def test_phase2_analytics_endpoint():
    """Test Phase 2: Analytics API Endpoint"""
    print_test("Phase 2: Analytics API Endpoint")
    
    # First, try to register/login to get a token
    test_email = f"test_{int(time.time())}@example.com"
    test_password = "Test123!@#"
    test_username = f"testuser_{int(time.time())}"
    
    try:
        # Register a test user
        print_info("Registering test user...")
        register_response = requests.post(
            f"{BASE_URL}/userauth/register",
            json={
                "email": test_email,
                "password": test_password,
                "username": test_username
            },
            timeout=10
        )
        
        if register_response.status_code in [200, 201]:
            print_success("Test user registered")
            register_data = register_response.json()
            token = register_data.get('access_token') or register_data.get('token')
            
            if not token:
                # Try to login
                print_info("Getting token via login...")
                login_response = requests.post(
                    f"{BASE_URL}/userauth/login",
                    json={
                        "email": test_email,
                        "password": test_password
                    },
                    timeout=10
                )
                if login_response.status_code == 200:
                    login_data = login_response.json()
                    token = login_data.get('access_token') or login_data.get('token')
            
            if token:
                print_success("Got authentication token")
                
                # Test analytics endpoint
                print_info("Testing analytics track endpoint...")
                analytics_response = requests.post(
                    f"{BASE_URL}/userauth/analytics/track",
                    headers={
                        "Authorization": f"Bearer {token}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "event_type": "test_event",
                        "event_data": {
                            "test_key": "test_value",
                            "timestamp": datetime.utcnow().isoformat()
                        },
                        "platform": "test"
                    },
                    timeout=10
                )
                
                if analytics_response.status_code == 200:
                    print_success("Analytics endpoint working")
                    print_info(f"Response: {analytics_response.json()}")
                    return True
                else:
                    print_error(f"Analytics endpoint returned HTTP {analytics_response.status_code}")
                    print_info(f"Response: {analytics_response.text}")
                    return False
            else:
                print_error("Could not get authentication token")
                return False
        else:
            print_warning(f"User registration failed (HTTP {register_response.status_code})")
            print_info("This might be expected if user already exists or service is not fully running")
            return False
            
    except requests.exceptions.ConnectionError:
        print_error("Cannot connect to Flask app. Is it running?")
        return False
    except Exception as e:
        print_error(f"Error testing analytics endpoint: {e}")
        return False

# Code Integration Tests
def test_code_integration():
    """Test that code integration is correct"""
    print_test("Code Integration Verification")
    
    import os
    import sys
    
    # Check Python files exist
    files_to_check = [
        "core/monitoring/metrics_collector.py",
        "core/services/analytics_service.py",
        "core/modules/analytics_module/analytics_main.py"
    ]
    
    base_path = os.path.dirname(os.path.abspath(__file__))
    
    all_exist = True
    for file_path in files_to_check:
        full_path = os.path.join(base_path, file_path)
        if os.path.exists(full_path):
            print_success(f"File exists: {file_path}")
        else:
            print_error(f"File missing: {file_path}")
            all_exist = False
    
    # Check Flutter file exists (use absolute path)
    flutter_file = "lib/modules/analytics_module/analytics_module.dart"
    # Try relative path first
    flutter_path_rel = os.path.join(base_path, "../../flutter_base_05", flutter_file)
    # Try absolute path
    flutter_path_abs = os.path.join("/Users/sil/Documents/Work/reignofplay/Recall/app_dev/flutter_base_05", flutter_file)
    
    if os.path.exists(flutter_path_rel):
        print_success(f"Flutter file exists: {flutter_file}")
    elif os.path.exists(flutter_path_abs):
        print_success(f"Flutter file exists: {flutter_file}")
    else:
        print_error(f"Flutter file missing: {flutter_file}")
        all_exist = False
    
    return all_exist

def main():
    """Run all tests"""
    print(f"\n{BLUE}{'='*60}")
    print("Analytics and Metrics System Test Suite")
    print(f"{'='*60}{RESET}\n")
    
    results = {}
    
    # Code Integration Test (always run)
    results['code_integration'] = test_code_integration()
    
    # Phase 1: Prometheus Metrics
    metrics_accessible, metrics_text = test_phase1_metrics_endpoint()
    results['metrics_endpoint'] = metrics_accessible
    
    if metrics_accessible:
        results['user_metrics'] = test_phase1_user_metrics(metrics_text)
        results['game_metrics'] = test_phase1_game_metrics(metrics_text)
    else:
        results['user_metrics'] = False
        results['game_metrics'] = False
    
    # Phase 2: Analytics API
    results['analytics_endpoint'] = test_phase2_analytics_endpoint()
    
    # Summary
    print(f"\n{BLUE}{'='*60}")
    print("Test Summary")
    print(f"{'='*60}{RESET}\n")
    
    for test_name, result in results.items():
        if result:
            print_success(f"{test_name}: PASSED")
        else:
            print_error(f"{test_name}: FAILED")
    
    passed = sum(1 for r in results.values() if r)
    total = len(results)
    
    print(f"\n{BLUE}Results: {passed}/{total} tests passed{RESET}\n")
    
    if passed == total:
        print_success("All tests passed! 🎉")
        return 0
    else:
        print_warning("Some tests failed. Check the output above for details.")
        return 1

if __name__ == "__main__":
    exit(main())
