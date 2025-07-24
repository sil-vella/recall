import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';
import 'dart:async';
import '../system/00_base/screen_base.dart';
import '../system/managers/websockets/websocket_manager.dart';
import '../system/managers/websockets/ws_event_manager.dart';
import '../system/managers/state_manager.dart';
import '../system/models/websocket_events.dart';

class RoomManagementScreen extends BaseScreen {
  const RoomManagementScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Room Management';

  @override
  BaseScreenState<RoomManagementScreen> createState() => _RoomManagementScreenState();
}

class _RoomManagementScreenState extends BaseScreenState<RoomManagementScreen> {
  
  // Controllers
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _allowedUsersController = TextEditingController();
  final TextEditingController _allowedRolesController = TextEditingController();
  
  // State variables - only transient UI state
  String _selectedPermission = 'public';
  List<Map<String, dynamic>> _publicRooms = [];
  List<Map<String, dynamic>> _myRooms = [];
  bool _isLoading = false;
  
  // Managers
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final WSEventManager _wsEventManager = WSEventManager.instance;
  final StateManager _stateManager = StateManager();
  
  // Permission options
  final List<String> _permissionOptions = [
    'public',
    'private', 
    'restricted',
    'owner_only'
  ];

  @override
  void initState() {
    super.initState();
    _initializeWebSocket().then((_) {
      _loadPublicRooms();
      _setupEventCallbacks();
      _initializeRoomState();
    });
  }

  Future<void> _initializeWebSocket() async {
    try {
      // Check if WebSocketManager is already connected
      if (_websocketManager.isConnected) {
        log.info("✅ WebSocket already connected");
        return;
      }
      
      // Check if we're already in the process of connecting
      if (_websocketManager.isConnecting) {
        log.info("🔄 WebSocket is already connecting, waiting...");
        return;
      }
      
      // Only try to connect if no existing connection
      log.info("🔄 No existing connection found, connecting to WebSocket server...");
      final success = await _websocketManager.connect();
      
      if (success) {
        log.info("✅ WebSocket connected successfully");
      } else {
        log.error("❌ WebSocket connection failed");
        // Don't show error snackbar - user might already be connected from another screen
        log.info("ℹ️ Assuming WebSocket is already connected from another screen");
      }
    } catch (e) {
      log.error("❌ Error initializing WebSocket: $e");
      // Don't show error snackbar - user might already be connected from another screen
      log.info("ℹ️ Assuming WebSocket is already connected from another screen");
    }
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _roomIdController.dispose();
    _allowedUsersController.dispose();
    _allowedRolesController.dispose();
    
    // Clean up event callbacks
    _wsEventManager.offEvent('room', (data) {});
    _wsEventManager.offEvent('error', (data) {});
    
    super.dispose();
  }

  Future<void> _loadPublicRooms() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // For now, we'll simulate some rooms since we need to implement room discovery
      // In a real implementation, this would come from WebSocket events
      await Future.delayed(const Duration(seconds: 1));
      
      setState(() {
        _publicRooms = [
          {
            'room_id': 'demo-room-1',
            'owner_id': 'user123',
            'permission': 'public',
            'current_size': 2,
            'max_size': 10,
            'created_at': '2024-01-15T10:30:00Z'
          },
          {
            'room_id': 'demo-room-2', 
            'owner_id': 'user456',
            'permission': 'public',
            'current_size': 1,
            'max_size': 10,
            'created_at': '2024-01-15T11:00:00Z'
          }
        ];
        _isLoading = false;
      });
    } catch (e) {
      log.error("Error loading public rooms: $e");
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to load public rooms: $e', isError: true);
    }
  }

  Future<void> _createRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      _showSnackBar('Please enter a room name', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Prepare room data based on permission type
      Map<String, dynamic> roomData = {
        'permission': _selectedPermission,
      };

      // Only add allowed users/roles for non-public rooms
      if (_selectedPermission != 'public') {
        List<String> allowedUsers = [];
        List<String> allowedRoles = [];
        
        if (_allowedUsersController.text.isNotEmpty) {
          allowedUsers = _allowedUsersController.text.split(',').map((e) => e.trim()).toList();
        }
        
        if (_allowedRolesController.text.isNotEmpty) {
          allowedRoles = _allowedRolesController.text.split(',').map((e) => e.trim()).toList();
        }
        
        roomData['allowed_users'] = allowedUsers;
        roomData['allowed_roles'] = allowedRoles;
      }

      // Create room via WebSocket manager
      log.info("🏠 Attempting to create room with data: $roomData");
      
      // Check if connected before creating room
      if (!_websocketManager.isConnected) {
        log.error("❌ Cannot create room: WebSocket not connected");
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Cannot create room: WebSocket not connected', isError: true);
        return;
      }
      
      final result = await _wsEventManager.createRoom('current_user', roomData);
      
      log.info("🏠 Create room result: $result");
      
      if (result?['success'] != null && result!['success'].toString().contains('successfully')) {
        // Use the actual room data from the server response
        final roomData = result!['data'] as Map<String, dynamic>;
        final newRoom = {
          'room_id': roomData['room_id'],
          'owner_id': 'current_user',
          'permission': _selectedPermission,
          'current_size': roomData['current_size'],
          'max_size': roomData['max_size'],
          'created_at': DateTime.now().toIso8601String(),
          'allowed_users': roomData['allowed_users'] ?? [],
          'allowed_roles': roomData['allowed_roles'] ?? [],
        };

        setState(() {
          _myRooms.add(newRoom);
          _isLoading = false;
        });

        _showSnackBar('Room created successfully!');
        _clearForm();
        
        // Note: The room_joined event will be handled by the event callback
        // which will update StateManager automatically
      } else {
        throw Exception(result?['error'] ?? 'Failed to create room');
      }
      
    } catch (e) {
      log.error("Error creating room: $e");
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to create room: $e', isError: true);
    }
  }

  Future<void> _joinRoom(String roomId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check if connected before joining room
      if (!_websocketManager.isConnected) {
        log.error("❌ Cannot join room: WebSocket not connected");
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Cannot join room: WebSocket not connected', isError: true);
        return;
      }
      
      // Join room via WebSocket event manager
      log.info("🚪 Joining room: $roomId");
      final result = await _wsEventManager.joinRoom(roomId, 'current_user');
      
      if (result?['success'] == true) {
        setState(() {
          _isLoading = false;
        });

        _showSnackBar('Joined room: $roomId');
        
        // Note: The room_joined event will be handled by the event callback
        // which will update StateManager automatically
      } else {
        throw Exception(result?['error'] ?? 'Failed to join room');
      }
      
    } catch (e) {
      log.error("Error joining room: $e");
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to join room: $e', isError: true);
    }
  }

  Future<void> _leaveRoom(String roomId) async {
    try {
      // Leave room via WebSocket event manager
      log.info("🚪 Leaving room: $roomId");
      final result = await _wsEventManager.leaveRoom(roomId);
      
      if (result?['success'] == true) {
        _showSnackBar('Left room: $roomId');
        
        // Note: The room_joined event will be handled by the event callback
        // which will update StateManager automatically
      } else {
        throw Exception(result?['error'] ?? 'Failed to leave room');
      }
      
    } catch (e) {
      log.error("Error leaving room: $e");
      _showSnackBar('Failed to leave room: $e', isError: true);
    }
  }

  void _clearForm() {
    _roomNameController.clear();
    _roomIdController.clear();
    _allowedUsersController.clear();
    _allowedRolesController.clear();
    _selectedPermission = 'public';
  }

  void _initializeRoomState() {
    // State is now managed by StateManager, no need to initialize local variables
    log.info("🏠 Room state is managed by StateManager");
  }

  void _setupEventCallbacks() {
    // Listen for room events - no setState needed as StateManager handles state
    _wsEventManager.onEvent('room', (data) {
      final action = data['action'];
      final roomId = data['roomId'];
      
      log.info("📨 Received room event: action=$action, roomId=$roomId");
      
      if (action == 'joined') {
        _showSnackBar('Successfully joined room: $roomId');
      } else if (action == 'left') {
        _showSnackBar('Left room: $roomId');
      } else if (action == 'created') {
        _showSnackBar('Room created: $roomId');
        // Note: After room creation, the user is automatically joined
        // The 'joined' event will handle updating the UI state
      }
    });

    // Listen for specific room events for better debugging
    _wsEventManager.onEvent('room_joined', (data) {
      log.info("📨 Received room_joined event: $data");
    });

    _wsEventManager.onEvent('join_room_success', (data) {
      log.info("📨 Received join_room_success event: $data");
    });

    _wsEventManager.onEvent('create_room_success', (data) {
      log.info("📨 Received create_room_success event: $data");
    });

    _wsEventManager.onEvent('room_created', (data) {
      log.info("📨 Received room_created event: $data");
    });

    // Listen for error events
    _wsEventManager.onEvent('error', (data) {
      final error = data['error'];
      _showSnackBar('Error: $error', isError: true);
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<ConnectionStatusEvent>(
      stream: _websocketManager.connectionStatus,
      builder: (context, connectionSnapshot) {
        final isConnected = connectionSnapshot.data?.status == ConnectionStatus.connected || _websocketManager.isConnected;
        final isConnecting = _websocketManager.isConnecting;
        
        return AnimatedBuilder(
          animation: _stateManager,
          builder: (context, child) {
            // Get state from StateManager
            final websocketState = _stateManager.getModuleState<Map<String, dynamic>>("websocket");
            final currentRoomId = websocketState?['currentRoomId'] as String?;
            final currentRoomInfo = websocketState?['currentRoomInfo'] as Map<String, dynamic>?;
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Connection Status
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : isConnecting ? Colors.orange : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isConnected ? Icons.wifi : isConnecting ? Icons.sync : Icons.wifi_off,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isConnected ? 'Connected' : isConnecting ? 'Connecting...' : 'Disconnected',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Create Room Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Create New Room',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          TextField(
                            controller: _roomNameController,
                            decoration: const InputDecoration(
                              labelText: 'Room Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          DropdownButtonFormField<String>(
                            value: _selectedPermission,
                            decoration: const InputDecoration(
                              labelText: 'Permission Level',
                              border: OutlineInputBorder(),
                            ),
                            items: _permissionOptions.map((permission) {
                              return DropdownMenuItem(
                                value: permission,
                                child: Text(permission.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedPermission = value!;
                              });
                            },
                          ),
                          
                          if (_selectedPermission != 'public') ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _allowedUsersController,
                              decoration: const InputDecoration(
                                labelText: 'Allowed Users (comma-separated)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            TextField(
                              controller: _allowedRolesController,
                              decoration: const InputDecoration(
                                labelText: 'Allowed Roles (comma-separated)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isConnected && !_isLoading ? _createRoom : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Create Room'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Join Room Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Join Room',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _roomIdController,
                                  decoration: const InputDecoration(
                                    labelText: 'Room ID',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: isConnected && !_isLoading ? () => _joinRoom(_roomIdController.text.trim()) : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Join'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Current Room Info
                  if (currentRoomInfo != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Current Room',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: isConnected && currentRoomId != null ? () => _leaveRoom(currentRoomId!) : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Leave'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Room ID: ${currentRoomInfo!['room_id']}'),
                            Text('Owner: ${currentRoomInfo!['owner_id']}'),
                            Text('Members: ${currentRoomInfo!['current_size']}/${currentRoomInfo!['max_size']}'),
                            Text('Permission: ${currentRoomInfo!['permission']}'),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Public Rooms Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Public Rooms',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          if (_isLoading)
                            const Center(child: CircularProgressIndicator())
                          else if (_publicRooms.isEmpty)
                            const Text('No public rooms available')
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _publicRooms.length,
                              itemBuilder: (context, index) {
                                final room = _publicRooms[index];
                                return ListTile(
                                  title: Text('Room: ${room['room_id']}'),
                                  subtitle: Text('Members: ${room['current_size']}/${room['max_size']}'),
                                  trailing: ElevatedButton(
                                    onPressed: isConnected ? () => _joinRoom(room['room_id']) : null,
                                    child: const Text('Join'),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // My Rooms Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Rooms',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          if (_myRooms.isEmpty)
                            const Text('You haven\'t created any rooms yet')
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _myRooms.length,
                              itemBuilder: (context, index) {
                                final room = _myRooms[index];
                                return ListTile(
                                  title: Text('Room: ${room['room_id']}'),
                                  subtitle: Text('Members: ${room['current_size']}/${room['max_size']}'),
                                  trailing: ElevatedButton(
                                    onPressed: isConnected ? () => _joinRoom(room['room_id']) : null,
                                    child: const Text('Join'),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
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