import '../../../utils/consts/config.dart';

/// Route/query hints for [DutchCustomizeScreen] (`/dutch-customize`).
///
/// Used by notification deeplinks and in-screen [GoRouterState] handling.

const String kCustomizeShopPath = '/dutch-customize';

const String kCustomizeDeeplinkTabKey = 'tab';
const String kCustomizeDeeplinkSectionKey = 'section';
const String kCustomizeDeeplinkItemIdKey = 'item_id';

/// Accordion titles on the customize screen (must match [DutchCustomizeScreen]).
const String kCustomizeAccordionConsumables = 'Consumables';
const String kCustomizeAccordionCardCovers = 'Card Covers';
const String kCustomizeAccordionTable = 'Table';
const String kCustomizeAccordionMyPacks = 'My Packs';

/// Tab slug for card-back cosmetics (`category_group: card_backs` in consumables catalog).
const String kCustomizeTabSlugCardCovers = 'card_covers';

/// Example catalog `item_id` from `consumables_catalog.json` (Card Cover Ember).
const String kDeclarativeConsumableCardBackEmberId = 'card_back_ember';

/// Card cover with pack art under `app_media/media/card_back/dragon/`.
const String kDeclarativeConsumableCardBackDragonId = 'card_back_dragon';

/// `data` key: resolve shop preview URL via [consumableShopItemModalImageUrl] (same as Customize tiles).
const String kCustomizeModalImageItemIdKey = 'modal_image_item_id';

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Maps `tab` / `section` query values to an accordion title, or null if unknown.
String? resolveCustomizeAccordionTab(String? tabHint) {
  final raw = tabHint?.trim() ?? '';
  if (raw.isEmpty) return null;
  final t = raw.toLowerCase();
  switch (t) {
    case 'consumables':
    case 'consumable':
    case 'boosters':
    case 'booster':
      return kCustomizeAccordionConsumables;
    case 'card_backs':
    case 'card_back':
    case 'card_covers':
    case 'card_cover':
    case 'card covers':
    case 'card cover':
    case 'covers':
      return kCustomizeAccordionCardCovers;
    case 'table':
    case 'tables':
    case 'table_design':
    case 'table_designs':
      return kCustomizeAccordionTable;
    case 'my_packs':
    case 'my packs':
    case 'packs':
    case 'owned':
      return kCustomizeAccordionMyPacks;
  }
  final slug = _slug(raw);
  for (final title in [
    kCustomizeAccordionConsumables,
    kCustomizeAccordionCardCovers,
    kCustomizeAccordionTable,
    kCustomizeAccordionMyPacks,
  ]) {
    final ts = _slug(title);
    if (slug == ts || (slug.length >= 2 && (ts.contains(slug) || slug.contains(ts)))) {
      return title;
    }
  }
  return null;
}

/// Tab slug for a catalog `item_id` (card backs, table designs, else consumables).
String? customizeTabSlugForItemId(String itemId) {
  final id = itemId.trim();
  if (id.startsWith('card_back_')) return kCustomizeTabSlugCardCovers;
  if (id.startsWith('table_design_')) return 'table';
  if (id.startsWith('coin_booster') || id.contains('booster')) {
    return 'consumables';
  }
  return null;
}

/// Public `app_media` preview URL for a shop cosmetic (matches Customize + in-game card/table rules).
String? consumableShopItemModalImageUrl(String itemId, {int version = 1}) {
  final id = itemId.trim();
  if (id.isEmpty) return null;
  final base = Config.apiUrl.trim();
  if (base.isEmpty) return null;
  final v = version < 1 ? 1 : version;
  if (id.startsWith('table_design_')) {
    return '$base/app_media/media/table_design_overlay.webp?skinId=$id&v=$v';
  }
  if (id.startsWith('card_back_')) {
    return '$base/app_media/media/card_back.webp?skinId=$id&v=$v';
  }
  return null;
}

/// `data.deeplink` map for customize shop navigation.
Map<String, dynamic> customizeShopDeeplink({
  String? tab,
  String? itemId,
}) {
  final map = <String, dynamic>{'path': kCustomizeShopPath};
  final id = itemId?.trim();
  final tabSlug = (tab?.trim().isNotEmpty == true)
      ? tab!.trim()
      : (id != null && id.isNotEmpty ? customizeTabSlugForItemId(id) : null);
  if (tabSlug != null && tabSlug.isNotEmpty) {
    map[kCustomizeDeeplinkTabKey] = tabSlug;
  }
  if (id != null && id.isNotEmpty) {
    map[kCustomizeDeeplinkItemIdKey] = id;
  }
  return map;
}

/// Full `data` block for a customize promo global / notification (deeplink + optional modal hero).
Map<String, dynamic> customizeShopPromoData({
  required String itemId,
  String? tab,
  bool includeModalImage = true,
  int modalImageVersion = 1,
}) {
  final id = itemId.trim();
  final data = <String, dynamic>{
    'deeplink': customizeShopDeeplink(tab: tab, itemId: id),
  };
  if (includeModalImage && consumableShopItemModalImageUrl(id, version: modalImageVersion) != null) {
    data['modal_background_enabled'] = true;
    data[kCustomizeModalImageItemIdKey] = id;
  }
  return data;
}
