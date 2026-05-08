import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/00_base/screen_base.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../utils/widgets/felt_texture_widget.dart';
import '../../models/card_display_config.dart';
import '../../models/card_model.dart';
import '../game_play/utils/table_design_style_helpers.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../utils/dutch_game_play_table_style_mapping.dart';
import '../../widgets/card_widget.dart';

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
  static const bool LOGGING_SWITCH = false;
  /// Dark scrim behind title / price only.
  static final Color _kTextScrimFill = AppColors.darkGray.withValues(alpha: 0.92);

  /// Cosmetic overlay on felt — must match [GamePlayScreen] table overlay (`Opacity` child).
  static const double _kShopTableOverlayOpacity = 0.22;

  final Logger _logger = Logger();
  bool _loading = true;
  List<Map<String, dynamic>> _catalog = const [];
  Map<String, dynamic> _inventory = const {};
  String _selectedItemId = '';

  @override
  void initState() {
    super.initState();
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: initState equipOnly=${widget.equipOnly}');
    }
    _loadData();
  }

  Future<void> _loadData() async {
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: _loadData start');
    }
    setState(() => _loading = true);
    final catalog = await DutchGameHelpers.getShopCatalog();
    final inventory = await DutchGameHelpers.fetchInventory() ?? {};
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _inventory = inventory;
      _loading = false;
    });
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: _loadData done catalog=${_catalog.length}');
    }
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
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: purchase tap item=${item['item_id']}');
    }
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

  String _sectionLabel(String key) {
    if (key.contains('::')) {
      final parts = key.split('::');
      final group = parts.first.replaceAll('_', ' ');
      final theme = parts.last.replaceAll('_', ' ');
      return '${group[0].toUpperCase()}${group.substring(1)} - ${theme[0].toUpperCase()}${theme.substring(1)}';
    }
    final txt = key.replaceAll('_', ' ');
    return txt[0].toUpperCase() + txt.substring(1);
  }

  /// After [My Packs]: consumables core → other consumables → card backs → table designs → anything else.
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
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: equip tap item=${item['item_id']} type=${item['item_type']}');
    }
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
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: unequip tap slot=$slot');
    }
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
    if (LOGGING_SWITCH) {
      _logger.info('🎨 DutchCustomizeScreen: buildContent loading=$_loading equipOnly=${widget.equipOnly}');
    }
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

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in visible) {
      final id = item['item_id']?.toString() ?? '';
      final type = item['item_type']?.toString() ?? '';
      if ((type == 'card_back' || type == 'table_design') && myPackIds.contains(id)) {
        continue;
      }
      final key = _sectionKey(item);
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    }
    final sectionKeys = grouped.keys.toList();
    _sortShopSectionKeys(sectionKeys);

    Widget packGrid(List<Map<String, dynamic>> items) {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'No packs yet — shop below.',
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
          childAspectRatio: 0.90,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildItemTile(items[index], showPrice: false),
      );
    }

    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppPadding.defaultPadding,
        children: [
          _sectionHeader('My Packs'),
          packGrid(myPacks),
          SizedBox(height: AppPadding.largePadding.top),
          for (final section in sectionKeys) ...[
            _sectionHeader(_sectionLabel(section)),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: AppPadding.smallPadding.left,
                mainAxisSpacing: AppPadding.smallPadding.top,
                childAspectRatio: 0.90,
              ),
              itemCount: grouped[section]!.length,
              itemBuilder: (context, index) => _buildItemTile(grouped[section]![index]),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
          ],
        ],
      ),
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
        Icon(Icons.monetization_on, size: 16, color: AppColors.matchPotGold),
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

  /// Accent strip aligned with [ModalTemplateWidget] headers and achievement summary cards.
  Widget _sectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top, top: AppPadding.smallPadding.top),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accentColor,
          borderRadius: AppBorderRadius.smallRadius,
        ),
        child: Padding(
          padding: AppPadding.cardPadding,
          child: Text(
            title,
            style: AppTextStyles.headingSmall(color: AppColors.textOnAccent),
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
    return LayoutBuilder(
      builder: (context, c) {
        if (type == 'card_back') {
          const aspect = 0.63;
          final maxW = math.min(78.0, c.maxWidth);
          final maxH = math.min(102.0, c.maxHeight);
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
          final maxW = math.min(96.0, c.maxWidth);
          final maxH = math.min(90.0, c.maxHeight);
          const surfaceAspect = 1.55;
          var w = maxW;
          var h = w / surfaceAspect;
          if (h > maxH) {
            h = maxH;
            w = h * surfaceAspect;
          }
          return _miniTableDesignPreview(skinId: id, width: w, height: h);
        }
        final side = math.min(48.0, math.min(c.maxWidth, c.maxHeight) * 0.5);
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
    final tableStyle = DutchGamePlayTableStyles.forLevel(1);
    final borderColor = TableDesignStyleHelpers.outerBorderColorForDesign(skinId);
    final borderGlow = TableDesignStyleHelpers.outerBorderGlowForDesign(skinId);
    final borderColors = TableDesignStyleHelpers.borderColorsForDesign(skinId);
    final isJuventus = TableDesignStyleHelpers.isJuventusTableDesign(skinId);
    final overlayUrl = TableDesignStyleHelpers.buildOverlayUrl(
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
                          child: LayoutBuilder(
                            builder: (context, inner) {
                              final maxW = inner.maxWidth * 0.88;
                              final maxH = inner.maxHeight * 0.88;
                              return Center(
                                child: Opacity(
                                  opacity: _kShopTableOverlayOpacity,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxW,
                                      maxHeight: maxH,
                                    ),
                                    child: Image.network(
                                      overlayUrl,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.center,
                                      width: maxW,
                                      height: maxH,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.table_restaurant,
                                        size: math.min(maxW, maxH) * 0.35,
                                        color: AppColors.warmSpotlightColor.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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

    return GestureDetector(
      onTap: () => setState(() => _selectedItemId = selected ? '' : id),
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
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _textScrim(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  item['display_name']?.toString() ?? 'Item',
                  style: AppTextStyles.caption(color: AppColors.white).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  maxLines: selected ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: _centeredItemPreview(item),
                        ),
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!widget.equipOnly && !owned)
                              _tilePrimaryAction('Buy', () => _purchase(item)),
                            if (canEquip && owned && !equipped)
                              _tilePrimaryAction('Use', () => _equip(item)),
                            if (canEquip && equipped) ...[
                              _tileSecondaryAction(
                                'Unuse',
                                () => _unequip(type == 'card_back' ? 'card_back' : 'table_design'),
                              ),
                              _textScrim(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'In use',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.overline(color: AppColors.white.withValues(alpha: 0.9)),
                                ),
                              ),
                            ],
                          ],
                        ),
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
    );
  }
}

// Backward-compatible alias for existing references.
class DutchCosmeticsShopScreen extends DutchCustomizeScreen {
  const DutchCosmeticsShopScreen({super.key, super.equipOnly});
}

