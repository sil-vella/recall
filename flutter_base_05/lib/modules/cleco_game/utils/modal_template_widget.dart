import 'package:flutter/material.dart';
import '../../../utils/consts/theme_consts.dart';

/// Template Modal Widget for Cleco Game
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
    final modalBackgroundColor = backgroundColor ?? AppColors.card;
    
    return Material(
      color: AppColors.black.withOpacity(AppOpacity.barrier), // Semi-transparent background
      child: Center(
        child: Material(
          color: Colors.transparent, // Transparent Material to avoid theme interference
        child: Container(
            margin: EdgeInsets.all(AppSizes.modalMargin),
          constraints: BoxConstraints(
              maxWidth: maxWidth ?? screenSize.width * AppSizes.modalMaxWidthPercent,
              maxHeight: maxHeight ?? screenSize.height * AppSizes.modalMaxHeightPercent,
          ),
          decoration: BoxDecoration(
              color: modalBackgroundColor, // Use white card background for better text visibility
              borderRadius: AppBorderRadius.largeRadius,
            boxShadow: [
              BoxShadow(
                  color: AppColors.black.withOpacity(AppOpacity.shadow),
                  blurRadius: AppSizes.shadowBlur,
                  offset: AppSizes.shadowOffset,
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: AppPadding.defaultPadding,
      decoration: BoxDecoration(
        color: AppColors.cardVariant, // Use theme-aware subtle background
        borderRadius: AppBorderRadius.only(
          topLeft: AppBorderRadius.large,
          topRight: AppBorderRadius.large,
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: AppColors.accentColor,
              size: AppSizes.iconMedium,
            ),
            SizedBox(width: AppPadding.smallPadding.left),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.headingSmall(
                color: AppColors.accentColor,
              ),
            ),
          ),
          if (showCloseButton)
                    IconButton(
                      onPressed: onClose ?? () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.close,
                      color: AppColors.accentColor,
              ),
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
      style: AppTextStyles.bodyMedium(
        color: textColor ?? AppColors.textOnCard,
      ).copyWith(
        height: 1.5,
      ),
    );

    if (scrollable) {
      return SingleChildScrollView(
        padding: padding ?? AppPadding.defaultPadding,
        child: contentWidget,
      );
    } else {
      return Padding(
        padding: padding ?? AppPadding.defaultPadding,
        child: contentWidget,
      );
    }
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: AppPadding.defaultPadding,
      decoration: BoxDecoration(
        color: AppColors.cardVariant, // Use theme-aware subtle background
        borderRadius: AppBorderRadius.only(
          bottomLeft: AppBorderRadius.large,
          bottomRight: AppBorderRadius.large,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (showCloseButton)
            TextButton.icon(
              onPressed: onClose ?? () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.close,
                color: AppColors.textOnAccent,
              ),
              label: Text(
                closeButtonText ?? 'Close',
                style: AppTextStyles.buttonText(
                  color: AppColors.textOnAccent,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textOnAccent,
                backgroundColor: AppColors.accentColor,
                padding: AppPadding.cardPadding,
                shape: RoundedRectangleBorder(
                  borderRadius: AppBorderRadius.smallRadius,
                ),
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
      backgroundColor: AppColors.successColor.withOpacity(AppOpacity.subtle),
      textColor: AppColors.successColor,
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
      backgroundColor: AppColors.errorColor.withOpacity(AppOpacity.subtle),
      textColor: AppColors.errorColor,
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
      backgroundColor: AppColors.warningColor.withOpacity(AppOpacity.subtle),
      textColor: AppColors.warningColor,
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
        padding: AppPadding.defaultPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              content,
              style: AppTextStyles.bodyMedium(
                color: AppColors.textOnCard,
              ).copyWith(
                height: 1.5,
              ),
            ),
            SizedBox(height: AppPadding.largePadding.top),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.buttonText(
                      color: AppColors.accentColor,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentColor,
                  ),
                ),
                SizedBox(width: AppPadding.smallPadding.left),
                ElevatedButton(
                  onPressed: onConfirm,
                  child: Text(
                    'Confirm',
                    style: AppTextStyles.buttonText(
                      color: AppColors.textOnAccent,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentColor,
                    foregroundColor: AppColors.textOnAccent,
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
