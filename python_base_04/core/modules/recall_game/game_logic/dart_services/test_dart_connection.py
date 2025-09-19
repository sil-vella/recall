#!/usr/bin/env python3
"""
Simple test script to verify Dart service connection
"""

import subprocess
import json
import time
import sys

def test_dart_service_directly():
    """Test the Dart service directly via subprocess"""
    print("Testing Dart service directly...")
    
    try:
        # Start Dart service
        process = subprocess.Popen(
            ['dart', 'run', 'simple_dart_service.dart'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0
        )
        
        # Send health check
        health_check = {
            'action': 'health_check',
            'game_id': '',
            'data': {}
        }
        
        process.stdin.write(json.dumps(health_check) + '\n')
        process.stdin.flush()
        
        # Read response
        response_line = process.stdout.readline()
        if response_line and response_line.strip():
            response = json.loads(response_line.strip())
            print(f"Response: {response}")
            
            if response.get('status') == 'healthy':
                print("✅ Dart service is responding correctly")
                return True
            else:
                print("❌ Dart service returned error")
                return False
        else:
            print("❌ No response from Dart service")
            return False
            
    except Exception as e:
        print(f"❌ Error testing Dart service: {e}")
        return False
    finally:
        if 'process' in locals():
            process.terminate()
            process.wait()

if __name__ == "__main__":
    success = test_dart_service_directly()
    sys.exit(0 if success else 1)
