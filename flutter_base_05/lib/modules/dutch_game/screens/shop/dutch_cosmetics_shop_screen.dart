import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/00_base/screen_base.dart';
import '../../../../../utils/consts/config.dart';
import '../../../../../utils/dev_logger.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../utils/consumables_catalog_bootstrap.dart';
import '../../utils/customize_shop_route_hints.dart';
import '../../../../../utils/widgets/coin_icon.dart';
import '../../../../../utils/widgets/felt_texture_widget.dart';
import '../../models/card_display_config.dart';
import '../../models/card_model.dart';
import '../game_play/utils/table_design_style_helpers.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../utils/dutch_game_play_table_style_mapping.dart';
import '../../widgets/card_widget.dart';
import '../lobby_room/widgets/collapsible_section_widget.dart';

class DutchCustomizeScreen extends BaseScreen {
  final bool equipOnly;

  const DutchCustomizeScreen({
    super.key,
    this.equipOnly = false,
  });

  @override
  String computeTitle(BuildContext context) => 'Customize';

  /// Same backdrop as lobby, leaderboard, and achievements ([main-screens-background.webp]).
  @override
  Decoration? getBackground(BuildContext context) {
    return const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/images/backgrounds/main-screens-background.webp'),
        fit: BoxFit.contain,
        alignment: Alignment.bottomRight,
      ),
    );
  }

  @override
  BaseScreenState<DutchCustomizeScreen> createState() => _DutchCustomizeScreenState();
}

class _DutchCustomizeScreenState extends BaseScreenState<DutchCustomizeScreen> {
  // Tracing shop tile previews (card back / table design show defaults).
  static const bool LOGGING_SWITCH = false;

  static const String _kAccordionMyPacks = kCustomizeAccordionMyPacks;
  static const String _kAccordionConsumables = kCustomizeAccordionConsumables;
  static const String _kAccordionCardBacks = kCustomizeAccordionCardCovers;
  static const String _kAccordionTable = kCustomizeAccordionTable;

  /// Dark scrim behind title / price only.
  static final Color _kTextScrimFill = AppColors.darkGray.withValues(alpha: 0.92);

  bool _loading = true;
  List<Map<String, dynamic>> _catalog = const [];
  Map<String, dynamic> _inventory = const {};
  String _selectedItemId = '';

  /// Accordion section open (lobby-style); consumables default.
  String? _expandedSection = _kAccordionConsumables;

  /// Last [GoRouterState.uri.query] applied for deep-link highlight (re-run when query changes).
  String? _lastCustomizeRouteQueryApplied;

  /// Raw hint from route until catalog is ready to resolve to [item_id].
  String? _pendingCustomizeHighlightHint;

  /// Accordion to expand from `tab` / `section` query (applied after catalog load).
  String? _pendingCustomizeTab;

  final Map<String, GlobalKey> _itemScrollKeys = {};

  GlobalKey _scrollKeyForItem(String id) =>
      _itemScrollKeys.putIfAbsent(id, GlobalKey.new);

  static String _slugForCustomizeHint(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// Resolve `item_id` or fuzzy [display_name] slug against the loaded shop catalog.
  String? _resolveCatalogItemId(String hint) {
    final h = hint.trim();
    if (h.isEmpty) return null;
    for (final item in _catalog) {
      final id = item['item_id']?.toString() ?? '';
      if (id == h) return id;
    }
    final hs = _slugForCustomizeHint(h);
    if (hs.length < 2) return null;
    for (final item in _catalog) {
      final id = item['item_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = _slugForCustomizeHint(item['display_name']?.toString() ?? '');
      if (name.isEmpty) continue;
      if (name == hs || name.contains(hs) || hs.contains(name)) return id;
    }
    return null;
  }

  void _captureCustomizeRouteIntent() {
    if (!mounted) return;
    Uri uri;
    try {
      uri = GoRouterState.of(context).uri;
    } catch (_) {
      return;
    }
    if (uri.path != kCustomizeShopPath) return;
    final q = uri.query;
    if (q == _lastCustomizeRouteQueryApplied) return;
    _lastCustomizeRouteQueryApplied = q;

    final tabRaw =
        uri.queryParameters[kCustomizeDeeplinkTabKey] ??
        uri.queryParameters[kCustomizeDeeplinkSectionKey];
    final tabTitle = resolveCustomizeAccordionTab(tabRaw);
    _pendingCustomizeTab = tabTitle;

    final raw = uri.queryParameters[kCustomizeDeeplinkItemIdKey] ??
        uri.queryParameters['item'] ??
        uri.queryParameters['highlight'] ??
        uri.queryParameters['consumable'];
    if (raw == null || raw.trim().isEmpty) {
      _pendingCustomizeHighlightHint = null;
      return;
    }
    _pendingCustomizeHighlightHint = raw.trim();
  }

  void _retryCustomizeRouteHintsFromUri() {
    if (!mounted) return;
    try {
      final uri = GoRouterState.of(context).uri;
      if (uri.path != kCustomizeShopPath) return;
      final hasTab = resolveCustomizeAccordionTab(
            uri.queryParameters[kCustomizeDeeplinkTabKey] ??
                uri.queryParameters[kCustomizeDeeplinkSectionKey],
          ) !=
          null;
      final hasItem = (uri.queryParameters[kCustomizeDeeplinkItemIdKey] ??
              uri.queryParameters['item'] ??
              uri.queryParameters['highlight'] ??
              uri.queryParameters['consumable'])
          ?.trim()
          .isNotEmpty ==
          true;
      if (!hasTab && !hasItem) return;
      _lastCustomizeRouteQueryApplied = null;
      _captureCustomizeRouteIntent();
      _tryApplyPendingCustomizeRouteHints();
    } catch (_) {}
  }

  void _tryApplyPendingCustomizeTab() {
    final tab = _pendingCustomizeTab;
    if (tab == null || tab.isEmpty || _loading || !mounted) return;
    _pendingCustomizeTab = null;
    setState(() => _expandedSection = tab);
  }

  void _tryApplyPendingCustomizeRouteHints() {
    _tryApplyPendingCustomizeTab();
    _tryApplyPendingCustomizeHighlight();
  }

  void _tryApplyPendingCustomizeHighlight() {
    final hint = _pendingCustomizeHighlightHint;
    if (hint == null || hint.isEmpty || _loading || !mounted) return;
    final resolved = _resolveCatalogItemId(hint);
    if (resolved == null) {
      _pendingCustomizeHighlightHint = null;
      return;
    }
    _pendingCustomizeHighlightHint = null;
    String? expandSection;
    for (final item in _catalog) {
      if (item['item_id']?.toString() == resolved) {
        final type = item['item_type']?.toString() ?? '';
        if ((type == 'card_back' || type == 'table_design') && _isOwned(item)) {
          expandSection = _kAccordionMyPacks;
        } else {
          expandSection = _accordionTitleForItem(item);
        }
        break;
      }
    }
    setState(() {
      _selectedItemId = resolved;
      if (expandSection != null) _expandedSection = expandSection;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _itemScrollKeys[resolved]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();

    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _captureCustomizeRouteIntent();
    if (!_loading) {
      _tryApplyPendingCustomizeRouteHints();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final catalog = await DutchGameHelpers.getShopCatalog();
    final inventory = await DutchGameHelpers.fetchInventory() ?? {};
    if (!mounted) return;
    if (LOGGING_SWITCH) {
      _logCatalogCosmeticDiagnostics(catalog, phase: 'after getShopCatalog');
    }
    setState(() {
      _catalog = catalog;
      _inventory = inventory;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _retryCustomizeRouteHintsFromUri();
    });
    _tryApplyPendingCustomizeRouteHints();
  }

  void _logCatalogCosmeticDiagnostics(List<Map<String, dynamic>> catalog, {required String phase}) {
    if (!LOGGING_SWITCH) return;
    var cardBacks = 0;
    var tables = 0;
    var inlineStyle = 0;
    var bootstrapStyle = 0;
    for (final item in catalog) {
      final type = item['item_type']?.toString() ?? '';
      final id = item['item_id']?.toString() ?? '';
      if (type == 'card_back') cardBacks++;
      if (type == 'table_design') tables++;
      final style = item['style'];
      if (style is Map && style.isNotEmpty) inlineStyle++;
      final boot = ConsumablesCatalogBootstrap.getStyleForItem(id);
      if (boot.isNotEmpty) bootstrapStyle++;
    }
    customlog(
      'CustomizeScreen $phase: catalog=${catalog.length} card_backs=$cardBacks '
      'table_designs=$tables inlineStyle=$inlineStyle bootstrapStyle=$bootstrapStyle '
      'bootstrapCache=${ConsumablesCatalogBootstrap.getCachedItems().length}',
    );
  }

  void _logItemPreview(Map<String, dynamic> item) {
    if (!LOGGING_SWITCH) return;
    final id = item['item_id']?.toString() ?? '';
    final type = item['item_type']?.toString() ?? '';
    if (type != 'card_back' && type != 'table_design') return;
    final inline = item['style'];
    final inlineKeys = inline is Map ? Map<String, dynamic>.from(inline).keys.join(',') : 'none';
    final boot = ConsumablesCatalogBootstrap.getStyleForItem(id);
    final bootKeys = boot.keys.join(',');
    if (type == 'card_back') {
      final url = id.isNotEmpty
          ? '${Config.apiUrl}/app_media/media/card_back.webp?skinId=$id&v=3'
          : TableDesignStyleHelpers.defaultCardBackAsset;
      customlog(
        'CustomizeScreen preview card_back: id=$id inlineStyleKeys=$inlineKeys '
        'bootstrapStyleKeys=$bootKeys imageUrl=$url',
      );
      return;
    }
    final borderStyle = TableDesignStyleHelpers.borderStyleForDesign(id);
    final borderColors = TableDesignStyleHelpers.borderColorsForDesign(id);
    final overlayNetworkUrl = TableDesignStyleHelpers.buildOverlayNetworkUrl(
      currentGameId: '',
      equippedTableDesignId: id,
      imageVersion: 1,
    );
    customlog(
      'CustomizeScreen preview table_design: id=$id inlineStyleKeys=$inlineKeys '
      'bootstrapStyleKeys=$bootKeys borderStyle=$borderStyle borderColorCount=${borderColors.length} '
      'juventus=${TableDesignStyleHelpers.isJuventusTableDesign(id)} '
      'overlayNetworkUrl=${overlayNetworkUrl ?? TableDesignStyleHelpers.defaultTableOverlayAsset}',
    );
  }

  bool _isOwned(Map<String, dynamic> item) {
    final type = item['item_type']?.toString() ?? '';
    final id = item['item_id']?.toString() ?? '';
    final cosmetics = _inventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final ownedBacks = (cosmetics['owned_card_backs'] as List<dynamic>? ?? const []).map((e) => e.toString()).toSet();
    final ownedTables = (cosmetics['owned_table_designs'] as List<dynamic>? ?? const []).map((e) => e.toString()).toSet();
    if (type == 'card_back') return ownedBacks.contains(id);
    if (type == 'table_design') return ownedTables.contains(id);
    return false;
  }

  bool _isEquipped(Map<String, dynamic> item) {
    final type = item['item_type']?.toString() ?? '';
    final id = item['item_id']?.toString() ?? '';
    final equipped = (_inventory['cosmetics'] as Map<String, dynamic>? ?? const {})['equipped'] as Map<String, dynamic>? ?? const {};
    if (type == 'card_back') return equipped['card_back_id']?.toString() == id;
    if (type == 'table_design') return equipped['table_design_id']?.toString() == id;
    return false;
  }

  Future<void> _purchase(Map<String, dynamic> item) async {
    
    final result = await DutchGameHelpers.purchaseShopItem(item['item_id']?.toString() ?? '');
    final ok = result['success'] == true;
    if (!mounted) return;

    final errorStr = (result['error']?.toString() ?? '').toLowerCase();
    final isInsufficientCoins = errorStr.contains('insufficient_coins') || errorStr.contains('insufficient coins');
    if (!ok && isInsufficientCoins) {
      final requiredCoins = int.tryParse('${result['price_coins'] ?? item['price_coins'] ?? 0}') ?? 0;
      await DutchGameHelpers.stashLastCoinPurchaseContextAndShowBuyModal(
        stash: {
          'origin': 'dutch_customize_screen',
          'item_id': item['item_id']?.toString() ?? '',
          'display_name': item['display_name']?.toString() ?? '',
        },
        requiredCoins: requiredCoins,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Purchased ${item['display_name']}' : (result['error']?.toString() ?? 'Purchase failed'))),
    );
    if (ok) _loadData();
  }

  int _readPriceCoins(Map<String, dynamic> item) {
    final p = item['price_coins'];
    if (p is int) return p;
    if (p is num) return p.round();
    return int.tryParse(p?.toString() ?? '') ?? 0;
  }

  /// Tile label without catalog category prefix (section header already shows category).
  String _itemShortTitle(Map<String, dynamic> item) {
    final raw = (item['display_name']?.toString() ?? 'Item').trim();
    if (raw.isEmpty) return 'Item';

    final type = item['item_type']?.toString() ?? '';
    if (type == 'card_back') {
      for (final prefix in const ['Card Cover ', 'Card Back ']) {
        if (raw.length > prefix.length) {
          final lower = raw.toLowerCase();
          final prefixLower = prefix.toLowerCase();
          if (lower.startsWith(prefixLower)) {
            final short = raw.substring(prefix.length).trim();
            if (short.isNotEmpty) return short;
          }
        }
      }
    } else if (type == 'table_design') {
      const prefix = 'Table Design ';
      if (raw.length > prefix.length) {
        final lower = raw.toLowerCase();
        final prefixLower = prefix.toLowerCase();
        if (lower.startsWith(prefixLower)) {
          final short = raw.substring(prefix.length).trim();
          if (short.isNotEmpty) return short;
        }
      }
    }
    return raw;
  }

  String _accordionTitleForItem(Map<String, dynamic> item) {
    final type = item['item_type']?.toString() ?? '';
    if (type == 'card_back') return _kAccordionCardBacks;
    if (type == 'table_design') return _kAccordionTable;
    return _kAccordionConsumables;
  }

  String _sectionKey(Map<String, dynamic> item) {
    final group = (item['category_group']?.toString() ?? '').trim();
    final theme = (item['category_theme']?.toString() ?? '').trim();
    if (group.isNotEmpty && theme.isNotEmpty) return '$group::$theme';
    if (group.isNotEmpty) return group;
    final type = item['item_type']?.toString() ?? '';
    if (type == 'card_back') return 'card_backs';
    if (type == 'table_design') return 'table_designs';
    return 'consumables';
  }

  /// Inner gold bar label — theme only when grouped under an accordion (no repeated "Card backs - ").
  String _sectionLabel(String key) {
    if (key.contains('::')) {
      final theme = key.split('::').last.replaceAll('_', ' ').trim();
      if (theme.isEmpty) return '';
      return '${theme[0].toUpperCase()}${theme.substring(1)}';
    }
    final txt = key.replaceAll('_', ' ').trim();
    if (txt.isEmpty) return '';
    if (txt == 'card backs') return 'Card Covers';
    return txt[0].toUpperCase() + txt.substring(1);
  }

  void _sortShopSectionKeys(List<String> keys) {
    int rank(String key) {
      if (key == 'consumables::core') return 0;
      if (key.startsWith('consumables::') || key == 'consumables') return 1;
      if (key.startsWith('card_backs::') || key == 'card_backs') return 2;
      if (key.startsWith('table_designs::') || key == 'table_designs') return 3;
      return 4;
    }

    keys.sort((a, b) {
      final cmp = rank(a).compareTo(rank(b));
      if (cmp != 0) return cmp;
      return a.compareTo(b);
    });
  }

  Map<String, List<Map<String, dynamic>>> _groupByCategory(List<Map<String, dynamic>> items) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final key = _sectionKey(item);
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    }
    for (final list in grouped.values) {
      _sortByDisplayName(list);
    }
    return grouped;
  }

  void _sortByDisplayName(List<Map<String, dynamic>> items) {
    items.sort(
      (a, b) => (a['display_name']?.toString() ?? '').compareTo(b['display_name']?.toString() ?? ''),
    );
  }

  void _handleSectionToggled(String sectionTitle) {
    setState(() {
      if (_expandedSection == sectionTitle) {
        _expandedSection = null;
      } else {
        _expandedSection = sectionTitle;
      }
    });
  }

  /// Owned card backs + table designs (purchased packs) for the My Packs section.
  List<Map<String, dynamic>> _myPackItems(List<Map<String, dynamic>> visible) {
    final out = <Map<String, dynamic>>[];
    for (final item in visible) {
      final type = item['item_type']?.toString() ?? '';
      if (type != 'card_back' && type != 'table_design') continue;
      if (!_isOwned(item)) continue;
      out.add(item);
    }
    out.sort((a, b) => (a['display_name']?.toString() ?? '').compareTo(b['display_name']?.toString() ?? ''));
    return out;
  }

  Set<String> _myPackItemIds(List<Map<String, dynamic>> myPacks) {
    return myPacks.map((e) => e['item_id']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
  }

  Future<void> _equip(Map<String, dynamic> item) async {
    
    final type = item['item_type']?.toString() ?? '';
    final slot = type == 'card_back' ? 'card_back' : 'table_design';
    final result = await DutchGameHelpers.equipCosmetic(
      slot: slot,
      cosmeticId: item['item_id']?.toString() ?? '',
    );
    final ok = result['success'] == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Using ${item['display_name']}' : (result['error']?.toString() ?? 'Use failed'))),
    );
    if (ok) _loadData();
  }

  Future<void> _unequip(String slot) async {
    
    final result = await DutchGameHelpers.equipCosmetic(
      slot: slot,
      cosmeticId: '',
    );
    final ok = result['success'] == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Unused $slot' : (result['error']?.toString() ?? 'Unuse failed'))),
    );
    if (ok) _loadData();
  }

  @override
  Widget buildContent(BuildContext context) {
    
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentColor));
    }
    final visible = _catalog.where((item) {
      final type = item['item_type']?.toString() ?? '';
      final canEquip = type == 'card_back' || type == 'table_design';
      if (widget.equipOnly && !(_isOwned(item)) && canEquip) return false;
      return true;
    }).toList();

    final myPacks = _myPackItems(visible);
    final myPackIds = _myPackItemIds(myPacks);

    final consumables = <Map<String, dynamic>>[];
    final cardBacks = <Map<String, dynamic>>[];
    final tables = <Map<String, dynamic>>[];
    for (final item in visible) {
      final id = item['item_id']?.toString() ?? '';
      final type = item['item_type']?.toString() ?? '';
      if ((type == 'card_back' || type == 'table_design') && myPackIds.contains(id)) {
        continue;
      }
      if (type == 'card_back') {
        cardBacks.add(item);
      } else if (type == 'table_design') {
        tables.add(item);
      } else {
        consumables.add(item);
      }
    }
    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _loadData,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppPadding.defaultPadding,
            children: [
              CollapsibleSectionWidget(
                title: _kAccordionMyPacks,
                icon: Icons.backpack_outlined,
                accentHeaderStyle: true,
                isExpanded: _expandedSection == _kAccordionMyPacks,
                onExpandedChanged: () => _handleSectionToggled(_kAccordionMyPacks),
                child: _myPacksAccordionContent(myPacks),
              ),
              CollapsibleSectionWidget(
                title: _kAccordionConsumables,
                icon: Icons.shopping_bag_outlined,
                isExpanded: _expandedSection == _kAccordionConsumables,
                onExpandedChanged: () => _handleSectionToggled(_kAccordionConsumables),
                child: _categorizedAccordionContent(
                  consumables,
                  emptyMessage: 'No consumables in the shop right now.',
                ),
              ),
              CollapsibleSectionWidget(
                title: _kAccordionCardBacks,
                icon: Icons.style_outlined,
                isExpanded: _expandedSection == _kAccordionCardBacks,
                onExpandedChanged: () => _handleSectionToggled(_kAccordionCardBacks),
                child: _categorizedAccordionContent(
                  cardBacks,
                  emptyMessage: 'No card covers in the shop right now.',
                ),
              ),
              CollapsibleSectionWidget(
                title: _kAccordionTable,
                icon: Icons.table_restaurant_outlined,
                isExpanded: _expandedSection == _kAccordionTable,
                onExpandedChanged: () => _handleSectionToggled(_kAccordionTable),
                child: _categorizedAccordionContent(
                  tables,
                  emptyMessage: 'No table designs in the shop right now.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Owned packs grid inside the My Packs accordion (defaults closed).
  Widget _myPacksAccordionContent(List<Map<String, dynamic>> myPacks) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppPadding.defaultPadding.left),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.widgetContainerBackground,
          borderRadius: AppBorderRadius.largeRadius,
          border: Border.all(color: AppColors.casinoBorderColor),
        ),
        child: Padding(
          padding: AppPadding.cardPadding,
          child: _shopItemGrid(
            myPacks,
            showPrice: false,
            emptyMessage: 'No packs yet — shop below.',
          ),
        ),
      ),
    );
  }

  /// Category blocks (gold title + opaque panel) inside an accordion section.
  Widget _categorizedAccordionContent(
    List<Map<String, dynamic>> items, {
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: AppPadding.defaultPadding.left),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.widgetContainerBackground,
            borderRadius: AppBorderRadius.largeRadius,
            border: Border.all(color: AppColors.casinoBorderColor),
          ),
          child: Padding(
            padding: AppPadding.cardPadding,
            child: Text(
              emptyMessage,
              style: AppTextStyles.bodySmall(color: AppColors.lightGray),
            ),
          ),
        ),
      );
    }

    final grouped = _groupByCategory(items);
    final sectionKeys = grouped.keys.toList();
    _sortShopSectionKeys(sectionKeys);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final key in sectionKeys)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppPadding.defaultPadding.left),
            child: _shopSection(
              title: _sectionLabel(key),
              child: _shopItemGrid(grouped[key]!),
            ),
          ),
      ],
    );
  }

  Widget _shopItemGrid(
    List<Map<String, dynamic>> items, {
    bool showPrice = true,
    String? emptyMessage,
  }) {
    if (items.isEmpty) {
      if (emptyMessage == null || emptyMessage.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          emptyMessage,
          style: AppTextStyles.bodySmall(color: AppColors.lightGray),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppPadding.smallPadding.left,
        mainAxisSpacing: AppPadding.smallPadding.top,
        childAspectRatio: 0.80,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildItemTile(items[index], showPrice: showPrice),
    );
  }

  Widget _textScrim({required Widget child, EdgeInsetsGeometry? padding}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kTextScrimFill,
        borderRadius: AppBorderRadius.smallRadius,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: child,
      ),
    );
  }

  Widget _priceWithCoinIcon(int coins) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CoinIcon(size: 16, color: AppColors.matchPotGold),
        const SizedBox(width: 4),
        Text(
          '$coins',
          style: AppTextStyles.caption(color: AppColors.white).copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  /// Opaque panel for a shop category — matches lobby / achievements containers.
  Widget _shopSection({required String title, required Widget child}) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.largePadding.top),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.widgetContainerBackground,
          borderRadius: AppBorderRadius.largeRadius,
          border: Border.all(color: AppColors.casinoBorderColor),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withValues(alpha: AppOpacity.shadow),
              blurRadius: AppSizes.shadowBlur,
              offset: AppSizes.shadowOffset,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppBorderRadius.largeRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(title),
              child,
            ],
          ),
        ),
      ),
    );
  }

  /// Full-width gold bar with black title ([matchPotGold] — theme-independent).
  Widget _sectionHeader(String title) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.matchPotGold,
        border: Border(
          bottom: BorderSide(color: AppColors.casinoBorderColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          title,
          style: AppTextStyles.bodyMedium(color: AppColors.black).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _tilePrimaryAction(String label, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top / 2),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentColor,
            foregroundColor: AppColors.textOnAccent,
            elevation: 3,
            shadowColor: AppColors.black.withValues(alpha: 0.45),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.smallRadius),
            textStyle: AppTextStyles.label(color: AppColors.textOnAccent).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  /// Portrait card back preview (same network/skin rules as [CardWidget]).
  Widget _centeredItemPreview(Map<String, dynamic> item) {
    final type = item['item_type']?.toString() ?? '';
    final id = item['item_id']?.toString() ?? '';
    if (LOGGING_SWITCH) {
      _logItemPreview(item);
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (type == 'card_back') {
          const aspect = 0.63;
          final maxW = math.min(92.0, c.maxWidth);
          final maxH = math.min(118.0, c.maxHeight);
          var h = maxH;
          var w = h * aspect;
          if (w > maxW) {
            w = maxW;
            h = w / aspect;
          }
          return CardWidget(
            card: const CardModel(
              cardId: 'shop_preview',
              rank: '?',
              suit: '?',
              points: 0,
              isFaceDown: true,
            ),
            dimensions: Size(w, h),
            config: const CardDisplayConfig(
              showPoints: false,
              showSpecialPower: false,
              isSelectable: false,
            ),
            showBack: true,
            ownerCardBackId: id,
          );
        }
        if (type == 'table_design') {
          final maxW = math.min(110.0, c.maxWidth);
          final maxH = math.min(104.0, c.maxHeight);
          const surfaceAspect = 1.55;
          var w = maxW;
          var h = w / surfaceAspect;
          if (h > maxH) {
            h = maxH;
            w = h * surfaceAspect;
          }
          return _miniTableDesignPreview(skinId: id, width: w, height: h);
        }
        final side = math.min(58.0, math.min(c.maxWidth, c.maxHeight) * 0.55);
        final icon = type.contains('boost') ? Icons.bolt : Icons.shopping_bag_outlined;
        return Icon(
          icon,
          size: side,
          color: AppColors.accentColor2,
        );
      },
    );
  }

  Widget _miniTableDesignPreview({required String skinId, required double width, required double height}) {
    if (LOGGING_SWITCH) {
      customlog(
        'CustomizeScreen _miniTableDesignPreview build: skinId=$skinId '
        'resolvedBorder=${TableDesignStyleHelpers.outerBorderColorForDesign(skinId)}',
      );
    }
    final tableStyle = DutchGamePlayTableStyles.forLevel(1);
    final borderColor = TableDesignStyleHelpers.outerBorderColorForDesign(skinId);
    final borderGlow = TableDesignStyleHelpers.outerBorderGlowForDesign(skinId);
    final borderColors = TableDesignStyleHelpers.borderColorsForDesign(skinId);
    final isJuventus = TableDesignStyleHelpers.isJuventusTableDesign(skinId);
    final overlayNetworkUrl = TableDesignStyleHelpers.buildOverlayNetworkUrl(
      currentGameId: '',
      equippedTableDesignId: skinId,
      imageVersion: 1,
    );
    final outerBorderW = (width * 0.04).clamp(2.0, 9.0);
    const outerR = 10.0;
    const innerR = 6.0;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          boxShadow: [
            BoxShadow(
              color: borderGlow,
              blurRadius: math.min(14.0, width * 0.18),
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(outerR),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: FeltTextureWidget(
                  backgroundColor: tableStyle.feltBackground,
                ),
              ),
              if (!isJuventus)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(outerR),
                      border: Border.all(color: borderColor, width: outerBorderW),
                    ),
                  ),
                ),
              if (isJuventus)
                Positioned.fill(
                  child: CustomPaint(
                    painter: JuventusStripeBorderPainter(
                      borderWidth: outerBorderW,
                      borderRadius: outerR,
                      stripeColors: borderColors.isEmpty
                          ? const [AppColors.black, AppColors.white]
                          : borderColors,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(outerBorderW),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(innerR),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: FeltTextureWidget(
                            backgroundColor: tableStyle.feltBackground,
                          ),
                        ),
                        Positioned.fill(
                          child: SizedBox.expand(
                            child: overlayNetworkUrl == null
                                ? TableDesignStyleHelpers.defaultTableOverlayImage()
                                : TableDesignStyleHelpers.wrapCosmeticTableDesignOverlay(
                                    Image.network(
                                      overlayNetworkUrl,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, error, __) {
                                        if (LOGGING_SWITCH) {
                                          customlog(
                                            'CustomizeScreen table overlay load failed: '
                                            'skinId=$skinId url=$overlayNetworkUrl error=$error',
                                          );
                                        }
                                        return TableDesignStyleHelpers.defaultTableOverlayImage();
                                      },
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileSecondaryAction(String label, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top / 2),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.darkGray,
            foregroundColor: AppColors.white,
            elevation: 3,
            shadowColor: AppColors.black.withValues(alpha: 0.45),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.smallRadius,
              side: const BorderSide(color: AppColors.white, width: 1.2),
            ),
            textStyle: AppTextStyles.label(color: AppColors.white).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item, {bool showPrice = true}) {
    final id = item['item_id']?.toString() ?? '';
    final type = item['item_type']?.toString() ?? '';
    final owned = _isOwned(item);
    final equipped = _isEquipped(item);
    final canEquip = type == 'card_back' || type == 'table_design';
    final selected = _selectedItemId == id;
    final priceCoins = showPrice ? _readPriceCoins(item) : 0;

    return Semantics(
      identifier: 'customize_shop_item_$id',
      child: GestureDetector(
        onTap: () => setState(() => _selectedItemId = selected ? '' : id),
        child: KeyedSubtree(
        key: _scrollKeyForItem(id),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.accentContrast,
            borderRadius: AppBorderRadius.mediumRadius,
            border: Border.all(
              color: selected ? AppColors.accentColor2 : AppColors.borderDefault,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: AppOpacity.shadow),
                blurRadius: AppSizes.shadowBlur,
                offset: AppSizes.shadowOffset,
              ),
            ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _textScrim(
                  padding: EdgeInsets.zero,
                  child: Text(
                    _itemShortTitle(item),
                    style: AppTextStyles.caption(color: AppColors.white).copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: selected ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Center(
                          child: _centeredItemPreview(item),
                        ),
                      ),
                      if (selected)
                        Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!widget.equipOnly && !owned)
                                _tilePrimaryAction('Buy', () => _purchase(item)),
                              if (canEquip && owned && !equipped)
                                _tilePrimaryAction('Use', () => _equip(item)),
                              if (canEquip && equipped)
                                _tileSecondaryAction(
                                  'Current: Deselect',
                                  () => _unequip(type == 'card_back' ? 'card_back' : 'table_design'),
                                ),
                            ],
                          )
                      else
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: showPrice
                              ? _textScrim(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  child: _priceWithCoinIcon(priceCoins),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ),
      ),
    ),
    );
  }
}

// Backward-compatible alias for existing references.
class DutchCosmeticsShopScreen extends DutchCustomizeScreen {
  const DutchCosmeticsShopScreen({super.key, super.equipOnly});
}

