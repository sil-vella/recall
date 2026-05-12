# AdMob in the Dutch Flutter app

This document describes how **Google Mobile Ads** are wired in `flutter_base_05`: **banner**, **interstitial**, and **rewarded** placements, how **application IDs** and **ad unit IDs** reach native code from environment files, and how to run **test** vs **production** inventory safely.

For a shorter checklist focused on native app IDs and Gradle, see [`Documentation/flutter_base_05/ADMOB_NATIVE_SETUP.md`](../flutter_base_05/ADMOB_NATIVE_SETUP.md).

---

## 1. Architecture overview

| Layer | Role |
|--------|------|
| **`.env.local` / `.env.prod`** (repo root) | Single source of truth for keys consumed as Dart compile-time constants and (on Android) for `ADMOB_APPLICATION_ID` in Gradle. |
| **`playbooks/frontend/env_for_flutter_dart_defines.py`** | Converts `KEY=value` env files to JSON for `flutter run` / `flutter build … --dart-define-from-file=…` (avoids shell `ARG_MAX` with large envs). |
| **`lib/utils/consts/config.dart`** | `String.fromEnvironment` / `bool.fromEnvironment` / `int.fromEnvironment` for each AdMob-related key. |
| **`lib/modules/admobs/admob_bootstrap.dart`** | Native only: UMP consent update + `MobileAds.instance.initialize()` before any ad load. Called from `main.dart` before `runApp`. |
| **`BannerAdModule` / `InterstitialAdModule` / `RewardedAdModule`** | Load/show logic; read unit IDs from `Config.*`. |
| **`AdExperiencePolicy`** | Gates monetized ads when `subscription_tier` is `premium`. |
| **Android `android/app/build.gradle.kts`** | Injects `ADMOB_APPLICATION_ID` into `AndroidManifest.xml` via `manifestPlaceholders`. |
| **iOS `ios/Flutter/*.xcconfig` + `Info.plist`** | `GAD_APPLICATION_ID` for the same AdMob **app** as your units. |

Web builds do not use AdMob (`kIsWeb` guards); use AdSense keys from env where applicable.

---

## 2. Environment variables → Dart and Android

### 2.1 Keys you typically set

| Variable | Used for | Notes |
|----------|-----------|--------|
| **`ADMOB_APPLICATION_ID`** | Android **app** id (`ca-app-pub-XXXXXXXX~YYYYYYYY`). **Not** an ad unit. | Must belong to the **same** AdMob app as every `ADMOBS_*` unit id you use. |
| **`ADMOBS_TOP_BANNER01`** | Top banner unit | Can equal bottom unit; two `BannerAd` instances are used (see §4). |
| **`ADMOBS_BOTTOM_BANNER01`** | Bottom banner unit | Skipped on web in `BannerAdModule` hook. |
| **`ADMOBS_INTERSTITIAL01`** | Interstitial unit | If **empty**, switch-screen interstitial flow is skipped entirely. |
| **`ADMOBS_REWARDED01`** | Rewarded unit | If **empty**, coin-purchase “watch ad” path is skipped. |
| **`ADMOB_DEBUG_LOGS`** | Extra `[AdMob]` logs via `dbgAdMob` | `true` / `false`. |
| **`ADMOB_TAG_FOR_CHILD_DIRECTED_TREATMENT`** | `RequestConfiguration` | `-1` default unspecified; `0` / `1` per SDK. |
| **`ADMOB_TAG_FOR_UNDER_AGE_OF_CONSENT_REQUEST`** | Same | `-1` default. |
| **`ADMOB_CONSENT_TAG_UNDER_AGE_OF_CONSENT`** | UMP `ConsentRequestParameters` | `true` / `false`. |

All of the above are plain `KEY=value` lines in `.env.local` (device/web dev) or `.env.prod` (release builds). Launch/build scripts merge the whole file into Flutter via **`--dart-define-from-file`** (see `playbooks/frontend/launch_oneplus.sh`, `launch_chrome.sh`, `build_apk.sh`, `build_appbundle.sh`, `build_web.sh`).

### 2.2 Android application ID precedence (`build.gradle.kts`)

1. **`ADMOB_APPLICATION_ID`** decoded from Flutter’s `dart-defines` (comes from your env JSON when you `flutter run` / `flutter build`).  
2. Else `admob.application_id` in `flutter_base_05/android/local.properties`.  
3. Else hardcoded **production** default `ca-app-pub-6524100109992126~6470366151`.

The chosen value is written to:

```text
android/app/src/main/AndroidManifest.xml
  → <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
               android:value="${ADMOB_APPLICATION_ID}"/>
```

### 2.3 iOS application ID

`ios/Runner/Info.plist` references `$(GAD_APPLICATION_ID)`. Values are set in:

- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`

Example line:

```properties
GAD_APPLICATION_ID=ca-app-pub-6524100109992126~6470366151
```

For **local testing with Google’s sample ad units** (`ca-app-pub-3940256099942544/…`), you must use Google’s **sample app id** on iOS as well (`ca-app-pub-3940256099942544~3347511713`), or use **your** real units with **your** `6524100109992126~…` app id. **Never** mix a production app id with Google’s `3940256099942544` sample units — the SDK returns `onAdFailedToLoad` code **1** (“Cannot determine request type…”).

---

## 3. `Config` compile-time mapping (`config.dart`)

Dart reads compile-time constants (fed by `--dart-define-from-file`):

```dart
// Ad unit IDs (examples — real values come from .env)
static const String admobsTopBanner = String.fromEnvironment(
  'ADMOBS_TOP_BANNER01',
  defaultValue: 'ca-app-pub-6524100109992126/3612268528',
);
static const String admobsBottomBanner = String.fromEnvironment(
  'ADMOBS_BOTTOM_BANNER01',
  defaultValue: 'ca-app-pub-6524100109992126/3612268528',
);
static const String admobsInterstitial01 = String.fromEnvironment(
  'ADMOBS_INTERSTITIAL01',
  defaultValue: '',
);
static const String admobsRewarded01 = String.fromEnvironment(
  'ADMOBS_REWARDED01',
  defaultValue: '',
);
```

**Note:** `ADMOB_APPLICATION_ID` is **not** read in Dart; it exists for Gradle (Android) / xcconfig (iOS) only.

---

## 4. Banner ads — current implementation

### 4.1 Module and slots

- **File:** `lib/modules/admobs/banner/banner_ad.dart`  
- **Class:** `BannerAdModule` (`moduleKey`: `admobs_banner_ad_module`).

**Design:** Top and bottom slots are keyed separately (`top|<unitId>`, `bottom|<unitId>`) so the **same** unit id can be used twice: two `BannerAd` loads, two `AdWidget`s. Deduplicating only by unit id would break the second slot.

### 4.2 When loads are triggered

1. **`AdvertsModule`** (`lib/modules/admobs/adverts_module.dart`), after other ad modules register, calls on native + non-premium:

   ```dart
   banner.loadBannerAd(Config.admobsTopBanner, slot: 'top');
   banner.loadBannerAd(Config.admobsBottomBanner, slot: 'bottom');
   ```

2. **`BaseScreen`** (`lib/core/00_base/screen_base.dart`), `initState` → post-frame:

   - `appManager.triggerBottomBannerBarHook(context);`
   - `appManager.triggerTopBannerBarHook(context);`

3. **`BannerAdModule.initialize`** registers **HooksManager** callbacks:

   - `top_banner_bar_loaded` → `loadBannerAd(Config.admobsTopBanner, slot: 'top')`
   - `bottom_banner_bar_loaded` → `loadBannerAd(..., slot: 'bottom')` (skipped if `kIsWeb`)

`AppManager` registers **stub** hooks at priority **1**; `BannerAdModule` registers at priority **10** so real handlers run.

### 4.3 UI placement

Still in **`BaseScreen`**: a `Column` reserves **50px** top/bottom when `AdExperiencePolicy.showMonetizedAds`, `bannerAdModule != null`, and the corresponding `Config.admobs*` string is non-empty. Children:

- `bannerAdModule!.getTopBannerWidget(context)`
- `bannerAdModule!.getBottomBannerWidget(context)`

Each slot uses `ValueListenableBuilder` tied to `_frameTick` so when `onAdLoaded` assigns `_bannerByKey[key]`, the `AdWidget` appears.

### 4.4 Example env (production-style)

```properties
ADMOB_APPLICATION_ID='ca-app-pub-6524100109992126~6470366151'
ADMOBS_TOP_BANNER01='ca-app-pub-6524100109992126/3612268528'
ADMOBS_BOTTOM_BANNER01='ca-app-pub-6524100109992126/3612268528'
```

### 4.5 Example env (Google test banners on Android)

Use **Google’s test app id** together with [official sample banner units](https://developers.google.com/admob/android/test-ads):

```properties
ADMOB_APPLICATION_ID='ca-app-pub-3940256099942544~3347511713'
ADMOBS_TOP_BANNER01='ca-app-pub-3940256099942544/6300978111'
ADMOBS_BOTTOM_BANNER01='ca-app-pub-3940256099942544/6300978111'
```

Match **iOS** `GAD_APPLICATION_ID` to the same test app id when running on iPhone with those units.

---

## 5. Interstitial ads — current implementation

### 5.1 Module

- **File:** `lib/modules/admobs/interstitial/interstitial_ad.dart`  
- **Class:** `InterstitialAdModule(Config.admobsInterstitial01)` registered in `module_registry.dart`.

If `adUnitId` is empty, `initialize` skips `loadAd()`. Loads respect `AdExperiencePolicy.showMonetizedAds`.

### 5.2 Navigation gate + overlay

1. **`AdsSwitchScreenNavigatorObserver`** (`lib/modules/promotional_ads_module/ads_navigator_observer.dart`) counts **real** `PageRoute` pushes/replaces (not dialogs). Every **`showAfterScreenChanges`** transitions (from YAML type `switch_screen`, default **3**), it fires hook `switch_screen_ad` with the route’s `BuildContext`.

2. **`PromotionalAdsModule`** listens to `switch_screen_ad`. It **returns early** if:

   - `Config.admobsInterstitial01.trim().isEmpty`
   - `!AdExperiencePolicy.showMonetizedAds`
   - No `switch_screen` entry in `AdRegistry`
   - Overlay already open

   Otherwise it opens **`SwitchScreenAdOverlay.show`** with `delayBeforeSkipSeconds` from YAML.

3. **`SwitchScreenAdOverlay`** (`widgets/switch_screen_ad_overlay.dart`):

   - Post-frame: `InterstitialAdModule.loadAd()` (refresh inventory before Skip).
   - After countdown: **`InterstitialAdModule.showOrFinish(context, onClosed)`** — shows interstitial if ready, else closes overlay immediately.

### 5.3 Example env (interstitial enabled)

```properties
ADMOB_APPLICATION_ID='ca-app-pub-6524100109992126~6470366151'
ADMOBS_INTERSTITIAL01='ca-app-pub-6524100109992126/<your-interstitial-unit>'
```

Google’s **test interstitial** unit is commonly `ca-app-pub-3940256099942544/1033173712` — pair with **test app id** `ca-app-pub-3940256099942544~3347511713`.

---

## 6. Rewarded ads — current implementation

### 6.1 Module

- **File:** `lib/modules/admobs/rewarded/rewarded_ad.dart`  
- **Class:** `RewardedAdModule(Config.admobsRewarded01)`.

`initialize` calls `loadAd()` if unit id non-empty. `isReady` exposes readiness; `stateTick` drives UI rebuilds.

### 6.2 Coin purchase screen

- **File:** `lib/screens/coin_purchase_screen/coin_purchase_screen.dart`

Flow sketch:

1. User taps “watch ad” (when `Config.admobsRewarded01` is non-empty and not web).
2. If `!mod.isReady`, show snackbar and `loadAd()`.
3. Else generate `clientNonce` (UUID), call:

   ```dart
   await mod.showAd(
     context,
     onUserEarnedReward: () {
       unawaited(_claimRewardedAdCoins(api, clientNonce));
     },
   );
   ```

4. **`_claimRewardedAdCoins`** POSTs to the Python API (e.g. `/userauth/admob/claim-rewarded-ad`) with `{ "client_nonce": "<uuid>" }` for server-side validation and coin grant.

### 6.3 Example env (rewarded enabled)

```properties
ADMOB_APPLICATION_ID='ca-app-pub-6524100109992126~6470366151'
ADMOBS_REWARDED01='ca-app-pub-6524100109992126/<your-rewarded-unit>'
```

Google’s **test rewarded** unit is often `ca-app-pub-3940256099942544/5224354917` — again use **test app id** `…3940256099942544~3347511713` on both Android and iOS when testing.

### 6.4 Backend (reference)

Flask env knobs (see `playbooks/rop01/templates/env.j2` and Python `AdmobRewardsModule`):

- `ADMOB_REWARDED_COINS_PER_CLAIM`
- `ADMOB_REWARDED_DAILY_CAP`

Production should use **Google rewarded SSV** so grants cannot be spoofed from a raw HTTP client.

---

## 7. Premium and policy (`AdExperiencePolicy`)

- **File:** `lib/modules/admobs/ad_experience_policy.dart`

If `DutchGameHelpers.getUserDutchGameStats()?['subscription_tier']` normalizes to **`premium`**, then `showMonetizedAds` is **false**: no banner loads, interstitial observer short-circuits, rewarded UI treats ads as off. Server should align (e.g. `403` on reward claim for premium).

---

## 8. Bootstrap and logging

### 8.1 Startup order (`main.dart`)

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `await bootstrapConsentAndMobileAds()` — UMP + `MobileAds.instance.initialize()` (native only).
3. Firebase (when enabled).
4. `runApp` → modules initialize → `AdvertsModule` preloads banners.

### 8.2 Traces

- **`admobTrace(tag, message)`** — `lib/modules/admobs/admob_trace.dart` (structured prefix `[AdMob/<tag>]`).
- **`dbgAdMob(...)`** — gated by `Config.admobDebugLogs` (`ADMOB_DEBUG_LOGS=true` in env).

Local runs that mirror Flutter to `python_base_04/tools/logger/server.log` (e.g. `launch_oneplus.sh`) will show load failures such as **code 1** when app id and unit publisher mismatch.

---

## 9. Testing vs production (quick reference)

| Environment | Android / Gradle `ADMOB_APPLICATION_ID` | Example banner unit | iOS `GAD_APPLICATION_ID` |
|-------------|----------------------------------------|------------------------|---------------------------|
| **Google sample ads** | `ca-app-pub-3940256099942544~3347511713` | `ca-app-pub-3940256099942544/6300978111` (banner) | Same `~3347511713` app id |
| **Dutch production** | `ca-app-pub-6524100109992126~6470366151` | Units created under that app in AdMob console | Same `6524100109992126~6470366151` |

**Rule:** The **application id** (with `~`) and every **ad unit id** (with `/`) must belong to the **same AdMob application** in Google’s sense. Mixing production `~6470366151` with `3940256099942544/…` sample units produces **failed loads**, not “silent” banners.

After changing application id, run **`flutter clean`** and reinstall so merged manifests / Info.plist update.

---

## 10. Module registration order (reference)

From `lib/core/managers/module_registry.dart` (conceptual):

1. `BannerAdModule`
2. `InterstitialAdModule(Config.admobsInterstitial01)`
3. `RewardedAdModule(Config.admobsRewarded01)`
4. `AdvertsModule` (depends on the three above — preloads banners)

---

## 11. Related paths (index)

| Path | Purpose |
|------|---------|
| `flutter_base_05/lib/main.dart` | Calls `bootstrapConsentAndMobileAds()`. |
| `flutter_base_05/lib/modules/admobs/admob_bootstrap.dart` | UMP + SDK init. |
| `flutter_base_05/lib/modules/admobs/banner/banner_ad.dart` | Banners. |
| `flutter_base_05/lib/modules/admobs/interstitial/interstitial_ad.dart` | Interstitial. |
| `flutter_base_05/lib/modules/admobs/rewarded/rewarded_ad.dart` | Rewarded. |
| `flutter_base_05/lib/modules/admobs/adverts_module.dart` | Eager banner preload. |
| `flutter_base_05/lib/core/00_base/screen_base.dart` | Layout + hook triggers. |
| `flutter_base_05/lib/core/managers/app_manager.dart` | Stub banner hooks + triggers. |
| `flutter_base_05/lib/modules/promotional_ads_module/` | Interstitial gate + YAML. |
| `flutter_base_05/android/app/build.gradle.kts` | `ADMOB_APPLICATION_ID` → manifest. |
| `flutter_base_05/ios/Flutter/Debug.xcconfig` / `Release.xcconfig` | `GAD_APPLICATION_ID`. |
| `playbooks/frontend/env_for_flutter_dart_defines.py` | Env → JSON for Flutter CLI. |
| `Documentation/flutter_base_05/ADMOB_NATIVE_SETUP.md` | Shorter native + troubleshooting. |

---

## 12. Changelog hints for maintainers

- Prefer adding new AdMob **keys** to `.env.local` / `.env.prod` and `config.dart` rather than hardcoding units in Dart modules.
- If you add many env keys, keep using **`--dart-define-from-file`** (already the playbook default) so macOS/Linux do not hit **`ARG_MAX`** on `flutter run`.
