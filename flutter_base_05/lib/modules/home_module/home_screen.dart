import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/00_base/screen_base.dart';
import '../../utils/consts/theme_consts.dart';

/// widget HomeScreen - Flutter widget for UI components
///
/// A Flutter widget that provides UI functionality
///
/// Example:
/// ```dart
/// HomeScreen()
/// ```
///
class HomeScreen extends BaseScreen {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<HomeScreen> createState() => _HomeScreenState();

  @override
  String computeTitle(BuildContext context) => 'Home';
}

/// widget _HomeScreenState - Flutter widget for UI components
///
/// A Flutter widget that provides UI functionality
///
/// Example:
/// ```dart
/// _HomeScreenState()
/// ```
///
class _HomeScreenState extends BaseScreenState<HomeScreen> {
  @override
  Widget buildContent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo at top
          Padding(
            padding: const EdgeInsets.only(top: 40.0),
            child: Image.asset(
              'assets/images/logo.png',
              height: 120,
              width: 120,
            ),
          ),
          
          const SizedBox(height: 100), // Space between logo and button

          // Create Voucher button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: ElevatedButton(
              onPressed: () {
                context.push('/voucher');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Create Voucher',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 