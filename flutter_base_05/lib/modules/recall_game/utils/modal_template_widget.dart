import 'package:flutter/material.dart';
import '../../../utils/consts/theme_consts.dart';

/// Template Modal Widget for Recall Game
/// 
/// A reusable modal template that can be used for any type of popup:
/// - Instructions
/// - Rules
/// - Messages
/// - Confirmations
/// - Alerts
/// 
/// Features:
/// - Device-centered positioning
/// - Theme integration
/// - Customizable content
/// - Close button functionality
/// - Responsive design
class ModalTemplateWidget extends StatelessWidget {
  final String title;
  final String content;
  final IconData? icon;
  final String? closeButtonText;
  final VoidCallback? onClose;
  final bool showCloseButton;
  final bool showHeader;
  final bool showFooter;
  final Color? backgroundColor;
  final Color? textColor;
  final EdgeInsets? padding;
  final double? maxWidth;
  final double? maxHeight;
  final bool scrollable;
  final Widget? customContent;

  const ModalTemplateWidget({
    Key? key,
    required this.title,
    required this.content,
    this.icon,
    this.closeButtonText,
    this.onClose,
    this.showCloseButton = true,
    this.showHeader = true,
    this.showFooter = true,
    this.backgroundColor,
    this.textColor,
    this.padding,
    this.maxWidth,
    this.maxHeight,
    this.scrollable = true,
    this.customContent,
  }) : super(key: key);

  /// Show the modal using Flutter's official showDialog method
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String content,
    IconData? icon,
    String? closeButtonText,
    VoidCallback? onClose,
    bool showCloseButton = true,
    bool showHeader = true,
    bool showFooter = true,
    Color? backgroundColor,
    Color? textColor,
    EdgeInsets? padding,
    double? maxWidth,
    double? maxHeight,
    bool scrollable = true,
    Widget? customContent,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return ModalTemplateWidget(
          title: title,
          content: content,
          icon: icon,
          closeButtonText: closeButtonText,
          onClose: onClose ?? () => Navigator.of(context).pop(),
          showCloseButton: showCloseButton,
          showHeader: showHeader,
          showFooter: showFooter,
          backgroundColor: backgroundColor,
          textColor: textColor,
          padding: padding,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          scrollable: scrollable,
          customContent: customContent,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Material(
      color: Colors.black54, // Semi-transparent background
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? screenSize.width * 0.9, // 90% of screen width
            maxHeight: maxHeight ?? screenSize.height * 0.9, // 90% of screen height
          ),
          decoration: BoxDecoration(
            color: backgroundColor ?? Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header (optional)
              if (showHeader) _buildHeader(context),
              
              // Content area
              Flexible(
                child: _buildContent(context),
              ),
              
              // Footer (optional)
              if (showFooter) _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: AppColors.accentColor,
              size: 24,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.accentColor,
              ),
            ),
          ),
          if (showCloseButton)
                    IconButton(
                      onPressed: onClose ?? () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: AppColors.accentColor,
                      tooltip: 'Close',
                    ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (customContent != null) {
      return customContent!;
    }

    final contentWidget = Text(
      content,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        height: 1.5,
        color: textColor,
      ),
    );

    if (scrollable) {
      return SingleChildScrollView(
        padding: padding ?? const EdgeInsets.all(16),
        child: contentWidget,
      );
    } else {
      return Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: contentWidget,
      );
    }
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (showCloseButton)
            TextButton.icon(
              onPressed: onClose ?? () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              label: Text(closeButtonText ?? 'Close'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentColor,
                backgroundColor: AppColors.primaryColor,
                padding: AppPadding.cardPadding,
              ),
            ),
        ],
      ),
    );
  }
}

/// Predefined modal types for common use cases
class ModalTypes {
  /// Instructions modal
  static ModalTemplateWidget instructions({
    required String title,
    required String content,
    VoidCallback? onClose,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: Icons.help_outline,
      onClose: onClose,
    );
  }

  /// Rules modal
  static ModalTemplateWidget rules({
    required String title,
    required String content,
    VoidCallback? onClose,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: Icons.rule,
      onClose: onClose,
    );
  }

  /// Message modal
  static ModalTemplateWidget message({
    required String title,
    required String content,
    IconData? icon,
    String? closeButtonText,
    VoidCallback? onClose,
    Color? backgroundColor,
    Color? textColor,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: icon ?? Icons.info_outline,
      closeButtonText: closeButtonText,
      onClose: onClose,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  /// Success modal
  static ModalTemplateWidget success({
    required String title,
    required String content,
    VoidCallback? onClose,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: Icons.check_circle_outline,
      closeButtonText: 'OK',
      onClose: onClose,
      backgroundColor: Colors.green.shade50,
      textColor: Colors.green.shade800,
    );
  }

  /// Error modal
  static ModalTemplateWidget error({
    required String title,
    required String content,
    VoidCallback? onClose,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: Icons.error_outline,
      closeButtonText: 'OK',
      onClose: onClose,
      backgroundColor: Colors.red.shade50,
      textColor: Colors.red.shade800,
    );
  }

  /// Warning modal
  static ModalTemplateWidget warning({
    required String title,
    required String content,
    VoidCallback? onClose,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: Icons.warning_outlined,
      closeButtonText: 'OK',
      onClose: onClose,
      backgroundColor: Colors.orange.shade50,
      textColor: Colors.orange.shade800,
    );
  }

  /// Confirmation modal
  static ModalTemplateWidget confirmation({
    required String title,
    required String content,
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
  }) {
    return ModalTemplateWidget(
      title: title,
      content: content,
      icon: Icons.help_outline,
      showFooter: true,
      customContent: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              content,
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentColor,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onConfirm,
                  child: const Text('Confirm'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
