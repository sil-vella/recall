# iOS App Store release checklist (Dutch Card Game)

**Full walkthrough (Apple account → IPA):** [`Documentation/Android_V_ios/IOS_APP_STORE_RELEASE_GUIDE.md`](../Android_V_ios/IOS_APP_STORE_RELEASE_GUIDE.md)  
**Coin packs + Premium (match Play):** [`Documentation/Android_V_ios/IOS_IN_APP_PURCHASES_SETUP.md`](../Android_V_ios/IOS_IN_APP_PURCHASES_SETUP.md)  
**Product ID SSOT:** [`Documentation/Android_V_ios/COIN_CATALOG_SSOT.md`](../Android_V_ios/COIN_CATALOG_SSOT.md)

Bundle ID: **`com.reignofplay.dutch`**  
Team ID (Xcode): **`D6J4Y6ZQGV`**  
Workspace: **`flutter_base_05/ios/Runner.xcworkspace`**

Official references:

- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Distributing for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Edit access to an app](https://developer.apple.com/help/app-store-connect/create-an-app-record/edit-access-to-an-app/)

---

## Agent / repo (done in project)

| Item | Location |
|------|----------|
| Bundle ID | `ios/Runner.xcodeproj` → `com.reignofplay.dutch` |
| Automatic signing + team | `DEVELOPMENT_TEAM = D6J4Y6ZQGV`, `CODE_SIGN_STYLE = Automatic` |
| Firebase iOS | `ios/Runner/GoogleService-Info.plist` (`BUNDLE_ID` matches) |
| AdMob app ID | `ios/Flutter/Debug.xcconfig` / `Release.xcconfig` → `GAD_APPLICATION_ID` |
| Release IPA script | `playbooks/frontend/build_ipa.sh` |
| Xcode Cloud CI | `ios/ci_scripts/ci_post_clone.sh` + `ci_pre_xcodebuild.sh` |
| Prod dart-defines on Cloud | Workflow secret `DUTCH_DART_DEFINES_PROD_B64` (see below) |

---

## Xcode Cloud — prod dart-defines (required)

Xcode Cloud does **not** have `.env.dart.defines.prod` on disk (gitignored). **`ci_pre_xcodebuild.sh`** decodes it from a workflow secret before `flutter build ios --config-only --dart-define-from-file`, same idea as AAB/IPA local builds.

### One-time: add workflow secrets

App Store Connect → **Xcode Cloud** → your workflow → **Environment**:

| Secret | Required | Contents |
|--------|----------|----------|
| `DUTCH_DART_DEFINES_PROD_B64` | **Yes** | Base64 of repo-root `.env.dart.defines.prod` |
| `DUTCH_ENV_PROD_B64` | No | Base64 of `.env.prod` (version can also come from committed `pubspec.yaml`) |

On your Mac (after editing local prod env):

```bash
cd /path/to/app_dev
base64 -i .env.dart.defines.prod | pbcopy   # paste into DUTCH_DART_DEFINES_PROD_B64
# optional:
base64 -i .env.prod | pbcopy
```

**Refresh secrets** whenever you change API URLs, Firebase, AdMob units, `APP_STORE_URL`, etc. in local `.env.dart.defines.prod`.

### Before each Cloud build

1. Bump `flutter_base_05/pubspec.yaml` `version:` (and run `sync_pubspec_version.sh` locally if you want pbxproj / floor aligned).
2. Commit and push.
3. Trigger Xcode Cloud workflow.

### Verify Cloud build logs

In **pre-xcodebuild** logs you should see:

- `API_URL validated: https://dutch.reignofplay.com` (not `10.0.2.2` or `localhost`)
- `Generated.xcconfig includes API_URL`

On TestFlight, **Sign In** should finish in seconds (prod `HTTP_REQUEST_TIMEOUT`, typically 15s).

### Local dry-run of Cloud scripts

```bash
export REPO_ROOT=/path/to/app_dev
# optional: export DUTCH_DART_DEFINES_PROD_B64="$(base64 -i .env.dart.defines.prod)"
./flutter_base_05/ios/ci_scripts/ci_pre_xcodebuild.sh
```

---

## You — one-time Xcode confirm (~5 min)

1. Open **`flutter_base_05/ios/Runner.xcworkspace`**.
2. **Runner** → **Signing & Capabilities**.
3. Confirm **Automatically manage signing** and team **D6J4Y6ZQGV** (no red errors).
4. If prompted, sign in with Apple ID and allow Xcode to manage profiles.

---

## You — build & upload

### Option A: Script (recommended)

```bash
cd /path/to/app_dev
chmod +x playbooks/frontend/build_ipa.sh
./playbooks/frontend/build_ipa.sh
```

Uses `.env.prod` (version bump) and `.env.dart.defines.prod` (API URLs, keys).

### Option B: Xcode Cloud

Uses the same dart-defines as Option A, materialized from **`DUTCH_DART_DEFINES_PROD_B64`** (see **Xcode Cloud — prod dart-defines** above). Scripts: `ci_post_clone.sh` (Flutter + CocoaPods) → `ci_pre_xcodebuild.sh` (prod defines + `config-only`).

### Option C: Xcode GUI

1. Destination: **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. **Window → Organizer** → **Distribute App** → **App Store Connect** → Upload.

### After IPA exists — check TestFlight before Transporter

1. App Store Connect → **TestFlight** → **Build Uploads**.
2. If your **version + build** (e.g. `2.0.68 (20068)`) is already listed → **stop**; do not open Transporter. Use that build for internal testing or attach it under **Distribution**.
3. If the build is **not** listed → **Transporter**: drag `.ipa` from `flutter_base_05/build/ios/ipa/` (or the Xcode Cloud **app-store** artifact).
4. Wait for **Processing** in TestFlight.

**Xcode Cloud** workflows that distribute to App Store Connect upload automatically — Transporter is only for builds that are not already in **Build Uploads**.

**Build number rule:** Each **new** upload needs a **higher** build number than the last on ASC. Bump `APP_VERSION` / `xcode_cloud_build_number.txt` (via `sync_pubspec_version.sh` or build scripts) before a **new** archive — re-uploading the same IPA always fails.

---

## You — App Store Connect (metadata)

App: **Dutch Card Game** → **Distribution** → **iOS App 1.0**

| Section | Action |
|---------|--------|
| **Previews and Screenshots** | iPhone 6.5": up to 10 screenshots (1242×2688 or 1284×2778, etc.) |
| **Description / keywords / URLs** | Support URL, marketing text, privacy policy URL |
| **App Privacy** | Privacy questionnaire |
| **Pricing and Availability** | Territories, price |
| **App Review Information** | Contact, demo account if login required |
| **Age Rating** | Questionnaire |
| **Build** | After processing, select uploaded build on version 1.0 |
| **Submit** | **Save** → **Add for Review** |

---

## Config — `APP_STORE_URL` (share links on iOS)

When App Store Connect shows the numeric app ID (e.g. `id1234567890`), add to **`.env.dart.defines.prod`** (not committed):

```bash
APP_STORE_URL=https://apps.apple.com/app/id1234567890
```

Rebuild IPA so celebration share sheets include the link. `PLAY_STORE_URL` is separate (Android).

---

## TestFlight (recommended before review)

1. App Store Connect → **TestFlight** → internal testing.
2. Add your Apple ID as tester.
3. Install **TestFlight** on iPhone → open build → smoke-test login, game, ads.

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| **No Accounts: Add a new account in Accounts settings** | Xcode → **Settings → Accounts** → **+** → Apple ID (team D6J4Y6ZQGV). Then open Runner signing again. |
| **No profiles for com.reignofplay.dutch** | Same as above; enable **Automatically manage signing** on Runner. |
| CocoaPods `ASCII-8BIT` / UTF-8 | `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` before build (set in `build_ipa.sh`). |
| No signing certificate | Xcode Signing & Capabilities; sign in to Apple ID |
| Bundle ID mismatch | Must be `com.reignofplay.dutch` everywhere |
| Invalid binary / processing failed | Read email from App Store Connect; often export compliance or missing icons |
| Version already used / Transporter duplicate | Open **TestFlight → Build Uploads** first; if build is already there, skip Transporter; if you need new bits, bump build number, new Xcode Cloud build, then upload only if not auto-delivered |
| Login spins forever on TestFlight / App Review | Cloud build missing prod `API_URL` — check pre-xcodebuild logs; set/refresh `DUTCH_DART_DEFINES_PROD_B64`; confirm not `10.0.2.2` |
| `Missing DUTCH_DART_DEFINES_PROD_B64` in Cloud | Add workflow secret (base64 of `.env.dart.defines.prod`) |

---

## What the agent cannot do

- App Store Connect forms, screenshots, privacy answers, **Add for Review**
- Apple ID / 2FA prompts
- TestFlight install on your phone

See plan: *iOS release agent scope* (repo `.cursor/plans/` if saved locally).
