import 'package:flutter_test/flutter_test.dart';

import 'package:dutch/core/widgets/instant_message_modal.dart';
import 'package:dutch/modules/dutch_game/utils/customize_shop_route_hints.dart';
import 'package:dutch/utils/consts/config.dart';

void main() {
  group('resolveCustomizeAccordionTab', () {
    test('maps card_covers slug to Card Covers accordion', () {
      expect(
        resolveCustomizeAccordionTab(kCustomizeTabSlugCardCovers),
        kCustomizeAccordionCardCovers,
      );
    });

    test('maps consumables and table slugs', () {
      expect(resolveCustomizeAccordionTab('consumables'), kCustomizeAccordionConsumables);
      expect(resolveCustomizeAccordionTab('table_design'), kCustomizeAccordionTable);
    });
  });

  group('customizeShopDeeplink', () {
    test('includes path, tab, and catalog item_id', () {
      final map = customizeShopDeeplink(
        tab: kCustomizeTabSlugCardCovers,
        itemId: kDeclarativeConsumableCardBackEmberId,
      );
      expect(map['path'], kCustomizeShopPath);
      expect(map[kCustomizeDeeplinkTabKey], 'card_covers');
      expect(map[kCustomizeDeeplinkItemIdKey], 'card_back_ember');
    });

    test('infers card_covers tab from item_id when tab omitted', () {
      final map = customizeShopDeeplink(itemId: kDeclarativeConsumableCardBackDragonId);
      expect(map[kCustomizeDeeplinkTabKey], kCustomizeTabSlugCardCovers);
      expect(map[kCustomizeDeeplinkItemIdKey], 'card_back_dragon');
    });
  });

  group('consumableShopItemModalImageUrl', () {
    test('builds card_back preview URL from Config.apiUrl', () {
      final url = consumableShopItemModalImageUrl(kDeclarativeConsumableCardBackDragonId);
      expect(
        url,
        '${Config.apiUrl}/app_media/media/card_back.webp?skinId=card_back_dragon&v=1',
      );
    });
  });

  group('customizeShopPromoData', () {
    test('includes deeplink and modal_image_item_id for catalog item', () {
      final data = customizeShopPromoData(itemId: kDeclarativeConsumableCardBackDragonId);
      expect(data['modal_background_enabled'], true);
      expect(data[kCustomizeModalImageItemIdKey], 'card_back_dragon');
      final deeplink = data['deeplink'] as Map<String, dynamic>;
      expect(deeplink[kCustomizeDeeplinkItemIdKey], 'card_back_dragon');
    });
  });

  group('modalBackgroundUrlFromMessage', () {
    test('resolves shop preview from modal_image_item_id', () {
      final message = {
        'data': {
          'modal_background_enabled': true,
          kCustomizeModalImageItemIdKey: kDeclarativeConsumableCardBackDragonId,
        },
      };
      expect(
        modalBackgroundUrlFromMessage(message),
        '${Config.apiUrl}/app_media/media/card_back.webp?skinId=card_back_dragon&v=1',
      );
      expect(modalBackgroundEnabledFromMessage(message), true);
    });
  });
}
