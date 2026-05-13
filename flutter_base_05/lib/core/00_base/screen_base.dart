import 'package:dutch/modules/admobs/ad_experience_policy.dart';
import 'package:dutch/modules/admobs/admob_trace.dart';
import 'package:dutch/modules/admobs/banner/banner_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:provider/provider.dart';
import '../managers/app_manager.dart';
import '../managers/module_manager.dart';
import '../../utils/consts/config.dart';
import '../../utils/consts/theme_consts.dart';
import 'drawer_base.dart';
import '../widgets/feature_slot.dart';
import '../../modules/dutch_game/managers/feature_contracts.dart';
import '../../modules/dutch_game/managers/feature_registry_manager.dart';
import '../widgets/state_aware_features/index.dart';
import '../widgets/instant_message_modal.dart';
import '../widgets/instant_notification_response.dart';
import '../managers/state_manager.dart';
import '../managers/navigation_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../modules/notifications_module/notifications_module.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
// Note: Do not import dutch game types here to keep BaseScreen generic.

abstract class BaseScreen extends StatefulWidget {
  const BaseScreen({Key? key}) : super(key: key);

  /// Define a method to compute the title dynamically
  String computeTitle(BuildContext context);

  /// Optional method to provide actions for the app bar
  List<Widget>? getAppBarActions(BuildContext context) => null;

  /// Optional method to provide a custom app bar
  PreferredSizeWidget? getAppBar(BuildContext context) => null;

  /// When true, the default app bar shows [kAppBarLogoAsset] at full app bar height instead of [computeTitle].
  bool get useLogoInAppBar => false;

  /// When true, the app bar feature slot (e.g. coins) is built with a stable [GlobalKey]
  /// so callers can resolve its position for overlays (e.g. coin stream animation to coins display).
  bool get useGlobalKeyForAppBarFeatureSlot => false;

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
  BannerAdModule? bannerAdModule;

  /// Drains pending `instant_ws` rows (same modal path as periodic check) when [NotificationsModule] signals new items.
  void _onPendingWsInstantQueued() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainPendingWsInstantModals();
    });
  }

  /// Stable key for the app bar feature slot when [BaseScreen.useGlobalKeyForAppBarFeatureSlot] is true.
  /// Used to resolve slot position for overlays (e.g. coin stream to coins display).
  final GlobalKey appBarFeatureSlotKey = GlobalKey();

  /// Returns the app bar feature slot key when the screen opts in, otherwise null.
  GlobalKey? get appBarFeatureSlotKeyIfUsed =>
      widget.useGlobalKeyForAppBarFeatureSlot ? appBarFeatureSlotKey : null;

  /// Get the scope key for this screen's feature registry
  String get featureScopeKey => widget.runtimeType.toString();

  /// Build app bar action features using the feature slot system
  Widget buildAppBarActionFeatures(BuildContext context) {
    return FeatureSlot(
      key: widget.useGlobalKeyForAppBarFeatureSlot ? appBarFeatureSlotKey : null,
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

  /// Register a home screen button feature (for HomeScreen only)
  void registerHomeScreenButton({
    required String featureId,
    required String text,
    required VoidCallback onTap,
    Color? backgroundColor,
    String? imagePath,
    double? height,
    EdgeInsetsGeometry? padding,
    TextStyle? textStyle,
    int priority = 100,
    Map<String, dynamic>? metadata,
  }) {
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: featureId,
      slotId: 'home_screen_buttons',
      text: text,
      onTap: onTap,
      backgroundColor: backgroundColor,
      imagePath: imagePath,
      height: height,
      padding: padding,
      textStyle: textStyle,
      priority: priority,
      metadata: metadata,
    );
    
    FeatureRegistryManager.instance.register(
      scopeKey: featureScopeKey,
      feature: feature,
      context: context,
    );
  }

  /// Unregister a home screen button feature
  void unregisterHomeScreenButton(String featureId) {
    FeatureRegistryManager.instance.unregister(
      scopeKey: featureScopeKey,
      featureId: featureId,
    );
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
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.borderDefault,
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
        title: Text(title, style: AppTextStyles.bodyLarge()),
        subtitle: subtitle != null ? Text(subtitle, style: AppTextStyles.bodyMedium()) : null,
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
          labelStyle: AppTextStyles.bodyMedium().copyWith(
            color: AppColors.accentColor,
          ),
          hintStyle: AppTextStyles.bodyMedium().copyWith(
            color: AppColors.lightGray,
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.borderDefault,
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppColors.borderDefault,
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
        style: AppTextStyles.bodyMedium(),
      ),
    );
  }

  Widget buildLoadingIndicator() {
    return SizedBox(
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
              style: AppTextStyles.bodyLarge(),
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
      color: AppColors.borderDefault,
      height: 1,
    );
  }

  Widget buildSpacer({double height = 16}) {
    return SizedBox(height: height);
  }

  @override
  void dispose() {
    _moduleManager.getModuleByType<NotificationsModule>()?.removePendingWsInstantListener(_onPendingWsInstantQueued);
    _moduleManager.getModuleByType<NotificationsModule>()?.removeInboxRefreshListener(_onInboxRefreshFromWs);
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
      
      // AdMob banner preload (native, non-premium only).
      if (!kIsWeb && bannerAdModule != null && AdExperiencePolicy.showMonetizedAds) {
        admobTrace(
          'BannerShell',
          'postFrame: firing bottom then top hooks (bannerModOk=true monetized=true)',
        );
        if (kDebugMode) {
          debugPrint(
            '[BannerShell] postFrame hooks: monetized=${AdExperiencePolicy.showMonetizedAds} '
            '${AdExperiencePolicy.monetizedAdsDebugLabel()} bannerNull=${bannerAdModule == null} '
            'topUnitLen=${Config.admobsTopBanner.trim().length} bottomUnitLen=${Config.admobsBottomBanner.trim().length}',
          );
        }
        appManager.triggerBottomBannerBarHook(context);
        appManager.triggerTopBannerBarHook(context);
      } else if (!kIsWeb && kDebugMode) {
        debugPrint(
          '[BannerShell] postFrame skip hooks: kIsWeb=$kIsWeb bannerNull=${bannerAdModule == null} '
          'monetized=${AdExperiencePolicy.showMonetizedAds} ${AdExperiencePolicy.monetizedAdsDebugLabel()}',
        );
        admobTrace(
          'BannerShell',
          'postFrame skip hooks web=$kIsWeb modNull=${bannerAdModule == null} monetized=${AdExperiencePolicy.showMonetizedAds}',
        );
      }

      // App-wide: show instant-type notification modals when unread (any screen)
      final notifMod = _moduleManager.getModuleByType<NotificationsModule>();
      notifMod?.addPendingWsInstantListener(_onPendingWsInstantQueued);
      notifMod?.addInboxRefreshListener(_onInboxRefreshFromWs);
      _checkAndShowInstantMessages();
    });
  }

  void _onInboxRefreshFromWs() {
    if (!mounted) return;
    // Bypass 15s fetch throttle so inbox_changed always pulls fresh rows from the API.
    StateManager().updateModuleState('notifications', {'lastFetchedAt': null});
    _checkAndShowInstantMessages();
  }

  /// Response handler for pending [instant_ws] rows (e.g. rematch invite — see [submitRematchInviteResponse]).
  Future<bool> Function(String messageId, String actionIdentifier)? _pendingWsOnSendResponse(
    Map<String, dynamic> msg,
  ) {
    final data = msg['data'];
    if (data is Map && data['respond_via'] == 'rematch_ws') {
      return (messageId, actionIdentifier) => submitRematchInviteResponse(
            actionIdentifier: actionIdentifier,
            messageRow: msg,
          );
    }
    if (data is Map &&
        data['source'] == 'create_room_error' &&
        data['insufficient_coins'] == true) {
      return (messageId, actionIdentifier) async {
        final aid = actionIdentifier.toLowerCase();
        if (aid == 'buy_coins') {
          NavigationManager().navigateTo('/coin-purchase');
        }
        return true;
      };
    }
    return null;
  }

  /// Unread global broadcasts (instant) first, then per-user API list for [InstantMessageModal.showUnreadInstantModals].
  List<Map<String, dynamic>> _mergeInstantModalInbox(
    NotificationsModule mod,
    List<Map<String, dynamic>> apiList,
  ) {
    final gList = mod.globalBroadcasts;
    final unreadGlobals = gList.where((m) {
      if (m['user_read'] == true) return false;
      final t = m['type']?.toString() ?? '';
      return t == kNotificationTypeInstant;
    }).toList();
    return [...unreadGlobals, ...apiList];
  }

  /// Handles [message.data] for global notification CTAs: in-app navigation with optional query params.
  ///
  /// Supported shapes:
  /// - **String** [deeplink]: `"/dutch/lobby?section=join_random&table=city"` or plain `"/path"`.
  ///   Optional [deeplink_query] map is merged into query (values stringified).
  /// - **Map** [deeplink]: `{"path": "/dutch/lobby", "section": "join_random", "table": "city"}` — keys other
  ///   than `path` / `route` become query parameters.
  /// - **Flat** alternative: [deeplink_path] string + optional [deeplink_query] map (no [deeplink] key).
  Future<void> _deeplinkFromGlobalMessage(Map<String, dynamic> message) async {
    final data = message['data'];
    if (data is! Map) return;

    String? path;
    Map<String, dynamic>? query;

    final rawDeeplink = data['deeplink'];
    if (rawDeeplink is Map) {
      final m = Map<String, dynamic>.from(rawDeeplink);
      path = (m.remove('path') ?? m.remove('route'))?.toString().trim();
      query = m.map((k, v) => MapEntry(k.toString(), v));
    } else if (rawDeeplink is String) {
      final link = rawDeeplink.trim();
      if (link.startsWith('http')) {
        final uri = Uri.tryParse(link);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      if (link.startsWith('/')) {
        final uri = Uri.parse('https://_._$link');
        path = uri.path;
        if (uri.queryParameters.isNotEmpty) {
          query = Map<String, dynamic>.from(uri.queryParameters);
        }
      }
    }

    if (path == null || path.isEmpty) {
      final flat = data['deeplink_path']?.toString().trim();
      if (flat != null && flat.isNotEmpty) {
        path = flat;
      }
      final dqFlat = data['deeplink_query'];
      if (dqFlat is Map && dqFlat.isNotEmpty) {
        query ??= {};
        dqFlat.forEach((k, v) {
          query![k.toString()] = v;
        });
      }
    }

    final extra = data['deeplink_query'];
    if (extra is Map && extra.isNotEmpty) {
      query ??= {};
      extra.forEach((k, v) {
        query![k.toString()] = v;
      });
    }

    if (path == null || path.isEmpty) return;
    if (!path.startsWith('/')) return;

    NavigationManager().navigateTo(
      path,
      parameters: query?.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  /// Shows queued `instant_ws` modals (rematch invite, etc.) using the same path as the rest of the instant system.
  Future<void> _drainPendingWsInstantModals() async {
    if (!mounted) return;
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login');
    if (loginState?['isLoggedIn'] != true) return;
    final mod = _moduleManager.getModuleByType<NotificationsModule>();
    if (mod == null) return;
    final pendingWs = mod.takePendingWsInstants();
    for (final msg in pendingWs) {
      if (!mounted) break;
      await InstantMessageModal.show(
        context,
        message: msg,
        onDismiss: () {},
        onSendResponse: _pendingWsOnSendResponse(msg),
        onMarkAsRead: null,
      );
    }
  }

  /// Fetches messages (throttled per call), then shows modals for unread notifications with type 'instant'.
  /// Also drains pending ws_instant_notification payloads from the Dart backend and shows them.
  /// Called on screen enter and periodically via timer so instant notifications appear without requiring navigation.
  void _checkAndShowInstantMessages() async {
    if (!mounted) return;
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login');
    if (loginState?['isLoggedIn'] != true) return;
    final mod = _moduleManager.getModuleByType<NotificationsModule>();
    if (mod == null) return;
    await _drainPendingWsInstantModals();
    if (!mounted) return;
    final state = StateManager().getModuleState<Map<String, dynamic>>('notifications');
    final lastFetched = state?['lastFetchedAt']?.toString();
    final shouldFetch = lastFetched == null ||
        (DateTime.now().difference(DateTime.tryParse(lastFetched) ?? DateTime.now()).inSeconds > 15);
    List<Map<String, dynamic>> list;
    if (shouldFetch) {
      list = await mod.fetchMessages();
    } else {
      list = mod.lastMessages;
    }
    if (!mounted) return;
    final api = _moduleManager.getModuleByType<ConnectionsApiModule>();
    final combined = _mergeInstantModalInbox(mod, list);
    await InstantMessageModal.showUnreadInstantModals(
      context,
      messages: combined,
      onMarkAsRead: (id) async {
        final sid = id.toString();
        if (sid.startsWith('glob_')) {
          await mod.markGlobalBroadcastsRead([sid]);
        } else {
          await mod.markAsRead([sid]);
        }
      },
      onSendResponse: api == null
          ? null
          : (String messageId, String actionIdentifier) async {
              final message = combined
                  .cast<Map<String, dynamic>>()
                  .where((m) => m['id']?.toString() == messageId)
                  .firstOrNull ??
                  <String, dynamic>{};
              if (message['origin']?.toString() == 'global') {
                await _deeplinkFromGlobalMessage(message);
                return true;
              }
              return submitInstantNotificationResponse(
                api: api,
                mod: mod,
                messageId: messageId,
                actionIdentifier: actionIdentifier,
                context: context,
                messageRow: message,
              );
            },
    );
  }

  /// Register global app bar features that appear on all screens
  void _registerGlobalAppBarFeatures() {
    // Register state-aware features using the new system
    StateAwareFeatureRegistry.registerGlobalAppBarFeatures(context);
  }



  /// Asset path for app bar logo (used when [BaseScreen.useLogoInAppBar] is true).
  static const String kAppBarLogoAsset = 'assets/images/logo_icon.webp';

  @override
  Widget build(BuildContext context) {
    final appBar = widget.getAppBar(context) ?? AppBar(
      title: widget.useLogoInAppBar
          ? SizedBox(
              height: kToolbarHeight,
              child: Image.asset(
                kAppBarLogoAsset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  widget.computeTitle(context),
                  style: AppTextStyles.headingMedium(color: AppColors.white),
                ),
              ),
            )
          : Text(
              widget.computeTitle(context),
              style: AppTextStyles.headingMedium(color: AppColors.white),
            ),
      backgroundColor: AppColors.accentContrast,
      elevation: 0,
      centerTitle: false,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.scaffoldBackgroundColor,
                      AppColors.scaffoldDeepPlumColor,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: widget.getBackground(context) ?? const BoxDecoration(),
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
                    return ListenableBuilder(
                      listenable: StateManager(),
                      builder: (context, _) {
                        // TEMP: snack-bar reserved strip disabled — re-enable [totalBottomSpace] + [SizedBox] below if needed.
                        final monetized = AdExperiencePolicy.showMonetizedAds;
                        final topBannerHeight = kIsWeb
                            ? 0.0
                            : (monetized &&
                                    bannerAdModule != null &&
                                    Config.admobsTopBanner.trim().isNotEmpty
                                ? 50.0
                                : 0.0);

                        final bottomBannerHeight = kIsWeb
                            ? 0.0
                            : (monetized &&
                                    bannerAdModule != null &&
                                    Config.admobsBottomBanner.trim().isNotEmpty
                                ? 50.0
                                : 0.0);

                        if (kDebugMode && !kIsWeb) {
                          debugPrint(
                            '[BannerShell] body layout maxW=${constraints.maxWidth.toStringAsFixed(0)} '
                            'maxH=${constraints.maxHeight.toStringAsFixed(0)} topH=$topBannerHeight bottomH=$bottomBannerHeight '
                            'monetized=$monetized modNull=${bannerAdModule == null} '
                            '${AdExperiencePolicy.monetizedAdsDebugLabel()}',
                          );
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FeatureSlot(
                              scopeKey: widget.runtimeType.toString(),
                              slotId: 'header',
                              title: 'Notices',
                            ),

                            if (topBannerHeight > 0)
                              SizedBox(
                                height: topBannerHeight,
                                child: Center(
                                  child: bannerAdModule!.getTopBannerWidget(context),
                                ),
                              ),

                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, contentConstraints) {
                                  return buildContent(context);
                                },
                              ),
                            ),

                            if (bottomBannerHeight > 0)
                              SizedBox(
                                height: bottomBannerHeight,
                                child: Center(
                                  child: bannerAdModule!.getBottomBannerWidget(context),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            ],
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
        color: AppColors.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppColors.borderDefault,
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
              color: AppColors.borderDefault,
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
                style: AppTextStyles.buttonText(),
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
      style: AppTextStyles.bodyMedium(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTextStyles.bodyMedium().copyWith(
          color: AppColors.accentColor,
        ),
        hintStyle: AppTextStyles.bodyMedium().copyWith(
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
