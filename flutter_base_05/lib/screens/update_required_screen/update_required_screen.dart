import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/consts/theme_consts.dart';
import '../../tools/logging/logger.dart';

/// Blocking screen that shows when a mandatory app update is required
/// This screen prevents navigation away (no app bar, no drawer, no back button)
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({Key? key}) : super(key: key);

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false;
  
  String? _downloadLink;
  bool _isLaunching = false;
  bool _hasExtractedParams = false;

  @override
  void initState() {
    super.initState();
    // Don't access context-dependent widgets here
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Extract download link from route parameters after context is ready
    if (!_hasExtractedParams) {
      try {
        final state = GoRouterState.of(context);
        _downloadLink = state.uri.queryParameters['download_link'];
        _hasExtractedParams = true;
        
        if (_downloadLink == null || _downloadLink!.isEmpty) {
          _logger.warning('UpdateRequiredScreen: No download link provided', isOn: LOGGING_SWITCH);
        } else {
          _logger.info('UpdateRequiredScreen: Download link: $_downloadLink', isOn: LOGGING_SWITCH);
        }
      } catch (e) {
        _logger.error('UpdateRequiredScreen: Error extracting download link: $e', isOn: LOGGING_SWITCH);
      }
    }
  }

  Future<void> _launchDownloadLink() async {
    if (_downloadLink == null || _downloadLink!.isEmpty) {
      _logger.error('UpdateRequiredScreen: Cannot launch - no download link', isOn: LOGGING_SWITCH);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download link is not available. Please contact support.'),
            backgroundColor: AppColors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLaunching = true;
    });

    try {
      final uri = Uri.parse(_downloadLink!);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _logger.warning('UpdateRequiredScreen: Failed to launch URL', isOn: LOGGING_SWITCH);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open download link. Please try again.'),
              backgroundColor: AppColors.redAccent,
            ),
          );
        }
      } else {
        _logger.info('UpdateRequiredScreen: Successfully launched download link', isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      _logger.error('UpdateRequiredScreen: Error launching URL: $e', isOn: LOGGING_SWITCH);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening download link: $e'),
            backgroundColor: AppColors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLaunching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back navigation
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBackgroundColor,
        body: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primaryColor,
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Update Icon
                    Icon(
                      Icons.system_update,
                      size: 80,
                      color: AppColors.accentColor,
                    ),
                    const SizedBox(height: 24),
                    
                    // Title
                    Text(
                      'Update Required',
                      style: AppTextStyles.headingLarge(color: AppColors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    
                    // Message
                    Text(
                      'A new version of the app is required to continue. Please download and install the latest version.',
                      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    
                    // Download Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLaunching ? null : _launchDownloadLink,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentColor,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: _isLaunching
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.download, size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Download Update',
                                    style: AppTextStyles.buttonText,
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.accentColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Instructions:',
                            style: AppTextStyles.headingSmall(color: AppColors.accentColor),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '1. Tap the "Download Update" button above\n'
                            '2. Install the downloaded file\n'
                            '3. Open the updated app to continue',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
                          ),
                        ],
                      ),
                    ),
                    
                    // Download Link (if available, for manual copy)
                    if (_downloadLink != null && _downloadLink!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Or copy this link:',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.lightGray),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _downloadLink!,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentColor),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
