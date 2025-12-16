#!/usr/bin/env python3
"""
Script to create Prometheus datasource in Grafana via API
This is a workaround for provisioning issues
"""
import requests
import json
import sys
import time

GRAFANA_URL = "http://localhost:3001"
GRAFANA_USER = "admin"
GRAFANA_PASSWORD = "admin"

def create_datasource():
    """Create Prometheus datasource in Grafana"""
    url = f"{GRAFANA_URL}/api/datasources"
    auth = (GRAFANA_USER, GRAFANA_PASSWORD)
    
    # Check if datasource already exists
    print("Checking if Prometheus datasource exists...")
    try:
        response = requests.get(url, auth=auth, timeout=5)
        if response.status_code == 200:
            datasources = response.json()
            for ds in datasources:
                if ds.get('name') == 'Prometheus':
                    print(f"✅ Datasource 'Prometheus' already exists (ID: {ds.get('id')})")
                    return True
    except Exception as e:
        print(f"⚠️  Error checking datasources: {e}")
    
    # Create datasource
    datasource_config = {
        "name": "Prometheus",
        "type": "prometheus",
        "access": "proxy",
        "url": "http://prometheus:9090",
        "isDefault": True,
        "editable": True,
        "jsonData": {
            "httpMethod": "GET"
        }
    }
    
    print(f"Creating Prometheus datasource...")
    try:
        response = requests.post(
            url,
            auth=auth,
            json=datasource_config,
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Datasource created successfully!")
            print(f"   ID: {result.get('datasource', {}).get('id')}")
            print(f"   UID: {result.get('datasource', {}).get('uid')}")
            return True
        elif response.status_code == 409:
            print("ℹ️  Datasource already exists (409 Conflict)")
            return True
        else:
            print(f"❌ Failed to create datasource: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"❌ Cannot connect to Grafana at {GRAFANA_URL}")
        print("   Make sure Grafana is running: docker ps | grep grafana")
        return False
    except Exception as e:
        print(f"❌ Error creating datasource: {e}")
        return False

def test_datasource():
    """Test the Prometheus datasource"""
    url = f"{GRAFANA_URL}/api/datasources/name/Prometheus"
    auth = (GRAFANA_USER, GRAFANA_PASSWORD)
    
    print("\nTesting datasource connection...")
    try:
        response = requests.get(url, auth=auth, timeout=5)
        if response.status_code == 200:
            ds = response.json()
            test_url = f"{GRAFANA_URL}/api/datasources/{ds['id']}/health"
            test_response = requests.get(test_url, auth=auth, timeout=10)
            if test_response.status_code == 200:
                print("✅ Datasource test passed!")
                return True
            else:
                print(f"⚠️  Datasource test returned: {test_response.status_code}")
                print(f"   Response: {test_response.text}")
                return False
    except Exception as e:
        print(f"⚠️  Error testing datasource: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("Grafana Prometheus Datasource Creator")
    print("=" * 60)
    print()
    
    # Wait for Grafana to be ready
    print("Waiting for Grafana to be ready...")
    for i in range(10):
        try:
            response = requests.get(f"{GRAFANA_URL}/api/health", timeout=2)
            if response.status_code == 200:
                print("✅ Grafana is ready")
                break
        except:
            if i < 9:
                print(f"   Waiting... ({i+1}/10)")
                time.sleep(2)
            else:
                print("❌ Grafana is not responding")
                sys.exit(1)
    
    print()
    
    if create_datasource():
        test_datasource()
        print()
        print("=" * 60)
        print("✅ Setup complete!")
        print("=" * 60)
        print("\nYou can now:")
        print("1. Open Grafana: http://localhost:3001")
        print("2. Go to Dashboards → Browse")
        print("3. Open 'Game Analytics Dashboard'")
        print("4. The datasource should now be found!")
    else:
        print()
        print("=" * 60)
        print("❌ Setup failed")
        print("=" * 60)
        print("\nManual steps:")
        print("1. Open Grafana: http://localhost:3001")
        print("2. Login: admin/admin")
        print("3. Go to: Connections → Data sources")
        print("4. Click 'Add data source'")
        print("5. Select 'Prometheus'")
        print("6. URL: http://prometheus:9090")
        print("7. Name: Prometheus")
        print("8. Click 'Save & Test'")
        sys.exit(1)
