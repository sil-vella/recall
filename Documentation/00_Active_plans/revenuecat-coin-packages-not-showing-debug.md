# Debug: RevenueCat coin packages not showing

**Status**: In Progress  
**Created**: 2026-04-26  
**Last Updated**: 2026-04-26

## Objective

Determine why **coin IAP packages** do not appear on the **Buy coins** screen when using **RevenueCat** on native (iOS/Android). Web uses Stripe and is out of scope for this specific issue unless the symptom is mis-attributed platform.

## Context (current behavior)

- Screen: `flutter_base_05/lib/screens/coin_purchase_screen/coin_purchase_screen.dart`
- Native path: `_loadNativeOfferings()` calls `Purchases.getOfferings()`, reads `offerings.current`, then **`availablePackages`** filtered by `_coinsForNativeProduct(p.storeProduct.identifier)` — only packages whose **store product id** exists in `_nativeStoreProductCoins` are shown.
- User-visible errors from that screen (when list ends empty):
  - **No current offering:** _“No store offering is set as current in RevenueCat.”_
  - **Current offering but no matching products:** _“No coin products in this offering match the app catalog. Check RevenueCat and product IDs.”_
- SDK / network failures set a generic load error and empty list.
- Verbose logging in this file is behind `LOGGING_SWITCH` (default `false`); toggle locally while debugging.

## Hypothesis checklist (verify in order)

1. **Platform** — Packages load only when `!kIsWeb` and iOS/Android (`_nativeIapSupported`). Confirm you are testing a **native** build, not web.
2. **No “current” offering in RevenueCat** — Dashboard: Project → Offerings → ensure an offering is marked **current** and contains the expected packages.
3. **Product ID mismatch** — App filter map `_nativeStoreProductCoins` keys must match **App Store / Play Console product ids** attached to packages in RevenueCat (and what `storeProduct.identifier` returns). Any rename in stores or RC without updating the Dart map → **filtered to empty**.
4. **RevenueCat / store configuration** — API keys, bundle id / application id alignment, products **Ready for Sale** (or valid test state), Play **license testers**, iOS **StoreKit config** / sandbox account as applicable.
5. **SDK init timing** — `RevenueCatAdapter` / `configureRevenueCatSDK()` must run before opening Buy coins; confirm `Purchases` is configured and `logIn` completed for logged-in users if required for offerings visibility.
6. **Backend alignment** — Python `REVENUECAT_COIN_PRODUCT_COINS` (verify path in `python_base_04`) should match the same product ids for post-purchase credit; mismatch does not hide UI but causes purchase/verify issues later.

## Implementation / investigation steps

- [ ] Reproduce on device/simulator with `LOGGING_SWITCH = false` (local only); log `offerings.current`, package count, raw `storeProduct.identifier` values before filter.
- [ ] Compare logged identifiers to `_nativeStoreProductCoins` keys and to RevenueCat + store console.
- [ ] In RevenueCat dashboard, confirm **current offering**, package order, and linked store products.
- [ ] Confirm `Purchases` configuration (key, user) matches the RC project that has the offerings.
- [ ] If products are intentionally under a **non-current** offering, either set it current or extend the app to load a named offering (product decision — document here if chosen).

## Current progress

- Plan created; root cause not confirmed.

## Next steps

1. Run native app → Buy coins → capture logs / screenshot of on-screen error string.
2. Cross-check RC dashboard “current” offering vs package identifiers vs Dart map.
3. After fix, revert temporary `LOGGING_SWITCH` if enabled; update **Files modified** below.

## Files modified

- _(none yet — update as debugging/fix proceeds)_

## Notes

- Empty list after successful `getOfferings()` is often **filter mismatch**, not SDK silence — compare **raw** packages vs filtered.
- Stripe/web flow on the same screen is separate; do not confuse “no packages” on web (expected to show Stripe/recommended UI) with native RC.
