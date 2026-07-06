import 'package:dutch/modules/dutch_game/screens/shop/widgets/cosmetic_catalog_preview.dart';
import 'package:dutch/modules/dutch_game/screens/shop/widgets/cosmetic_preview_modal.dart';
import 'package:dutch/utils/consts/theme_consts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cardBackItem = <String, dynamic>{
    'item_id': 'card_back_ember',
    'item_type': 'card_back',
    'display_name': 'Card Cover Ember',
  };

  group('cosmeticCatalogItemShortTitle', () {
    test('strips Card Cover prefix', () {
      expect(cosmeticCatalogItemShortTitle(cardBackItem), 'Ember');
    });

    test('strips Table Design prefix', () {
      expect(
        cosmeticCatalogItemShortTitle({
          'item_type': 'table_design',
          'display_name': 'Table Design Arcane',
        }),
        'Arcane',
      );
    });
  });

  group('CosmeticPreviewModal', () {
    testWidgets('shows title and close button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => CosmeticPreviewModal.show(context, item: cardBackItem),
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Ember'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byType(CosmeticCatalogPreview), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => CosmeticPreviewModal.show(context, item: cardBackItem),
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(CosmeticPreviewModal), findsNothing);
    });
  });
}
