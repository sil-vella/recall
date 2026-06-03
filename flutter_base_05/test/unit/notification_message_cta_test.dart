import 'package:flutter_test/flutter_test.dart';

import 'package:dutch/modules/dutch_game/utils/customize_shop_route_hints.dart';
import 'package:dutch/modules/notifications_module/utils/notification_message_cta.dart';

void main() {
  group('isNotificationStoreLinkDeeplink', () {
    test('matches store_link sentinel case-insensitively', () {
      expect(isNotificationStoreLinkDeeplink('store_link'), isTrue);
      expect(isNotificationStoreLinkDeeplink('STORE_LINK'), isTrue);
      expect(isNotificationStoreLinkDeeplink(' store_link '), isTrue);
      expect(isNotificationStoreLinkDeeplink('https://play.google.com'), isFalse);
      expect(isNotificationStoreLinkDeeplink(null), isFalse);
    });
  });

  group('tryHandleNotificationData', () {
    test('returns false for non-store deeplinks without launching', () async {
      final handled = await tryHandleNotificationData({
        'deeplink': '/dutch/lobby',
      });
      expect(handled, isFalse);
    });
  });

  group('customizeShopDeeplink', () {
    test('matches global card covers broadcast shape', () {
      final map = customizeShopDeeplink(
        tab: kCustomizeTabSlugCardCovers,
        itemId: kDeclarativeConsumableCardBackEmberId,
      );
      expect(map['path'], kCustomizeShopPath);
      expect(map['tab'], 'card_covers');
      expect(map['item_id'], 'card_back_ember');
    });
  });

  group('lobbyJoinRandomSpecialEventDeeplink', () {
    test('includes lobby path, section, tab, and event_id', () {
      final map = lobbyJoinRandomSpecialEventDeeplink(
        eventId: kDeclarativeSpecialEventCardsNightId,
      );
      expect(map['path'], kLobbyDeeplinkPath);
      expect(map[kLobbyDeeplinkSectionKey], kLobbyDeeplinkSectionJoinRandom);
      expect(map[kLobbyDeeplinkJoinRandomTabKey], kLobbyDeeplinkJoinRandomTabSpecialEvents);
      expect(map[kLobbyDeeplinkEventIdKey], 'cards_night');
    });
  });
}
