import 'package:flutter/material.dart';
import 'dart:convert';
import '../system/00_base/screen_base.dart';
import '../utils/consts/config.dart';
import '../system/managers/websockets/websocket_manager.dart';
import '../system/models/websocket_events.dart';

class WebSocketScreen extends BaseScreen {
  const WebSocketScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'WebSocket Test';

  @override
  BaseScreenState<WebSocketScreen> createState() => _WebSocketScreenState();
}

class _WebSocketScreenState extends BaseScreenState<WebSocketScreen> {
  List<String> messages = [];
  Map<String, dynamic>? sessionData;
  String? sessionId;
  
  // Controllers for input fields
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _customMessageController = TextEditingController();

  // Helper methods to get state from WebSocketManager
  bool get isConnected => WebSocketManager.instance.isConnected;

  String get connectionStatus {
    return isConnected ? 'Connected' : 'Disconnected';
  }

  @override
  void initState() {
    super.initState();
    // Don't auto-connect - let user press connect button
    log.info('🔌 WebSocket screen initialized (no auto-connection)');
  }

  void _connect() async {
    // Check if already connected first
    if (WebSocketManager.instance.isConnected) {
      log.info('✅ WebSocket already connected');
      setState(() {
        messages.add('✅ WebSocket already connected');
      });
      return;
    }
    
    log.info('🚀 Attempting to connect to WebSocket server...');
    final success = await WebSocketManager.instance.connect();
    if (success) {
      setState(() {
        messages.add('✅ Connected to WebSocket server');
      });
    } else {
      setState(() {
        messages.add('❌ Failed to connect to WebSocket server');
      });
    }
  }

  void _disconnect() {
    log.info('🔌 Manually disconnecting WebSocket...');
    WebSocketManager.instance.disconnect();
    setState(() {
      messages.add('🔌 Disconnected from WebSocket server');
    });
  }

  void _sendMessage() async {
    final message = _customMessageController.text.trim();
    if (message.isEmpty) {
      messages.add('⚠️ Please enter a message');
      return;
    }
    
    log.info('💬 Sending WebSocket message: $message');
    final result = await WebSocketManager.instance.broadcastMessage(message);
    if (result['success'] != null) {
      messages.add('💬 Sent message: $message');
      _customMessageController.clear(); // Clear the input
    } else {
      messages.add('🚨 Failed to send message: ${result['error']}');
    }
  }

  void _sendTestMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      messages.add('⚠️ Please enter a test message');
      return;
    }
    
    log.info('🧪 Sending test WebSocket message: $message');
    final result = await WebSocketManager.instance.broadcastMessage(message);
    if (result['success'] != null) {
      messages.add('🧪 Sent test message: $message');
      _messageController.clear(); // Clear the input
    } else {
      messages.add('🚨 Failed to send test message: ${result['error']}');
    }
  }

  void _clearMessages() {
    setState(() {
      messages.clear();
    });
  }

  @override
  void dispose() {
    log.info('🔌 Disposing WebSocket screen (keeping connection alive)');
    log.info('🔍 WebSocket state before dispose: connected=${WebSocketManager.instance.isConnected}');
    
    // Don't disconnect the WebSocket manager - keep it alive for other screens
    _messageController.dispose();
    _customMessageController.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<ConnectionStatusEvent>(
      stream: WebSocketManager.instance.connectionStatus,
      builder: (context, connectionSnapshot) {
        final isConnected = connectionSnapshot.data?.status == ConnectionStatus.connected || WebSocketManager.instance.isConnected;
        
        return StreamBuilder<WebSocketEvent>(
          stream: WebSocketManager.instance.events,
          builder: (context, eventSnapshot) {
            // Handle incoming events
            if (eventSnapshot.hasData) {
              final event = eventSnapshot.data!;
              if (event is SessionDataEvent) {
                sessionData = event.sessionData;
                sessionId = event.sessionData['session_id'];
              } else if (event is MessageEvent) {
                messages.add('💬 [${event.sender}]: ${event.message}');
              } else if (event is ErrorEvent) {
                messages.add('🚨 Error: ${event.error}');
              }
            }
            
            return SingleChildScrollView(
              child: Column(
                children: [
                  // Connection Status
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: isConnected ? Colors.green : Colors.red,
                    child: Row(
                      children: [
                        Icon(
                          isConnected ? Icons.wifi : Icons.wifi_off,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isConnected ? 'Connected' : 'Disconnected',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (sessionId != null)
                          Text(
                            'ID: ${sessionId!.substring(0, 8)}...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Session Data Display
                  if (sessionData != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Session Data:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            json.encode(sessionData),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                  // Connection Controls
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Connect/Disconnect Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isConnected ? _disconnect : _connect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isConnected ? Colors.red : Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              isConnected ? 'Disconnect' : 'Connect',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Message Sending
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Send Messages',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _customMessageController,
                                      decoration: const InputDecoration(
                                        labelText: 'Custom Message',
                                        hintText: 'Enter your message',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: isConnected ? _sendMessage : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Send'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      decoration: const InputDecoration(
                                        labelText: 'Test Message',
                                        hintText: 'Quick test message',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: isConnected ? _sendTestMessage : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Send Test'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Clear Messages Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _clearMessages,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Clear Messages'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Messages List
                  Container(
                    height: 300,
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              topRight: Radius.circular(8),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.message),
                              const SizedBox(width: 8),
                              const Text(
                                'WebSocket Messages',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Text(
                                '${messages.length} messages',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              Color messageColor = Colors.grey.shade50;
                              
                              // Color code messages based on type
                              if (message.contains('✅')) messageColor = Colors.green.shade50;
                              else if (message.contains('❌') || message.contains('🚨')) messageColor = Colors.red.shade50;
                              else if (message.contains('💬')) messageColor = Colors.blue.shade50;
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: messageColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  message,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
} 