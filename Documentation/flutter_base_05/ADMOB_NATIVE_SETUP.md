# AdMob native (Android / iOS)

## Flutter `--dart-define` (ad **unit** IDs)

Set in `.env.prod`, `.env.local`, or your launch script (see `playbooks/frontend/dart_defines_from_env.sh`). Release builds go through `playbooks/frontend/build_appbundle.sh`, `build_apk.sh`, and `build_web.sh`; local Android device runs use `launch_oneplus.sh` (see `.vscode/launch.json`) — not `flutter_base_05/build.py` (that file is an optional manual AAB helper only).

| Variable | Purpose |
|----------|---------|
| `ADMOB_APPLICATION_ID` | Android AdMob **app** id (`ca-app-pub-…~…`, **not** an ad unit). Same `.env` files as below; Gradle prefers this over `local.properties`. |
| `ADMOBS_TOP_BANNER01` | Top banner ad unit |
| `ADMOBS_BOTTOM_BANNER01` | Bottom banner ad unit |
| `ADMOBS_INTERSTITIAL01` | Full-screen interstitial (navigation gate) |
| `ADMOBS_REWARDED01` | Rewarded ad unit (coin screen) |

Leave `ADMOBS_INTERSTITIAL01` and `ADMOBS_REWARDED01` **empty** until those units exist in AdMob; the app skips the switch-screen interstitial gate and the rewarded coin card when they are unset (banner-only is supported).

### Google demo ad units (local / QA)

Official test creatives ([Android test ads](https://developers.google.com/admob/android/test-ads)). Set `ADMOBS_*` in root **`.env.local`** (loaded by `launch_oneplus.sh` / `launch_chrome.sh` via `dart_defines_from_env.sh`) and **`.env.prod`** (release). Use **Google sample** banner IDs locally with **Google test application id** in `android/local.properties`.

| Ad format | Demo ad unit ID | This repo (`ADMOBS_*`) |
|-----------|------------------|-------------------------|
| Fixed size banner | `ca-app-pub-3940256099942544/6300978111` | `TOP` + `BOTTOM` (matches `AdSize.banner`) |
| Anchored adaptive banner | `ca-app-pub-3940256099942544/9214589741` | Use if you switch banners to adaptive size API |
| Interstitial | `ca-app-pub-3940256099942544/1033173712` | `ADMOBS_INTERSTITIAL01` |
| Rewarded | `ca-app-pub-3940256099942544/5224354917` | `ADMOBS_REWARDED01` |
| Rewarded interstitial | `ca-app-pub-3940256099942544/5354046379` | Not used yet |
| App open | `ca-app-pub-3940256099942544/9257395921` | Not used yet |

## Premium (`subscription_tier`)

When `modules.dutch_game.subscription_tier` is **`premium`** (see `StateManager` / `DutchGameHelpers.getUserDutchGameStats()`), the client does not load or show AdMob banners, interstitials, or rewarded UI; navigation no longer counts toward interstitial gates. The rewarded claim API returns `403` with `PREMIUM_NO_ADS`. Tiers are evaluated **when each ad path runs** (and UI listens to `StateManager` for tier changes), not only at app start—so upgrades/downgrades apply without restarting.

Optional targeting / consent-related defines (see `lib/utils/consts/config.dart`):

- `ADMOB_TAG_FOR_CHILD_DIRECTED_TREATMENT` — `-1` unspecified, `0` not child-directed, `1` child-directed.
- `ADMOB_TAG_FOR_UNDER_AGE_OF_CONSENT_REQUEST` — same pattern for request configuration.
- `ADMOB_CONSENT_TAG_UNDER_AGE_OF_CONSENT` — `true` / `false` for UMP `ConsentRequestParameters`.

## Android AdMob **application** id

Gradle injects `ADMOB_APPLICATION_ID` into the manifest placeholder.

**What is “testing” vs production?**

- **`ca-app-pub-6524100109992126~6470366151`** — your **real** AdMob **application** id from the console (production app). Use it when `ADMOBS_*` point at **your** ad units from that same app.
- **`ca-app-pub-3940256099942544~3347511713`** — Google’s **sample** application id. Use it with Google’s **sample** unit ids (`ca-app-pub-3940256099942544/...`) for local QA.

**Precedence (no need to edit `local.properties` when switching):**

1. **`ADMOB_APPLICATION_ID`** in `.env.local` / `.env.prod` — emitted as `--dart-define` by `dart_defines_from_env.sh` (used by `launch_oneplus.sh`, `build_appbundle.sh`, etc.). **Wins when present.**
2. **`admob.application_id`** in `flutter_base_05/android/local.properties` — optional fallback (e.g. opening only the `android` module in Android Studio without Flutter’s dart-defines).
3. If both are absent, Gradle uses Google’s **test** application id (`ca-app-pub-3940256099942544~3347511713`).

Example `.env.local` (sample banners + sample app id):

```properties
ADMOB_APPLICATION_ID='ca-app-pub-3940256099942544~3347511713'
ADMOBS_TOP_BANNER01='ca-app-pub-3940256099942544/6300978111'
```

Example production (your app id + your live units from AdMob):

```properties
ADMOB_APPLICATION_ID='ca-app-pub-6524100109992126~6470366151'
ADMOBS_TOP_BANNER01='ca-app-pub-6524100109992126/3612268528'
```

### Troubleshooting: no banner, `onAdFailedToLoad` code 1

If logcat / forwarded logs show **`Error building request URL: Cannot determine request type. Is your ad unit id correct?`** for a unit like `ca-app-pub-3940256099942544/6300978111`, the **ad unit id string is often fine** — the mismatch is usually **application id** in `local.properties` (or iOS `GAD_APPLICATION_ID`) vs the **publisher** of the ad unit. Pair **Google sample units** with **`ca-app-pub-3940256099942544~3347511713`**. Pair **your live units** with **your** `ca-app-pub-…~…` app id from AdMob. Then **clean** (`flutter clean`) and reinstall so the manifest picks up the new app id.

## iOS AdMob **application** id

Set `GAD_APPLICATION_ID` in `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` (must match the same AdMob **app** as your banner units). `Info.plist` references `$(GAD_APPLICATION_ID)`.

## Backend (rewarded coins)

After the user earns a reward, the app POSTs `/userauth/admob/claim-rewarded-ad` with `{ "client_nonce": "<uuid>" }`.

Configure Flask via env (also in `playbooks/rop01/templates/env.j2`):

- `ADMOB_REWARDED_COINS_PER_CLAIM` (default `25`)
- `ADMOB_REWARDED_DAILY_CAP` (default `20`)

Production: add **Google rewarded server-side verification (SSV)** so grants cannot be forged from a generic HTTP client.
