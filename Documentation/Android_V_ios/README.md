# Android vs iOS — native SDK pins (Xcode 15.2)

This document records **dependency pins** in `flutter_base_05/pubspec.yaml` that exist so **iOS debug builds work on Xcode 15.2** (macOS Ventura, iOS 17.2 SDK). It also explains **what changes on Android** when those pins are in place.

**SSOT for pins:** `flutter_base_05/pubspec.yaml` (dependencies + `dependency_overrides`).

**Related:**

- **iOS App Store release (full walkthrough):** [`IOS_APP_STORE_RELEASE_GUIDE.md`](IOS_APP_STORE_RELEASE_GUIDE.md)
- **iOS release checklist (short):** [`Documentation/flutter_base_05/IOS_RELEASE_CHECKLIST.md`](../flutter_base_05/IOS_RELEASE_CHECKLIST.md)
- AdMob wiring: [`Documentation/Admobs/README.md`](../Admobs/README.md)
- Android AdMob native: [`Documentation/flutter_base_05/ADMOB_NATIVE_SETUP.md`](../flutter_base_05/ADMOB_NATIVE_SETUP.md)
- iOS simulator launch: `.vscode/launch.json` → **Dutch: Flutter (iPhone) — .env.dart.defines.local**
- Run script: `playbooks/frontend/run_flutter_app_to_global_log.sh ios <simulator_udid>`

---

## 1. Why these pins exist

| Blocker | Minimum toolchain | Affected plugin / SDK |
|--------|-------------------|------------------------|
| `Product.SubscriptionOffer.Signature` missing | **iOS 17.4 SDK** (Xcode **15.3+**) | `in_app_purchase_storekit` 0.4.1+ |
| `MarketplaceKit` linker errors | **Xcode 15.3+** | `google_mobile_ads` 5.2+ → Google-Mobile-Ads-SDK **11.6+** |
| Firebase Swift 6 / `sending` APIs | **Xcode 15.3+** (Firebase iOS 11.4+) | `firebase_core` 3.4+ |
| CocoaPods: GoogleSignIn 9 vs Firebase 10 | Pin iOS Google Sign-In pod | `google_sign_in_ios` 6.x with `firebase_core` 3.3 |

On **macOS 13 / Ventura**, the latest Xcode is often **15.2**, which cannot satisfy the above. Pins are intentional until you upgrade to **Xcode 15.3+** (requires **macOS Sonoma 14+** in practice).

---

## 2. Current pins (summary)

### 2.1 `dependencies` (both platforms unless noted)

| Package | Pinned version | Typical “latest” blocked on Xcode 15.2 |
|---------|----------------|----------------------------------------|
| `google_mobile_ads` | **5.1.0** | 5.2+ |
| `firebase_core` | **3.3.0** | 3.8+ |
| `firebase_analytics` | **11.0.0** | 11.3+ |
| `in_app_purchase` | `^3.2.0` | (unchanged) |
| `in_app_purchase_android` | `^0.4.0` | (unchanged) |

### 2.2 `dependency_overrides` (platform-specific)

| Override | Version | Platform |
|----------|---------|----------|
| `in_app_purchase_storekit` | **0.4.0** | **iOS only** |
| `google_sign_in_ios` | **5.7.6** | **iOS only** |
| `package_info_plus` | **8.3.1** | **Android** (javac / `PackageInfoPlugin`; unrelated to Xcode) |

### 2.3 iOS-only project settings

| File | Setting |
|------|---------|
| `ios/Podfile` | `platform :ios, '13.0'`; pods `IPHONEOS_DEPLOYMENT_TARGET = 13.0` |
| `ios/Runner.xcodeproj` | `IPHONEOS_DEPLOYMENT_TARGET = 13.0` |
| `ios/Flutter/AppFrameworkInfo.plist` | `MinimumOSVersion` **13.0** |

`firebase_analytics` on iOS requires deployment target **≥ 13.0** (was **12.0** before first iOS simulator build).

---

## 3. Android: AdMob and Firebase impact

Pins are **not** iOS-only for AdMob/Firebase: the **same Flutter package versions** resolve **different native SDKs** per platform.

### 3.1 AdMob (`google_mobile_ads`)

| | Pinned (5.1.0) | Newer (5.2.x) |
|--|----------------|---------------|
| **Android** | Play Services Ads **23.0.0** | **23.4.0** |
| **iOS** | Google-Mobile-Ads-SDK **~11.2.x** | **11.10+** (MarketplaceKit) |

**Android impact:** Same Dart API and env keys (`ADMOB_APPLICATION_ID`, `ADMOBS_*` in `.env.dart.defines.local` / `.env.prod`). You are one **minor** GMA Android SDK step behind; production ads and test units should still work. No change to `android/app/build.gradle.kts` manifest placeholder logic.

### 3.2 Firebase (`firebase_core` + `firebase_analytics`)

| | Pinned | Newer (example) |
|--|--------|-----------------|
| **Android** | Firebase BoM **33.1.0** (`firebase_core` 3.3.0) | BoM **33.16.0** (`firebase_core` 3.15.x) |
| **iOS** | Firebase iOS SDK **10.29.0** | Firebase iOS **11.15+** |

**Android impact:** Still **Firebase 33.x**; `google-services.json` and Analytics integration unchanged. Slightly older BoM; no intentional feature removal in app code.

### 3.3 Unaffected on Android

- `in_app_purchase_android` — not pinned down
- `google_sign_in` Android implementation — not overridden
- OnePlus / device launch configs — still `run_flutter_app_to_global_log.sh android <serial>`

---

## 4. iOS simulator launch

1. VS Code: **Dutch: Flutter (iPhone) — .env.dart.defines.local**
2. Default simulator UDID in `launch.json`: **iPhone 15** (`8E4C2275-C301-428F-A6F9-E076FDA87A41`). Change after `flutter devices` or `xcrun simctl list` if needed.
3. Script boots a **shutdown** sim (`simctl boot` + `bootstatus -b`), then `flutter run` with `.env.dart.defines.local`.

First iOS build after `pod install` is slow; later hot reloads are faster.

---

## 5. Upgrading (remove pins)

When **Xcode ≥ 15.3** is available:

1. In `pubspec.yaml`, relax pins, e.g.:
   - `google_mobile_ads: ^5.2.0`
   - `firebase_core: ^3.8.0`
   - `firebase_analytics: ^11.3.3`
2. Remove `dependency_overrides` for `in_app_purchase_storekit` and `google_sign_in_ios` (keep `package_info_plus` override until Android 9.x issue is resolved separately).
3. `cd flutter_base_05 && flutter pub get`
4. `cd ios && rm -rf Pods Podfile.lock && pod install`
5. `flutter build ios --simulator` (or device) and smoke-test **AdMob**, **Analytics**, **IAP**, **Google Sign-In**.

---

## 6. Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `SubscriptionOffer.Signature` compile error | `in_app_purchase_storekit` > 0.4.0 | Confirm override **0.4.0** |
| `MarketplaceKit` / undefined symbols on link | GMA iOS **11.6+** | Confirm `google_mobile_ads` **5.1.0** |
| Firebase Swift `sending` / `FIRAllocatedUnfairLock` | Firebase iOS 11.4+ on Xcode 15.2 | Confirm `firebase_core` **3.3.0** |
| Pod install: GoogleUtilities conflict | `google_sign_in_ios` 6.x + Firebase 10 | Confirm override **5.7.6** |
| CocoaPods deployment target 12 vs Firebase 13 | Old iOS target | Confirm Podfile / project **13.0** |
| Simulator not listed | Sim shutdown | Re-run launch config (script boots sim) |
| **Stuck on green splash** after `flutter run` | Session refresh / API call blocking startup | See [§7 Splash stuck on iOS](#7-splash-stuck-on-ios) |

---

## 7. Splash stuck on iOS

The app is **not frozen** if the terminal shows `A Dart VM Service on iPhone 15 is available`. Flutter has started; the UI is still on the bootstrap splash until `AppManager.initializeApp` finishes.

### What you see in the log (usually harmless)

| Log line | Meaning |
|----------|---------|
| `50 required SKAdNetwork identifier(s) missing` | AdMob warning — add SKAdNetwork IDs to `Info.plist` for production attribution; does not block launch. |
| `unhandled element <style/>; Picture key: Svg loader` | `flutter_svg` skipped a `<style>` in an SVG — cosmetic; does not block launch. |

### Common cause: HTTP timeout during session check

Startup calls `AuthManager.validateSessionOnStartup()`. If the simulator has **saved login + refresh token**, it may call `POST /public/refresh` on `API_URL` (from `.env.dart.defines.local`, e.g. `http://192.168.178.81:5001`).

`ConnectionsApiModule` uses `Config.httpRequestTimeout`, which defaults to **600 seconds** (10 minutes) unless overridden:

```dart
// flutter_base_05/lib/utils/consts/config.dart
static const int httpRequestTimeout = int.fromEnvironment(
  'HTTP_REQUEST_TIMEOUT',
  defaultValue: 600,
);
```

If Flask/Dart WS backends are **down** or unreachable from the Mac/simulator, the splash can sit for minutes.

**Quick checks:**

1. Confirm **Python Flask** is running at `API_URL` and **Dart WS** at `WS_URL` on the LAN IP (simulator uses the Mac network — not `localhost` unless the server is on the same machine and you use the Mac’s LAN IP).
2. In repo-root **`.env.dart.defines.local`**, set a sane timeout for daily dev:
   ```bash
   HTTP_REQUEST_TIMEOUT=15
   ```
   Re-run the iPhone launch config so defines are picked up.
3. **Fresh sim / no stale session:** delete the app from the simulator (long-press → Delete App) and launch again — logged-out startup skips refresh.
4. After backends are up, press **`R`** (hot restart) in the `flutter run` terminal.

### UI flow (for debugging)

1. `main()` — native splash preserved; AdMob UMP (≤30s), Firebase, modules registered.
2. `runApp` → `_AppBootstrapSplash` while `_isInitializing || !appManager.isInitialized`.
3. `appManager.initializeApp` — modules, then `validateSessionOnStartup`, then `handleAuthState`.
4. Splash removed → `MaterialApp.router` (default route `/`).

---

*Last updated: 2026-05-24 — aligned with Xcode 15.2 / Ventura iOS simulator workflow.*
