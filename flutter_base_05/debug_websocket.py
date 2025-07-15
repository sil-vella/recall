#!/usr/bin/env python3
"""
WebSocket Debug Script for Flutter App
Tests WebSocket connections and session handling
"""

import asyncio
import websockets
import json
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WebSocketDebugger:
    def __init__(self, url="ws://localhost:8081"):
        self.url = url
        self.websocket = None
        
    async def connect(self):
        """Connect to WebSocket server"""
        try:
            logger.info(f"🔌 Connecting to {self.url}")
            self.websocket = await websockets.connect(
                self.url,
                extra_headers={
                    'token': 'test_token_123',
                    'client_id': 'python_debugger',
                    'version': '1.0.0'
                }
            )
            logger.info("✅ Connected successfully")
            return True
        except Exception as e:
            logger.error(f"❌ Connection failed: {e}")
            return False
    
    async def send_message(self, event, data):
        """Send a message to the WebSocket server"""
        if not self.websocket:
            logger.error("❌ Not connected")
            return False
            
        try:
            message = {
                'event': event,
                'data': data
            }
            await self.websocket.send(json.dumps(message))
            logger.info(f"📤 Sent: {event} - {data}")
            return True
        except Exception as e:
            logger.error(f"❌ Send failed: {e}")
            return False
    
    async def listen(self, timeout=5):
        """Listen for messages from the server"""
        if not self.websocket:
            logger.error("❌ Not connected")
            return
            
        try:
            logger.info(f"👂 Listening for messages (timeout: {timeout}s)")
            async with asyncio.timeout(timeout):
                while True:
                    message = await self.websocket.recv()
                    logger.info(f"📥 Received: {message}")
        except asyncio.TimeoutError:
            logger.info("⏰ Listen timeout")
        except Exception as e:
            logger.error(f"❌ Listen error: {e}")
    
    async def test_session(self):
        """Test session handling"""
        logger.info("🧪 Testing session handling...")
        
        # Test 1: Get session data
        await self.send_message('get_session_data', {
            'client_id': 'python_debugger'
        })
        
        # Test 2: Join a room
        await self.send_message('join_room', {
            'room_id': 'test_room_123'
        })
        
        # Test 3: Send a message
        await self.send_message('message', {
            'room_id': 'test_room_123',
            'message': 'Hello from Python debugger!'
        })
        
        # Listen for responses
        await self.listen(10)
    
    async def close(self):
        """Close the WebSocket connection"""
        if self.websocket:
            await self.websocket.close()
            logger.info("🔌 Connection closed")

async def main():
    """Main test function"""
    debugger = WebSocketDebugger()
    
    # Try to connect
    if await debugger.connect():
        # Test session handling
        await debugger.test_session()
        
        # Close connection
        await debugger.close()
    else:
        logger.error("❌ Could not establish connection")

if __name__ == "__main__":
    asyncio.run(main()) 