# iOS In-App Purchases — match Android (coin packs + Premium)

This guide configures **App Store Connect** so product IDs align with **Google Play** and the repo catalog [`flutter_base_05/assets/dutch_coin_catalog.json`](../../flutter_base_05/assets/dutch_coin_catalog.json).

**App:** Dutch Card Game — bundle ID `com.reignofplay.dutch` — Apple ID `6772967073`

**Important:** The Flutter app enables Play Billing on **Android** and App Store billing on **iOS**. Server verify: [`play_billing_module`](../../python_base_04/core/modules/play_billing_module/play_billing_main.py) (Android) and [`apple_billing_module`](../../python_base_04/core/modules/apple_billing_module/apple_billing_main.py) (iOS). Deploy guide: [`APPLE_APP_STORE_BILLING.md`](../python_base_04/APPLE_APP_STORE_BILLING.md).

**Product ID SSOT:** [`COIN_CATALOG_SSOT.md`](COIN_CATALOG_SSOT.md) — keys `in_app_products`, `store_recommended_packages`, `premium_subscription.base_plans`. Flutter [`coin_catalog.dart`](../../flutter_base_05/lib/utils/coin_catalog.dart) and Python [`coin_catalog.py`](../../python_base_04/utils/coin_catalog.py) read the same JSON file.

---

## Official Apple documentation

| Topic | Link |
|--------|------|
| IAP types (consumable vs subscription) | [In-App Purchase types](https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-types/) |
| Configure IAP overview + workflow | [Overview for configuring In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/) |
| Create consumables | [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/) |
| Auto-renewable subscriptions | [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/) |
| Subscriptions (concepts) | [Auto-renewable Subscriptions](https://developer.apple.com/app-store/subscriptions/) |
| Sandbox testing | [Overview of testing in sandbox](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox/) |
| StoreKit (implementation) | [In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase) |
| App Store Server API | [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) |
| Paid Apps Agreement (required) | App Store Connect → **Business** → agreements |

---

## 0. Prerequisites (before creating products)

1. **Paid Apps Agreement** — Account Holder accepts in App Store Connect → **Business** ([overview](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/) step 1).
2. **Banking and tax** completed under **Business** (same as paid apps).
3. App record exists: **Dutch Card Game** / `com.reignofplay.dutch`.
4. **In-App Purchase capability** in Xcode: Runner target → **Signing & Capabilities** → **+ Capability** → **In-App Purchase** (when you implement StoreKit in the app).

---

## 1. Android / catalog parity matrix

SSOT: [`dutch_coin_catalog.json`](../../flutter_base_05/assets/dutch_coin_catalog.json) — `store_recommended_packages` + `in_app_products`

### 1.1 Coin packs (consumables)

| Coins | Google Play product ID | App Store product ID (use **same**) | Type on Apple |
|------:|----------------------|-------------------------------------|---------------|
| 100 | `coins_100` | `coins_100` | **Consumable** |
| 300 | `coins_300` | `coins_300` | **Consumable** |
| 500 | `coin_500` | `coin_500` | **Consumable** (note: `coin_` not `coins_`) |
| 700 | `coins_700` | `coins_700` | **Consumable** |
| 1500 | `coins_1500` | `coins_1500` | **Consumable** |
| 3500 | `coins_3500` | `coins_3500` | **Consumable** |

**Why consumable:** Coins are spent in-game; each purchase is depleted — matches [Apple consumable definition](https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-types/) and Play consumables.

**Reference UI prices** (Stripe / marketing only — set **equivalent tiers** in App Store Connect; Apple shows localized prices):

| Pack | `recommended_ui_packages` price (USD) |
|------|--------------------------------------|
| 100 | $0.99 |
| 300 | $2.49 |
| 500 | $3.99 |
| 700 | $4.99 |
| 1500 | $9.99 |
| 3500 | $19.99 |

### 1.2 Premium subscription

| | Google Play | App Store Connect |
|--|-------------|-------------------|
| Subscription product ID | `premium_subscription` | **Two separate subscription products** (Apple has no “base plans” on one ID) |
| Monthly (Play base plan ID) | `premium-auto-renew-monthly` | Apple Product ID: **`premium_auto_renew_monthly`** — duration **1 month** |
| Yearly (Play base plan ID) | `premium-auto-renew-yearly` | Apple Product ID: **`premium_auto_renew_yearly`** — duration **1 year** |
| Benefits (catalog) | Ad-free + **+11%** coins on packs (`subscriber_coin_bonus_percent`) | Same copy in subscription description |

Play uses **one** subscription SKU with multiple base plans; Apple uses **one subscription group** with **two** auto-renewable products (recommended so users pick monthly OR yearly, not both).

**Server today:** `POST /userauth/play/verify-subscription` and `verify-coin-purchase` — Android only ([`GOOGLE_PLAY_BILLING.md`](../python_base_04/GOOGLE_PLAY_BILLING.md)).

---

## 2. Create coin packs in App Store Connect

Path: **Apps** → **Dutch Card Game** → sidebar **Monetization** → **In-App Purchases** → **+**

For **each** row in §1.1:

1. Click **+**.
2. Select **Consumable**.
3. **Reference name:** e.g. `Coin pack — 100` (internal; not shown on store).
4. **Product ID:** must match table exactly (e.g. `coins_100`).
5. **Create**.
6. On the product page:
   - **Price schedule:** choose tier closest to USD reference (e.g. $0.99 tier for 100 coins).
   - **App Store localization:** display name + description (can reuse catalog `description` / `label`).
   - **Review screenshot:** if required for first IAP submission.
7. **Save**.

Repeat for all six product IDs.

Official steps: [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/).

**Limits:** Up to 10,000 IAPs per app; metadata can take **up to 1 hour** to appear in **Sandbox**.

---

## 3. Create Premium subscription group + products

Path: **Monetization** → **Subscriptions** → **+** (subscription group)

### 3.1 Subscription group

1. **+** → create group.
2. **Reference name:** e.g. `Dutch Premium`.
3. **Create**.

Use **one group** (best practice: user only holds one subscription in the group at a time) — [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/).

Optional localization: group display name e.g. **Premium membership**.

### 3.2 Monthly subscription

Inside the group → **Create** (or **+**):

| Field | Value |
|--------|--------|
| Reference name | Premium — Monthly |
| **Product ID** | `premium_auto_renew_monthly` |
| Duration | **1 month** |
| Price | Match Play monthly (pick tier; verify Play Console price) |
| Localization | Name: **Premium (Monthly)** — Description: *Ad-free play and +11% coins on every coin pack* |

### 3.3 Yearly subscription

| Field | Value |
|--------|--------|
| Reference name | Premium — Yearly |
| **Product ID** | `premium_auto_renew_yearly` |
| Duration | **1 year** |
| Price | Match Play yearly |
| Localization | Name: **Premium (Yearly)** — same benefits text |

### 3.4 Subscription levels (upgrade / downgrade)

If both are in the **same group**, set **levels** so yearly is “higher” than monthly if you want upgrades to prefer yearly — **Subscriptions** → group → **Edit Order** ([assign levels](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/)).

Single-tier setup (only one product) is also valid if you ship monthly-only first.

---

## 4. Tax category and IAP keys

1. **Tax category** — set per IAP/subscription (usually games / digital goods).
2. **In-App Purchase key** — App Store Connect → **Users and Access** → **Integrations** → **In-App Purchase** (for [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) signing).
3. **App Store Server Notifications** — configure sandbox + production URLs when the backend module exists ([overview workflow](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/)).

---

## 5. Submit IAPs for review

- First-time IAPs for an app are submitted **with an app version** that implements them ([overview](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/)).
- Each IAP needs **Ready to Submit** metadata (localizations, pricing, review notes).
- App Review must approve IAPs before they work in production; **Sandbox** works earlier for development.

---

## 6. Sandbox testing (no real charges)

1. App Store Connect → **Users and Access** → **Sandbox** → **Testers** → create sandbox Apple accounts.
2. On iPhone: **Settings → App Store → Sandbox Account** (sign in with sandbox tester).
3. Install build via **TestFlight** or dev build with StoreKit.
4. Purchase consumables and subscriptions; renewals are accelerated in sandbox — [Overview of testing in sandbox](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox/).

Optional: **StoreKit Configuration** file in Xcode for local testing without App Store Connect network — [Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).

---

## 7. Checklist — App Store Connect only

| # | Task | Done |
|---|------|------|
| 1 | Paid Apps Agreement + tax/banking | ☐ |
| 2 | Six **consumables** with IDs §1.1 | ☐ |
| 3 | Subscription group **Dutch Premium** | ☐ |
| 4 | `premium_auto_renew_monthly` (1 month) | ☐ |
| 5 | `premium_auto_renew_yearly` (1 year) | ☐ |
| 6 | Prices aligned with Play / catalog USD | ☐ |
| 7 | Localizations (EN at minimum) | ☐ |
| 8 | Sandbox testers created | ☐ |
| 9 | IAP key + (later) server notification URLs | ☐ |

---

## 8. After App Store Connect (code + server)

To match Android **behavior**, not just product IDs:

| Layer | Android today | iOS needed |
|--------|---------------|------------|
| UI | [`coin_purchase_screen.dart`](../../flutter_base_05/lib/screens/coin_purchase_screen/coin_purchase_screen.dart) — Play consumables | Enable StoreKit via `in_app_purchase` / `in_app_purchase_storekit`; query same product IDs |
| Premium UI | [`premium_subscription_section.dart`](../../flutter_base_05/lib/screens/account_screen/widgets/premium_subscription_section.dart) — Android only | iOS section: query `premium_auto_renew_monthly` + `premium_auto_renew_yearly` |
| Verify coins | `POST /userauth/play/verify-coin-purchase` | New route e.g. `/userauth/apple/verify-coin-purchase` using [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) transaction validation |
| Verify subscription | `POST /userauth/play/verify-subscription` | Apple subscription status + notifications → `subscription_tier` = `premium` |
| Catalog | `store_recommended_packages` + `in_app_products` | Same IDs in StoreKit `queryProductDetails` via `CoinCatalog.storeRecommendedPackages` |

**Status:** §8 implemented — see [`Documentation/python_base_04/APPLE_APP_STORE_BILLING.md`](../python_base_04/APPLE_APP_STORE_BILLING.md).

---

## 9. Product ID quick copy-paste

```
coins_100
coins_300
coin_500
coins_700
coins_1500
coins_3500
premium-auto-renew-monthly
premium-auto-renew-yearly
premium_auto_renew_monthly
premium_auto_renew_yearly
```

**Do not** use Team ID (`D6J4Y6ZQGV`) or Apple ID (`6772967073`) as product IDs.

---

## Related repo docs

- Catalog SSOT: [`COIN_CATALOG_SSOT.md`](COIN_CATALOG_SSOT.md)
- Android Play setup: [`Documentation/python_base_04/GOOGLE_PLAY_BILLING.md`](../python_base_04/GOOGLE_PLAY_BILLING.md)
- iOS release / IPA: [`IOS_APP_STORE_RELEASE_GUIDE.md`](IOS_APP_STORE_RELEASE_GUIDE.md)
- Xcode 15.2 SDK pins (StoreKit / IAP): [`README.md`](README.md)

---

*Created: 2026-05-25 — product IDs aligned with `dutch_coin_catalog.json` schema v2.*
