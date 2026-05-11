# AdMob native (Android / iOS)

## Flutter `--dart-define` (ad **unit** IDs)

Set in `.env.prod`, `.env.local`, or your launch script (see `playbooks/frontend/dart_defines_from_env.sh`). Release/debug builds go through `playbooks/frontend/build_appbundle.sh`, `build_apk.sh`, `build_web.sh`, and `launch_android_debug.sh` — not `flutter_base_05/build.py` (that file is an optional manual AAB helper only).

| Variable | Purpose |
|----------|---------|
| `ADMOBS_TOP_BANNER01` | Top banner ad unit |
| `ADMOBS_BOTTOM_BANNER01` | Bottom banner ad unit |
| `ADMOBS_INTERSTITIAL01` | Full-screen interstitial (navigation gate) |
| `ADMOBS_REWARDED01` | Rewarded ad unit (coin screen) |

Leave `ADMOBS_INTERSTITIAL01` and `ADMOBS_REWARDED01` **empty** until those units exist in AdMob; the app skips the switch-screen interstitial gate and the rewarded coin card when they are unset (banner-only is supported).

### Google demo ad units (local / QA)

Official test creatives ([Android test ads](https://developers.google.com/admob/android/test-ads)). Defaults for **hardcoded** demo IDs live in `playbooks/frontend/launch_android_debug.sh` and the optional `flutter_base_05/build.py`; most setups set `ADMOBS_*` in root `.env.local` / `.env.prod` instead.

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

Not a Dart define. Gradle injects `ADMOB_APPLICATION_ID` into the manifest placeholder.

1. In `flutter_base_05/android/local.properties` add (Dutch production app example):
   ```properties
   admob.application_id=ca-app-pub-6524100109992126~6470366151
   ```
2. If omitted, the build uses Google’s **test** application id (`ca-app-pub-3940256099942544~3347511713`) — only use that when your `ADMOBS_*` units are also Google’s **sample** IDs.

## iOS AdMob **application** id

Set `GAD_APPLICATION_ID` in `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` (must match the same AdMob **app** as your banner units). `Info.plist` references `$(GAD_APPLICATION_ID)`.

## Backend (rewarded coins)

After the user earns a reward, the app POSTs `/userauth/admob/claim-rewarded-ad` with `{ "client_nonce": "<uuid>" }`.

Configure Flask via env (also in `playbooks/rop01/templates/env.j2`):

- `ADMOB_REWARDED_COINS_PER_CLAIM` (default `25`)
- `ADMOB_REWARDED_DAILY_CAP` (default `20`)

Production: add **Google rewarded server-side verification (SSV)** so grants cannot be forged from a generic HTTP client.
