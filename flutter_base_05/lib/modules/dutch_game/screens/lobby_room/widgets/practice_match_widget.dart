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
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
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
            SizedBox(height: AppPadding.defaultPadding.top),

            // Difficulty Dropdown
            Text(
              'Difficulty',
              style: AppTextStyles.label().copyWith(color: AppColors.textPrimary),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            Semantics(
              label: 'practice_match_difficulty',
              identifier: 'practice_match_difficulty',
              child: DropdownButtonFormField<String>(
                value: _selectedDifficulty,
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppPadding.defaultPadding.left,
                    vertical: AppPadding.mediumPadding.top,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    borderSide: BorderSide(color: AppColors.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    borderSide: BorderSide(color: AppColors.borderDefault),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    borderSide: BorderSide(color: AppColors.borderFocused),
                  ),
                  helperText: 'Choose AI opponent difficulty level',
                  helperStyle: AppTextStyles.caption().copyWith(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.primaryColor,
                ),
                dropdownColor: AppColors.surface,
                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                items: _difficultyOptions.map((difficulty) {
                  return DropdownMenuItem<String>(
                    value: difficulty,
                    child: Text(
                      difficulty.toUpperCase(),
                      style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnSurface),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDifficulty = value ?? 'medium';
                  });
                },
              ),
            ),

            SizedBox(height: AppPadding.defaultPadding.top),
            
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
                    backgroundColor: AppColors.accentColor,
                    foregroundColor: AppColors.textOnAccent,
                    padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
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
            SizedBox(height: AppPadding.mediumPadding.top),
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
                    padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
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

