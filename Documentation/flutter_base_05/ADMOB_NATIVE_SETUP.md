# AdMob native (Android / iOS)

**Full implementation guide (banner / interstitial / rewarded, hooks, test vs prod):** [`Documentation/Admobs/README.md`](../Admobs/README.md).

## Flutter `--dart-define` (ad **unit** IDs)

Set in `.env.prod`, `.env.local`, or your launch script (see `playbooks/frontend/env_for_flutter_dart_defines.py` + `launch_oneplus.sh` / `build_*.sh`, which pass `--dart-define-from-file`). Release builds go through `playbooks/frontend/build_appbundle.sh`, `build_apk.sh`, and `build_web.sh`; local Android device runs use `launch_oneplus.sh` — not `flutter_base_05/build.py` (that file is an optional manual AAB helper only).

| Variable | Purpose |
|----------|---------|
| `ADMOB_APPLICATION_ID` | Android AdMob **app** id (`ca-app-pub-…~…`, **not** an ad unit). Same `.env` files as below; Gradle prefers this over `local.properties`. |
| `ADMOBS_TOP_BANNER01` | Top banner ad unit |
| `ADMOBS_BOTTOM_BANNER01` | Bottom banner ad unit |
| `ADMOBS_INTERSTITIAL01` | Full-screen interstitial (navigation gate) |
| `ADMOBS_REWARDED01` | Rewarded ad unit (coin screen) |

Leave `ADMOBS_INTERSTITIAL01` and `ADMOBS_REWARDED01` **empty** until those units exist in AdMob; the app skips the switch-screen interstitial gate and the rewarded coin card when they are unset (banner-only is supported).

**Defaults in repo:** `lib/utils/consts/config.dart` compiles in the live **banner** unit `ca-app-pub-6524100109992126/3612268528` for top and bottom unless you override with `--dart-define`. Interstitial and rewarded stay opt-in via env.

For **optional** Google test creatives (different publisher), see [Android test ads](https://developers.google.com/admob/android/test-ads) and set matching **application** id + sample units via `.env.local` / `local.properties` so app id and unit ids stay from the same account.

## Premium (`subscription_tier`)

When `modules.dutch_game.subscription_tier` is **`premium`** (see `StateManager` / `DutchGameHelpers.getUserDutchGameStats()`), the client does not load or show AdMob banners, interstitials, or rewarded UI; navigation no longer counts toward interstitial gates. The rewarded claim API returns `403` with `PREMIUM_NO_ADS`. Tiers are evaluated **when each ad path runs** (and UI listens to `StateManager` for tier changes), not only at app start—so upgrades/downgrades apply without restarting.

Optional targeting / consent-related defines (see `lib/utils/consts/config.dart`):

- `ADMOB_TAG_FOR_CHILD_DIRECTED_TREATMENT` — `-1` unspecified, `0` not child-directed, `1` child-directed.
- `ADMOB_TAG_FOR_UNDER_AGE_OF_CONSENT_REQUEST` — same pattern for request configuration.
- `ADMOB_CONSENT_TAG_UNDER_AGE_OF_CONSENT` — `true` / `false` for UMP `ConsentRequestParameters`.

## Android AdMob **application** id

Gradle injects `ADMOB_APPLICATION_ID` into the manifest placeholder.

**Production application id:** `ca-app-pub-6524100109992126~6470366151` — must be the same AdMob **app** as your `ADMOBS_*` unit ids.

**Precedence:**

1. **`ADMOB_APPLICATION_ID`** in `.env.local` / `.env.prod` — emitted as `--dart-define` by `dart_defines_from_env.sh` (used by `launch_oneplus.sh`, `build_appbundle.sh`, etc.). **Wins when present.**
2. **`admob.application_id`** in `flutter_base_05/android/local.properties` — optional fallback (e.g. opening only the `android` module in Android Studio without Flutter’s dart-defines).
3. If both are absent, Gradle uses the **production** default `ca-app-pub-6524100109992126~6470366151` (see `android/app/build.gradle.kts`).

Example overrides in `.env.prod` (same values as defaults; useful when you add more units later):

```properties
ADMOB_APPLICATION_ID='ca-app-pub-6524100109992126~6470366151'
ADMOBS_TOP_BANNER01='ca-app-pub-6524100109992126/3612268528'
ADMOBS_BOTTOM_BANNER01='ca-app-pub-6524100109992126/3612268528'
```

### Troubleshooting: no banner, `onAdFailedToLoad` code 1

If logcat shows **`Error building request URL: Cannot determine request type. Is your ad unit id correct?`**, the **ad unit string may still be valid** — check that **Android `APPLICATION_ID`** (Gradle / manifest) and **iOS `GAD_APPLICATION_ID`** match the **same AdMob app** as the ad unit’s publisher. After changing app id, run **`flutter clean`** and reinstall so the manifest updates.

## iOS AdMob **application** id

Set `GAD_APPLICATION_ID` in `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` (must match the same AdMob **app** as your banner units). `Info.plist` references `$(GAD_APPLICATION_ID)`.

## Backend (rewarded coins)

After the user earns a reward, the app POSTs `/userauth/admob/claim-rewarded-ad` with `{ "client_nonce": "<uuid>" }`.

Configure Flask via env (also in `playbooks/rop01/templates/env.j2`):

- `ADMOB_REWARDED_COINS_PER_CLAIM` (default `25`)
- `ADMOB_REWARDED_DAILY_CAP` (default `20`)

Production: add **Google rewarded server-side verification (SSV)** so grants cannot be forged from a generic HTTP client.
