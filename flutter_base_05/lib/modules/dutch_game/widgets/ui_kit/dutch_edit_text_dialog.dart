import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../utils/consts/theme_consts.dart';

/// Generic single-field text editor — adapted from
/// `assets/games-main/samples/multiplayer/lib/settings/custom_name_dialog.dart`.
///
/// Shows a scaling dialog with a single autofocused [TextField], a "Save" and
/// a "Cancel" action. Calls [onSave] with the trimmed value when the user
/// confirms (and only if it differs from [initialValue]).
Future<String?> showDutchEditTextDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? hintText,
  int maxLength = 32,
  TextInputType keyboardType = TextInputType.text,
  TextCapitalization textCapitalization = TextCapitalization.words,
  String saveLabel = 'Save',
  String cancelLabel = 'Cancel',
  ValueChanged<String>? onSave,
  String? Function(String value)? validator,
  String? semanticIdentifier,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: AppOpacity.barrier),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _DutchEditTextDialog(
        animation: animation,
        title: title,
        initialValue: initialValue ?? '',
        hintText: hintText,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        saveLabel: saveLabel,
        cancelLabel: cancelLabel,
        onSave: onSave,
        validator: validator,
        semanticIdentifier: semanticIdentifier,
      );
    },
  );
}

class _DutchEditTextDialog extends StatefulWidget {
  const _DutchEditTextDialog({
    required this.animation,
    required this.title,
    required this.initialValue,
    required this.maxLength,
    required this.keyboardType,
    required this.textCapitalization,
    required this.saveLabel,
    required this.cancelLabel,
    this.hintText,
    this.onSave,
    this.validator,
    this.semanticIdentifier,
  });

  final Animation<double> animation;
  final String title;
  final String initialValue;
  final String? hintText;
  final int maxLength;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final String saveLabel;
  final String cancelLabel;
  final ValueChanged<String>? onSave;
  final String? Function(String value)? validator;
  final String? semanticIdentifier;

  @override
  State<_DutchEditTextDialog> createState() => _DutchEditTextDialogState();
}

class _DutchEditTextDialogState extends State<_DutchEditTextDialog> {
  late final TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    if (value != widget.initialValue.trim()) {
      widget.onSave?.call(value);
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: widget.animation,
        curve: Curves.easeOutCubic,
      ),
      child: Center(
        child: Semantics(
          identifier: widget.semanticIdentifier,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: AppColors.scaffoldBackgroundColor,
              elevation: 8,
              borderRadius: AppBorderRadius.largeRadius,
              child: Padding(
                padding: AppPadding.largePadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      style: AppTextStyles.headingSmall(
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLength: widget.maxLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      textAlign: TextAlign.center,
                      textCapitalization: widget.textCapitalization,
                      keyboardType: widget.keyboardType,
                      textInputAction: TextInputAction.done,
                      style: AppTextStyles.bodyLarge(color: AppColors.white),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: AppTextStyles.bodyLarge(
                          color: AppColors.textSecondary,
                        ),
                        errorText: _validationError,
                      ),
                      onChanged: (_) {
                        if (_validationError != null) {
                          setState(() => _validationError = null);
                        }
                      },
                      onSubmitted: (_) => _handleSubmit(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            backgroundColor: Colors.transparent,
                          ),
                          child: Text(widget.cancelLabel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _handleSubmit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentColor,
                            foregroundColor: AppColors.textOnAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppBorderRadius.mediumRadius,
                            ),
                          ),
                          child: Text(widget.saveLabel),
                        ),
                      ],
                    ),
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
