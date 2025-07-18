#!/usr/bin/env python3
"""
Debug startup script for Flask application
Starts debugpy and then gunicorn
"""

import subprocess
import sys
import os
import time

def main():
    """Start debugpy and then gunicorn"""
    try:
        print("🔧 Starting debugpy...")
        
        # Import and start debugpy
        import debugpy
        debugpy.listen(("0.0.0.0", 5678))
        print("✅ Debugpy listening on 0.0.0.0:5678")
        
        # Wait for client to connect
        print("⏳ Waiting for VS Code debugger to connect...")
        debugpy.wait_for_client()
        print("✅ VS Code debugger connected!")
        
        # Start gunicorn
        gunicorn_cmd = [
            "gunicorn",
            "--bind", "0.0.0.0:5001",
            "--worker-class", "gevent",
            "--workers", "1",
            "--timeout", "120",
            "--keep-alive", "5",
            "app:app"
        ]
        
        print(f"🚀 Starting gunicorn: {' '.join(gunicorn_cmd)}")
        
        # Execute gunicorn
        subprocess.run(gunicorn_cmd)
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 