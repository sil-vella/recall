import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../utils/consts/config.dart';
import '../../../../../../utils/consts/theme_consts.dart';
import '../../../../../../utils/dev_logger.dart';
import '../../../../../../utils/widgets/felt_texture_widget.dart';
import '../../../models/card_display_config.dart';
import '../../../models/card_model.dart';
import '../../../utils/consumables_catalog_bootstrap.dart';
import '../../../utils/dutch_game_play_table_style_mapping.dart';
import '../../../widgets/card_widget.dart';
import '../../game_play/utils/table_design_style_helpers.dart';

const double kCardBackPreviewAspect = 0.63;
const double kTableDesignPreviewAspect = 1.55;

enum CosmeticPreviewSize { thumbnail, modal }

/// Tile label without catalog category prefix (section header already shows category).
String cosmeticCatalogItemShortTitle(Map<String, dynamic> item) {
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

/// Catalog preview for card covers and table designs (thumbnail or modal size).
class CosmeticCatalogPreview extends StatelessWidget {
  const CosmeticCatalogPreview({
    super.key,
    required this.item,
    this.size = CosmeticPreviewSize.thumbnail,
  });

  final Map<String, dynamic> item;
  final CosmeticPreviewSize size;

  static const bool LOGGING_SWITCH = false;

  @override
  Widget build(BuildContext context) {
    final type = item['item_type']?.toString() ?? '';
    final id = item['item_id']?.toString() ?? '';
    if (LOGGING_SWITCH) {
      _logItemPreview(item);
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (type == 'card_back') {
          final bounds = _cardBackBounds(c.maxWidth, c.maxHeight, context);
          return CardWidget(
            card: const CardModel(
              cardId: 'shop_preview',
              rank: '?',
              suit: '?',
              points: 0,
              isFaceDown: true,
            ),
            dimensions: Size(bounds.width, bounds.height),
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
          final bounds = _tableDesignBounds(c.maxWidth, c.maxHeight, context);
          return _TableDesignCatalogPreview(
            skinId: id,
            width: bounds.width,
            height: bounds.height,
          );
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

  Size _cardBackBounds(double maxWidth, double maxHeight, BuildContext context) {
    if (size == CosmeticPreviewSize.thumbnail) {
      final capW = math.min(92.0, maxWidth);
      final capH = math.min(118.0, maxHeight);
      var h = capH;
      var w = h * kCardBackPreviewAspect;
      if (w > capW) {
        w = capW;
        h = w / kCardBackPreviewAspect;
      }
      return Size(w, h);
    }

    final screen = MediaQuery.sizeOf(context);
    final capW = math.min(screen.width * 0.55, 300.0);
    final capH = screen.height * 0.72;
    var w = math.min(capW, maxWidth);
    var h = w / kCardBackPreviewAspect;
    if (h > capH || h > maxHeight) {
      h = math.min(capH, maxHeight);
      w = h * kCardBackPreviewAspect;
    }
    return Size(w, h);
  }

  Size _tableDesignBounds(double maxWidth, double maxHeight, BuildContext context) {
    if (size == CosmeticPreviewSize.thumbnail) {
      final capW = math.min(110.0, maxWidth);
      final capH = math.min(104.0, maxHeight);
      var w = capW;
      var h = w / kTableDesignPreviewAspect;
      if (h > capH) {
        h = capH;
        w = h * kTableDesignPreviewAspect;
      }
      return Size(w, h);
    }

    final screen = MediaQuery.sizeOf(context);
    final capW = math.min(screen.width * 0.88, 560.0);
    final capH = screen.height * 0.50;
    var w = math.min(capW, maxWidth);
    var h = w / kTableDesignPreviewAspect;
    if (h > capH || h > maxHeight) {
      h = math.min(capH, maxHeight);
      w = h * kTableDesignPreviewAspect;
    }
    return Size(w, h);
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
        'CosmeticCatalogPreview card_back: id=$id inlineStyleKeys=$inlineKeys '
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
      'CosmeticCatalogPreview table_design: id=$id inlineStyleKeys=$inlineKeys '
      'bootstrapStyleKeys=$bootKeys borderStyle=$borderStyle borderColorCount=${borderColors.length} '
      'juventus=${TableDesignStyleHelpers.isJuventusTableDesign(id)} '
      'overlayNetworkUrl=${overlayNetworkUrl ?? TableDesignStyleHelpers.defaultTableOverlayAsset}',
    );
  }
}

class _TableDesignCatalogPreview extends StatelessWidget {
  const _TableDesignCatalogPreview({
    required this.skinId,
    required this.width,
    required this.height,
  });

  final String skinId;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (CosmeticCatalogPreview.LOGGING_SWITCH) {
      customlog(
        'CosmeticCatalogPreview _TableDesignCatalogPreview: skinId=$skinId '
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
                                        if (CosmeticCatalogPreview.LOGGING_SWITCH) {
                                          customlog(
                                            'CosmeticCatalogPreview table overlay load failed: '
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
}
