#!/usr/bin/env python3
"""
Persistent Dart Game Service for Production

This script starts the Dart game service and keeps it running indefinitely,
ready to handle game logic requests from the Flask server.
"""

import sys
import os
import time
import signal
import threading

# Add the python_base_04 directory to the Python path
sys.path.append(os.path.join(os.path.dirname(__file__), '../../../../..'))

from core.modules.recall_game.game_logic.dart_services.dart_subprocess_manager import dart_subprocess_manager

class PersistentDartService:
    """Manages a persistent Dart service for production use"""
    
    def __init__(self):
        self.running = False
        self.dart_service_path = "simple_dart_service.dart"
        self.health_check_interval = 30  # Check health every 30 seconds
        self.health_check_thread = None
        
    def start_service(self):
        """Start the persistent Dart service"""
        print("🚀 Starting Persistent Dart Game Service...")
        print("=" * 50)
        
        # Start the Dart service
        if not dart_subprocess_manager.start_dart_service(self.dart_service_path):
            print("❌ Failed to start Dart service")
            return False
        
        # Wait for service to initialize
        print("⏳ Waiting for Dart service to initialize...")
        time.sleep(3)
        
        # Verify service is running
        if not dart_subprocess_manager.health_check():
            print("❌ Dart service health check failed")
            return False
        
        print("✅ Dart service started successfully!")
        self.running = True
        
        # Start health monitoring in background
        self.start_health_monitoring()
        
        return True
    
    def start_health_monitoring(self):
        """Start background health monitoring"""
        def health_monitor():
            while self.running:
                try:
                    time.sleep(self.health_check_interval)
                    if self.running and not dart_subprocess_manager.health_check():
                        print("⚠️  Dart service health check failed - attempting restart...")
                        self.restart_service()
                except Exception as e:
                    print(f"⚠️  Health monitoring error: {e}")
        
        self.health_check_thread = threading.Thread(target=health_monitor, daemon=True)
        self.health_check_thread.start()
        print(f"🔍 Health monitoring started (checking every {self.health_check_interval}s)")
    
    def restart_service(self):
        """Restart the Dart service"""
        print("🔄 Restarting Dart service...")
        dart_subprocess_manager.stop_dart_service()
        time.sleep(2)
        
        if dart_subprocess_manager.start_dart_service(self.dart_service_path):
            print("✅ Dart service restarted successfully")
        else:
            print("❌ Failed to restart Dart service")
            self.running = False
    
    def stop_service(self):
        """Stop the persistent Dart service"""
        print("\n🛑 Stopping Persistent Dart Game Service...")
        self.running = False
        
        if dart_subprocess_manager.is_service_running():
            dart_subprocess_manager.stop_dart_service()
            print("✅ Dart service stopped")
        
        print("👋 Persistent Dart Service shutdown complete")
    
    def run(self):
        """Run the persistent service"""
        # Set up signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        # Start the service
        if not self.start_service():
            return 1
        
        try:
            # Keep the service running
            print("\n🎮 Dart Game Service is running and ready!")
            print("📡 Listening for game logic requests from Flask server...")
            print("💡 Press Ctrl+C to stop the service")
            print("-" * 50)
            
            while self.running:
                time.sleep(1)
                
        except KeyboardInterrupt:
            print("\n\n🛑 Received shutdown signal...")
        finally:
            self.stop_service()
        
        return 0
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        print(f"\n🛑 Received signal {signum}, shutting down...")
        self.running = False

def main():
    """Main function"""
    service = PersistentDartService()
    return service.run()

if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except Exception as e:
        print(f"\n💥 Fatal error: {e}")
        sys.exit(1)
