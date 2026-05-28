# Coin catalog — single source of truth (Play, App Store, Stripe)

All **native store product IDs**, **coin amounts**, **Premium subscription IDs**, and **subscriber bonus** live in one JSON file. Flutter and Python read the same path; App Store Connect and Google Play Console must use matching product IDs.

## File

[`flutter_base_05/assets/dutch_coin_catalog.json`](../../flutter_base_05/assets/dutch_coin_catalog.json)  
**Schema version:** `3` (as of 2026-05-26)

## Loaders

| Runtime | Module |
|---------|--------|
| Flutter | [`flutter_base_05/lib/utils/coin_catalog.dart`](../../flutter_base_05/lib/utils/coin_catalog.dart) |
| Python | [`python_base_04/utils/coin_catalog.py`](../../python_base_04/utils/coin_catalog.py) |

## JSON sections

| Key | Purpose |
|-----|---------|
| `in_app_products` | **Product ID → coin count** (authoritative for Play + App Store consumables) |
| `store_recommended_packages` | UI rows: `product_id`, `label`, `description`, `isPopular` (must match `in_app_products`) |
| `play_recommended_packages` | **Legacy** — code falls back if `store_recommended_packages` is missing |
| `premium_subscription` | Play subscription SKU + **App Store** subscription product IDs under `base_plans` |
| `subscriber_coin_bonus_percent` | Premium +11% coins (server applies on verify) |
| `stripe_packages` | Web Stripe only (`starter`, `casual`, … + `stripe_price_env`) |
| `recommended_ui_packages` | Web/fallback display prices (`$0.99`, …) — not store product IDs |

## Product IDs (copy into store consoles)

### Consumables (coin packs)

| Product ID | Coins |
|------------|------:|
| `coins_100` | 100 |
| `coins_300` | 300 |
| `coin_500` | 500 |
| `coins_700` | 700 |
| `coins_1500` | 1500 |
| `coins_3500` | 3500 |

### Premium subscriptions

| Platform | ID | Role |
|----------|-----|------|
| Google Play | `premium_subscription` | Subscription SKU |
| Google Play | `premium-auto-renew-monthly` | Base plan |
| Google Play | `premium-auto-renew-yearly` | Base plan |
| App Store | `premium_auto_renew_monthly` | Auto-renewable, 1 month |
| App Store | `premium_auto_renew_yearly` | Auto-renewable, 1 year |

## Flutter API (after `CoinCatalog.ensureLoaded()`)

- `CoinCatalog.inAppProducts`
- `CoinCatalog.storeRecommendedPackages` — use for StoreKit / Play
- `CoinCatalog.playRecommendedPackages` — alias of `storeRecommendedPackages`
- `CoinCatalog.premiumSubscriptionProductId` — Play only (`premium_subscription`)
- `CoinCatalog.premiumBasePlanMonthly` / `premiumBasePlanYearly` — Play base plan IDs
- `CoinCatalog.premiumAppleProductIdMonthly` / `premiumAppleProductIdYearly` — App Store subscription product IDs

## Backend API

- `get_in_app_product_coins()` — verify coin `product_id`
- `get_store_recommended_packages()` — catalog rows
- `get_premium_subscription_config()` — subscription metadata
- Play verify: [`play_billing_main.py`](../../python_base_04/core/modules/play_billing_module/play_billing_main.py)
- Apple verify: **not implemented yet**

## Changing products

1. Edit **only** `dutch_coin_catalog.json`.
2. Create matching products in **Google Play Console** and **App Store Connect** (same IDs).
3. Rebuild Flutter app + redeploy Python backend.
4. Do not hardcode product IDs in Dart/Python.

## Related docs

- [IOS_IN_APP_PURCHASES_SETUP.md](IOS_IN_APP_PURCHASES_SETUP.md) — App Store Connect setup
- [GOOGLE_PLAY_BILLING.md](../python_base_04/GOOGLE_PLAY_BILLING.md) — Play verify + service account
- [IOS_APP_STORE_RELEASE_GUIDE.md](IOS_APP_STORE_RELEASE_GUIDE.md) — IPA + Business agreements
