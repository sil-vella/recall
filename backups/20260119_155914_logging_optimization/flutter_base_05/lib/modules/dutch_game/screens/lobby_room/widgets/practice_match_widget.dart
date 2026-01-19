/// # Practice Match Widget
/// 
/// This widget provides the user interface for starting a practice match in the Dutch card game.
/// It allows users to configure difficulty level before starting a practice game.
/// 
/// ## PracticeMatchWidget
/// A card-based widget that displays:
/// - Difficulty dropdown (easy, medium, hard, expert)
/// - Start Practice Match button
/// 
/// All controls are visible inline in the card (no modal needed for simplicity).
/// 
/// Note: Instructions are always disabled for practice matches (they are only used in demo matches).
/// 
/// The widget communicates with its parent through the `onStartPractice` callback,
/// passing a Map containing the selected difficulty and settings.

import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

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
  bool _isStarting = false;

  // Difficulty options
  final List<String> _difficultyOptions = [
    'easy',
    'medium',
    'hard',
    'expert',
  ];

  void _startPractice({required bool isClearAndCollect}) {
    setState(() {
      _isStarting = true;
    });

    // Prepare practice settings
    // Note: showInstructions is always false for practice matches (instructions are only used in demo matches)
    final practiceSettings = {
      'difficulty': _selectedDifficulty,
      'showInstructions': false,
      'isClearAndCollect': isClearAndCollect,
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
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Practice Match',
              style: AppTextStyles.headingSmall(),
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
            
            // Play Dutch button (Clear mode - no collection)
            Semantics(
              label: 'practice_match_clear',
              identifier: 'practice_match_clear',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isStarting ? null : () => _startPractice(isClearAndCollect: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.infoColor,
                    foregroundColor: AppColors.textOnAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.school),
                  label: _isStarting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnAccent,
                          ),
                        )
                      : const Text('Play Dutch'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Play Dutch: Clear and Collect button (Collection mode)
            Semantics(
              label: 'practice_match_collection',
              identifier: 'practice_match_collection',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isStarting ? null : () => _startPractice(isClearAndCollect: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentColor,
                    foregroundColor: AppColors.textOnAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.casino),
                  label: _isStarting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnAccent,
                          ),
                        )
                      : const Text('Play Dutch: Clear and Collect'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

