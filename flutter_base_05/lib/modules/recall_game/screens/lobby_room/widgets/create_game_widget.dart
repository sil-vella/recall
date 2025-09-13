/// # Create Room Widget
/// 
/// This widget provides the user interface for creating new game rooms in the Recall card game.
/// It consists of two main components:
/// 
/// ## CreateRoomWidget
/// A card-based widget that displays a "Create New Room" button. When pressed, it opens
/// a modal bottom sheet with detailed room configuration options.
/// 
/// ## CreateRoomModal
/// A comprehensive modal form that allows users to configure all aspects of a new game room:
/// 
/// ### Room Configuration Options:
/// - **Room Name**: Required text field for the room identifier
/// - **Game Type**: Dropdown selection (classic, tournament, practice)
/// - **Permission Level**: Access control (public, private)
/// - **Password**: Optional password field for non-public rooms
/// 
/// ### Player Settings:
/// - **Max Players**: Slider control (2-10 players)
/// - **Min Players**: Slider control (2 to max players)
/// 
/// ### Game Settings:
/// - **Turn Time Limit**: Slider control (15-120 seconds per turn)
/// - **Auto-start**: Toggle to automatically start when room is full
/// 
/// ### Features:
/// - Form validation (room name is required)
/// - Dynamic UI (password field only shows for non-public rooms)
/// - Loading states during room creation
/// - Success/error feedback via SnackBar
/// - Accessibility support with Semantics identifiers for automation
/// 
/// 
/// The widget communicates with its parent through the `onCreateRoom` callback,
/// passing a Map containing all the configured room settings.

import 'package:flutter/material.dart';

class CreateRoomWidget extends StatelessWidget {
  final Function(Map<String, dynamic>) onCreateRoom;

  const CreateRoomWidget({
    Key? key,
    required this.onCreateRoom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Provider removed; button enabled state handled by parent or left enabled
    return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create New Game',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                Semantics(
                  label: 'create_room_open_modal',
                  identifier: 'create_room_open_modal',
                  button: true,
                  child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showCreateRoomModal(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Room'),
                  ),
                ),
                ),
              ],
            ),
          ),
        );
  }

  void _showCreateRoomModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CreateRoomModal(onCreateRoom: onCreateRoom),
    );
  }
}

class CreateRoomModal extends StatefulWidget {
  final Function(Map<String, dynamic>) onCreateRoom;
  
  const CreateRoomModal({
    Key? key,
    required this.onCreateRoom,
  }) : super(key: key);

  @override
  State<CreateRoomModal> createState() => _CreateRoomModalState();
}

class _CreateRoomModalState extends State<CreateRoomModal> {
  // Controllers
  final TextEditingController _passwordController = TextEditingController();
  
  // State variables
  String _selectedPermission = 'public';
  String _selectedGameType = 'classic';
  int _maxPlayers = 6;
  int _minPlayers = 2;
  int _turnTimeLimit = 30;
  bool _autoStart = true;
  bool _isCreating = false;

  // Options
  final List<String> _permissionOptions = [
    'public',
    'private'
  ];

  final List<String> _gameTypeOptions = [
    'classic',
    'tournament',
    'practice'
  ];

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _createRoom() {

    setState(() {
      _isCreating = true;
    });

    // Prepare room settings
    final roomSettings = {
      'permission': _selectedPermission,
      'gameType': _selectedGameType,
      'maxPlayers': _maxPlayers,
      'minPlayers': _minPlayers,
      'turnTimeLimit': _turnTimeLimit,
      'autoStart': _autoStart,
      'password': _passwordController.text.trim(),
    };

    // Call the parent callback with room settings
    widget.onCreateRoom(roomSettings);
    
    // Close modal and show success message
    setState(() {
      _isCreating = false;
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Game created successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    'Create New Game',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    label: 'create_room_modal_close',
                    identifier: 'create_room_modal_close',
                    button: true,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
              const Divider(),
              
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      
                      const SizedBox(height: 16),
                      
                      // Game Type
                       Semantics(
                         label: 'create_room_dropdown_game_type',
                         identifier: 'create_room_dropdown_game_type',
                         child: DropdownButtonFormField<String>(
                        value: _selectedGameType,
                        decoration: const InputDecoration(
                          labelText: 'Game Type',
                          border: OutlineInputBorder(),
                        ),
                        items: _gameTypeOptions.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedGameType = value ?? 'classic';
                          });
                        },
                       ),
                       ),
                      
                      const SizedBox(height: 16),
                      
                      // Permission Level
                       Semantics(
                         label: 'create_room_dropdown_permission',
                         identifier: 'create_room_dropdown_permission',
                         child: DropdownButtonFormField<String>(
                        value: _selectedPermission,
                        decoration: const InputDecoration(
                          labelText: 'Permission Level',
                          border: OutlineInputBorder(),
                          helperText: 'Public: Anyone can join | Private: Password required',
                        ),
                        items: _permissionOptions.map((permission) {
                          return DropdownMenuItem(
                            value: permission,
                            child: Text(permission.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPermission = value ?? 'public';
                          });
                        },
                       ),
                       ),
                      
                      const SizedBox(height: 16),
                      
                      // Password (for private rooms)
                      if (_selectedPermission != 'public') ...[
                         Semantics(
                           label: 'create_room_field_password',
                           identifier: 'create_room_field_password',
                           textField: true,
                           child: TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Room Password',
                            border: OutlineInputBorder(),
                            hintText: 'Optional password for private room',
                          ),
                          obscureText: true,
                         ),
                         ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Player Count Settings
                      const Text(
                        'Player Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Max Players
                      Row(
                        children: [
                          const Text('Max Players: '),
                          Expanded(
                             child: Semantics(
                               label: 'create_room_slider_max_players',
                               identifier: 'create_room_slider_max_players',
                               child: Slider(
                              value: _maxPlayers.toDouble(),
                              min: 2,
                              max: 10,
                              divisions: 8,
                              label: _maxPlayers.toString(),
                              onChanged: (value) {
                                setState(() {
                                  _maxPlayers = value.round();
                                  if (_minPlayers > _maxPlayers) {
                                    _minPlayers = _maxPlayers;
                                  }
                                });
                              },
                             ),
                             ),
                          ),
                          Text('${_maxPlayers}'),
                        ],
                      ),
                      
                      // Min Players
                      Row(
                        children: [
                          const Text('Min Players: '),
                          Expanded(
                             child: Semantics(
                               label: 'create_room_slider_min_players',
                               identifier: 'create_room_slider_min_players',
                               child: Slider(
                              value: _minPlayers.toDouble(),
                              min: 2,
                              max: _maxPlayers.toDouble(),
                              divisions: (_maxPlayers - 2).clamp(1, 8),
                              label: _minPlayers.toString(),
                              onChanged: (value) {
                                setState(() {
                                  _minPlayers = value.round();
                                });
                              },
                             ),
                             ),
                          ),
                          Text('${_minPlayers}'),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Game Settings
                      const Text(
                        'Game Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Turn Time Limit
                      Row(
                        children: [
                          const Text('Turn Time Limit: '),
                          Expanded(
                             child: Semantics(
                               label: 'create_room_slider_turn_time',
                               identifier: 'create_room_slider_turn_time',
                               child: Slider(
                              value: _turnTimeLimit.toDouble(),
                              min: 15,
                              max: 120,
                              divisions: 7,
                              label: '${_turnTimeLimit}s',
                              onChanged: (value) {
                                setState(() {
                                  _turnTimeLimit = value.round();
                                });
                              },
                             ),
                             ),
                          ),
                          Text('${_turnTimeLimit}s'),
                        ],
                      ),
                      
                      // Auto Start Toggle
                       Semantics(
                         label: 'create_room_switch_auto_start',
                         identifier: 'create_room_switch_auto_start',
                         child: SwitchListTile(
                        title: const Text('Auto-start when full'),
                        subtitle: const Text('Start game automatically when max players join'),
                        value: _autoStart,
                        onChanged: (value) {
                          setState(() {
                            _autoStart = value;
                          });
                        },
                       ),
                       ),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'create_room_cancel',
                      identifier: 'create_room_cancel',
                      button: true,
                      child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Semantics(
                      label: 'create_room_submit',
                      identifier: 'create_room_submit',
                      button: true,
                      child: ElevatedButton(
                      onPressed: _isCreating ? null : _createRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create Game'),
                    ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
} 