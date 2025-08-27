import 'package:recall/modules/admobs/banner/banner_ad.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../tools/logging/logger.dart';
import '../managers/app_manager.dart';
import '../managers/module_manager.dart';
import '../managers/navigation_manager.dart';
import '../../utils/consts/theme_consts.dart';
import 'drawer_base.dart';
import '../widgets/feature_slot.dart';
import '../../modules/recall_game/managers/feature_contracts.dart';
import '../../modules/recall_game/managers/feature_registry_manager.dart';
import '../widgets/state_aware_features/index.dart';
import '../managers/websockets/websocket_manager.dart';
import '../managers/websockets/websocket_events.dart';
import 'dart:async';
// Note: Do not import recall game types here to keep BaseScreen generic.

abstract class BaseScreen extends StatefulWidget {
  const BaseScreen({Key? key}) : super(key: key);

  /// Define a method to compute the title dynamically
  String computeTitle(BuildContext context);

  /// Optional method to provide actions for the app bar
  List<Widget>? getAppBarActions(BuildContext context) => null;

  /// Optional method to provide a custom app bar
  PreferredSizeWidget? getAppBar(BuildContext context) => null;

  /// Optional method to provide a floating action button
  Widget? getFloatingActionButton(BuildContext context) => null;

  /// Optional method to provide a bottom navigation bar
  Widget? getBottomNavigationBar(BuildContext context) => null;

  /// Optional method to provide a custom background
  Decoration? getBackground(BuildContext context) => null;

  /// Optional method to provide a custom content padding
  EdgeInsets? getContentPadding(BuildContext context) => null;

  /// Optional method to provide a custom content margin
  EdgeInsets? getContentMargin(BuildContext context) => null;

  /// Optional method to provide a custom content alignment
  MainAxisAlignment? getContentAlignment(BuildContext context) => null;

  /// Optional method to provide a custom content cross alignment
  CrossAxisAlignment? getContentCrossAlignment(BuildContext context) => null;

  /// Optional method to provide a custom content main axis size
  MainAxisSize? getContentMainAxisSize(BuildContext context) => null;

  @override
  BaseScreenState createState();
}

abstract class BaseScreenState<T extends BaseScreen> extends State<T> {
  late final AppManager appManager;
  final ModuleManager _moduleManager = ModuleManager();
  final Logger log = Logger();
  BannerAdModule? bannerAdModule;
  
  // WebSocket connection monitoring for global features
  StreamSubscription<ConnectionStatusEvent>? _connectionSubscription;

  /// Get the scope key for this screen's feature registry
  String get featureScopeKey => widget.runtimeType.toString();

  /// Build app bar action features using the feature slot system
  Widget buildAppBarActionFeatures(BuildContext context) {
    return FeatureSlot(
      scopeKey: featureScopeKey,
      slotId: 'app_bar_actions',
      useTemplate: false,
      contract: 'icon_action',
      iconSize: 24,
      iconPadding: const EdgeInsets.all(8),
    );
  }

  /// Register an app bar action feature
  void registerAppBarAction({
    required String featureId,
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    int priority = 100,
    Map<String, dynamic>? metadata,
  }) {
    final feature = IconActionFeatureDescriptor(
      featureId: featureId,
      slotId: 'app_bar_actions',
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      priority: priority,
      metadata: metadata,
    );
    
    FeatureRegistryManager.instance.register(
      scopeKey: featureScopeKey,
      feature: feature,
      context: context,
    );
  }

  /// Unregister an app bar action feature
  void unregisterAppBarAction(String featureId) {
    FeatureRegistryManager.instance.unregister(
      scopeKey: featureScopeKey,
      featureId: featureId,
    );
  }

  /// Clear all app bar action features
  void clearAppBarActions() {
    FeatureRegistryManager.instance.clearScope(featureScopeKey);
  }

  // Layout components with automatic theme application
  Widget buildHeader(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: AppPadding.defaultPadding,
      child: child,
    );
  }

  Widget buildContentCard(BuildContext context, {required Widget child}) {
    return Card(
      margin: widget.getContentMargin(context) ?? AppPadding.defaultPadding,
      color: AppColors.primaryColor.withOpacity(0.8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.accentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: widget.getContentPadding(context) ?? AppPadding.cardPadding,
          child: child,
        ),
      ),
    );
  }

  Widget buildListTile({
    required String title,
    String? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ListTile(
        title: Text(title, style: AppTextStyles.bodyLarge),
        subtitle: subtitle != null ? Text(subtitle, style: AppTextStyles.bodyMedium) : null,
        leading: leading,
        trailing: trailing,
        onTap: onTap,
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: AppColors.accentColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget buildRow({
    required List<Widget> children,
    MainAxisAlignment? mainAxisAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    MainAxisSize? mainAxisSize,
    bool expand = true,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: mainAxisAlignment ?? widget.getContentAlignment(context) ?? MainAxisAlignment.start,
        crossAxisAlignment: crossAxisAlignment ?? CrossAxisAlignment.center,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget buildButtonRow({
    required List<Widget> children,
    MainAxisAlignment? mainAxisAlignment,
    bool expand = true,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: mainAxisAlignment ?? widget.getContentAlignment(context) ?? MainAxisAlignment.end,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget buildExpandedRow({
    required List<Widget> children,
    MainAxisAlignment? mainAxisAlignment,
    CrossAxisAlignment? crossAxisAlignment,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: mainAxisAlignment ?? widget.getContentAlignment(context) ?? MainAxisAlignment.start,
        crossAxisAlignment: crossAxisAlignment ?? CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: children.map((child) => Expanded(child: child)).toList(),
      ),
    );
  }

  Widget buildFormField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.accentColor,
          ),
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.lightGray,
          ),
          filled: true,
          fillColor: AppColors.primaryColor.withOpacity(0.8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.accentColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.accentColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.accentColor,
              width: 1,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.redAccent,
              width: 1,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.redAccent,
              width: 1,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: AppTextStyles.bodyMedium,
      ),
    );
  }

  Widget buildLoadingIndicator() {
    return const SizedBox(
      width: double.infinity,
      child: Center(
        child: CircularProgressIndicator(
          color: AppColors.accentColor,
        ),
      ),
    );
  }

  Widget buildErrorView(String message) {
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: AppColors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: AppTextStyles.headingSmall(),
        ),
      ),
    );
  }

  Widget buildDivider() {
    return Divider(
      color: AppColors.accentColor.withOpacity(0.3),
      height: 1,
    );
  }

  Widget buildSpacer({double height = 16}) {
    return SizedBox(height: height);
  }

  @override
  void dispose() {
    // Note: State-aware features are automatically managed by StateManager
    // No need to manually clean up subscriptions or unregister features
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    appManager = Provider.of<AppManager>(context, listen: false);
    bannerAdModule = _moduleManager.getModuleByType<BannerAdModule>();

    // Trigger hooks after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Register global app bar features for this screen (ALWAYS)
      _registerGlobalAppBarFeatures();
      
      // Trigger banner hooks if banner module is available
      if (bannerAdModule != null) {
        appManager.triggerTopBannerBarHook(context);
        appManager.triggerBottomBannerBarHook(context);
        log.info('✅ Global banner bar hooks triggered.');
      } else {
        log.error("❌ BannerAdModule not found.");
      }
    });
  }

  /// Register global app bar features that appear on all screens
  void _registerGlobalAppBarFeatures() {
    log.info('🌐 Registering state-aware global app bar features for screen: ${widget.runtimeType}');
    
    // Register state-aware features using the new system
    StateAwareFeatureRegistry.registerGlobalAppBarFeatures(context);
    
    log.info('✅ State-aware global app bar features registered for screen: ${widget.runtimeType}');
  }



  @override
  Widget build(BuildContext context) {
    final navigationManager = Provider.of<NavigationManager>(context);
    final appBar = widget.getAppBar(context) ?? AppBar(
      title: Text(
        widget.computeTitle(context),
        style: AppTextStyles.headingMedium(color: AppColors.white),
      ),
      backgroundColor: AppColors.primaryColor,
      elevation: 0,
      leading: Builder(
        builder: (context) => Semantics(
          label: 'drawer_open',
          identifier: 'drawer_open',
          button: true,
          child: IconButton(
            key: const Key(CustomDrawer.drawerOpenKey),
            icon: const Icon(Icons.menu),
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      actions: [
        // Custom app bar actions from widget
        if (widget.getAppBarActions(context) != null) 
          ...widget.getAppBarActions(context)!,
        // Feature slot for dynamic app bar actions
        buildAppBarActionFeatures(context),
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      appBar: appBar,
      drawer: CustomDrawer(),
      floatingActionButton: widget.getFloatingActionButton(context),
      bottomNavigationBar: widget.getBottomNavigationBar(context),

      body: SafeArea(
        child: Container(
          decoration: widget.getBackground(context) ??
            // Temporarily disabled background image
            BoxDecoration(
              color: AppColors.primaryColor,
            ),
            // (AppBackgrounds.backgrounds.isNotEmpty
            //   ? BoxDecoration(
            //       image: DecorationImage(
            //         image: AssetImage(AppBackgrounds.backgrounds[0]),
            //         fit: BoxFit.cover,
            //         colorFilter: ColorFilter.mode(
            //           AppColors.primaryColor.withOpacity(0.7),
            //           BlendMode.darken,
            //         ),
            //       ),
            //     )
            //   : BoxDecoration(
            //       color: AppColors.primaryColor,
            //     )
            // ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                    maxHeight: double.infinity,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Global header slot, rendered just under the AppBar
                      FeatureSlot(
                        scopeKey: widget.runtimeType.toString(),
                        slotId: 'header',
                        title: 'Notices',
                      ),

                      if (bannerAdModule != null)
                        SizedBox(
                          height: 50,
                          child: Center(
                            child: bannerAdModule!.getTopBannerWidget(context),
                          ),
                        ),

                      SizedBox(
                        height: constraints.maxHeight - (bannerAdModule != null ? 100 : 0),
                        child: SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - (bannerAdModule != null ? 100 : 0),
                            ),
                            child: buildContent(context),
                          ),
                        ),
                      ),

                      if (bannerAdModule != null)
                        SizedBox(
                          height: 50,
                          child: Center(
                            child: bannerAdModule!.getBottomBannerWidget(context),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    return scaffold;
  }

  /// Abstract method to be implemented by child classes
  Widget buildContent(BuildContext context);
}

class BaseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;

  const BaseCard({
    Key? key,
    required this.child,
    this.margin,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: EdgeInsets.zero,
        color: AppColors.primaryColor.withOpacity(0.8),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppColors.accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class BaseButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isFullWidth;
  final IconData? icon;

  const BaseButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.isPrimary = true,
    this.isFullWidth = false,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? AppColors.accentColor : AppColors.primaryColor,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: AppColors.accentColor.withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                style: AppTextStyles.buttonText,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BaseTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final bool readOnly;
  final int? maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const BaseTextField({
    Key? key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.accentColor,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.lightGray,
        ),
        filled: true,
        fillColor: AppColors.primaryColor.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.accentColor,
            width: 1,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.redAccent,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.redAccent,
            width: 1,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
