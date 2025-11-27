/// # Practice Match Widget
/// 
/// This widget provides the user interface for starting a practice match in the Recall card game.
/// It allows users to configure difficulty level and instructions display before starting a practice game.
/// 
/// ## PracticeMatchWidget
/// A card-based widget that displays:
/// - Difficulty dropdown (easy, medium, hard, expert)
/// - Instructions toggle switch
/// - Start Practice Match button
/// 
/// All controls are visible inline in the card (no modal needed for simplicity).
/// 
/// The widget communicates with its parent through the `onStartPractice` callback,
/// passing a Map containing the selected difficulty and instructions setting.

import 'package:flutter/material.dart';

class PracticeMatchWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onStartPractice;

  const PracticeMatchWidget({
    Key? key,
    required this.onStartPractice,
  }) : super(key: key);

  @override
  State<PracticeMatchWidget> createState() => _PracticeMatchWidgetState();
}

class _PracticeMatchWidgetState extends State<PracticeMatchWidget> {
  // State variables
  String _selectedDifficulty = 'medium';
  bool _showInstructions = true;
  bool _isStarting = false;

  // Difficulty options
  final List<String> _difficultyOptions = [
    'easy',
    'medium',
    'hard',
    'expert',
  ];

  void _startPractice() {
    setState(() {
      _isStarting = true;
    });

    // Prepare practice settings
    final practiceSettings = {
      'difficulty': _selectedDifficulty,
      'showInstructions': _showInstructions,
    };

    // Call the parent callback with practice settings
    widget.onStartPractice(practiceSettings);

    // Reset loading state after a delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Practice Match',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Difficulty Dropdown
            Semantics(
              label: 'practice_match_difficulty',
              identifier: 'practice_match_difficulty',
              child: DropdownButtonFormField<String>(
                value: _selectedDifficulty,
                decoration: const InputDecoration(
                  labelText: 'Difficulty',
                  border: OutlineInputBorder(),
                  helperText: 'Choose AI opponent difficulty level',
                ),
                items: _difficultyOptions.map((difficulty) {
                  return DropdownMenuItem(
                    value: difficulty,
                    child: Text(difficulty.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDifficulty = value ?? 'medium';
                  });
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Instructions Toggle
            Semantics(
              label: 'practice_match_instructions',
              identifier: 'practice_match_instructions',
              child: SwitchListTile(
                title: const Text('Show Instructions'),
                subtitle: const Text('Display game instructions during play'),
                value: _showInstructions,
                onChanged: (value) {
                  setState(() {
                    _showInstructions = value;
                  });
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Practice Button
            Semantics(
              label: 'practice_match_start',
              identifier: 'practice_match_start',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isStarting ? null : _startPractice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.school),
                  label: _isStarting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Start Practice Match'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

