### Tools Scripts Overview

This directory contains helper scripts for running and building the Dutch Flutter app and integrating it with the Python backend and the VPS.

Scripts:
- `launch_chrome.sh` – run the Flutter web app in Chrome; `--dart-define` values come only from repo-root `.env.local`.
- `launch_oneplus.sh` – run the Flutter app on a physical Android device; same dart-define SSOT (`.env.local`).
- `build_web.sh` – build Flutter web release and upload to VPS (dutch.reignofplay.com). Optional `DEPLOY_SUBDIR=example` deploys to dutch.reignofplay.com/example.
- `build_apk.sh` – build a release APK, bump the platform version, upload it to the VPS downloads directory, and update the mobile release manifest.

---

### 1. `launch_chrome.sh`

**Purpose**:
- Launches the Flutter web app (`flutter_base_05`) in Chrome on your Mac.
- **Dart-define SSOT:** repo-root `.env.local` (see `playbooks/frontend/dart_defines_from_env.sh`). Set `API_URL`, `WS_URL`, JWT, AdMob, Stripe there — scripts do not override them.
- **Social share (optional):** `PLAY_STORE_URL`, `APP_STORE_URL` — store links appended when users share win/level-up/rank-up from celebration screens (defaults to Play listing for `com.reignofplay.dutch`; set `APP_STORE_URL` before iOS release).

**What it runs**:
- `cd flutter_base_05`
- `flutter run -d chrome --web-port=3002 --web-hostname=localhost` with `--dart-define` built only from `.env.local`.
- Pipes merged `flutter run` stdout/stderr through `filter_logs`, which echoes each line to the terminal.

This is the recommended way to run the **web** version; point it at local or VPS by editing `API_URL` / `WS_URL` in `.env.local`.

---

### 2. `launch_oneplus.sh`

**Purpose**:
- Launches the Flutter app on a selected **Android** device (shortcuts for OnePlus, Samsung, Xiaomi tablet, DOOGEE).
- Uses the same dart-define SSOT as the Chrome launcher (repo-root `.env.local`).

**Prerequisites**:
- `adb` installed and on your `PATH`.
- Target device connected and visible via `adb devices`.

**Device selection**:
- Optional first argument **`local` or `vps`** (legacy, no-op for dart-defines): if present, device is **`$2`**, or `ANDROID_DEVICE_ID`, or the interactive prompt.
- Otherwise **`$1`** = device serial or shortcut (`1` OnePlus, `2` Samsung, `3` Xiaomi tablet, `4` DOOGEE).
- **Dart-define SSOT:** repo-root `.env.local`. Set `API_URL` / `WS_URL` there for local vs VPS backends.

**What it runs**:
- Confirms the device is connected.
- `cd flutter_base_05`.
- `flutter run -d <device>` with `--dart-define` built only from `.env.local`.
- Merged `flutter run` output is echoed to the terminal.

Use this script for **manual testing on a physical device**.

---

### 2b. Screen record (adb)

**Standalone** — `adb_screenrecord.sh` (timed clip, no flutter):
```bash
./playbooks/frontend/adb_screenrecord.sh              # 30 seconds, pick device
./playbooks/frontend/adb_screenrecord.sh 90 1        # 90s on OnePlus
```

**With Flutter (OnePlus, same launch as VS Code local)** — `run_flutter_oneplus_with_screenrecord.sh`:
- Same as `run_flutter_app_to_global_log.sh android 84fbcf31` (`.env.dart.defines.local`, `DUTCH_DEV_LOG`, `[dev]` → `global.log`).
- While `flutter run` is active, press **`V`** to **start/stop** screen record (like **`R`** = hot restart). Clips go to `recordings/dutch_screen_*.mp4`.
- VS Code: **Dutch: Flutter (OnePlus + V record) — .env.dart.defines.local**

```bash
./playbooks/frontend/run_flutter_oneplus_with_screenrecord.sh
./playbooks/frontend/run_flutter_oneplus_with_screenrecord.sh R3CWB0CS63D   # other serial
```

**Notes**:
- Video only (no audio). Each segment max **180s** (adb limit); press **V** again before 180s to stop early.
- Optional env: `SCREENRECORD_SIZE`, `SCREENRECORD_BIT_RATE` (default `8000000`).

---

### 3. `build_ipa.sh`

**Purpose**:
- Builds a **release IPA** for Dutch (TestFlight / App Store upload).
- Same production prep as `build_apk.sh` (dart-defines from `.env.dart.defines.prod`, version from `.env.prod`, deck config, `LOGGING_SWITCH` off).
- Does **not** upload to App Store Connect — after a build, check **TestFlight → Build Uploads** first; use Transporter or Organizer **only** if that build number is not already listed (Xcode Cloud may have uploaded it).

**Prerequisites**:
- macOS with Xcode; CocoaPods; Apple Developer signing (team `D6J4Y6ZQGV` in `ios/Runner.xcodeproj`).
- Add `APP_STORE_URL=https://apps.apple.com/app/id…` to `.env.dart.defines.prod` when the numeric App Store ID is known (iOS share links).

**Usage**:

```bash
./playbooks/frontend/build_ipa.sh
```

**Full checklist**: `Documentation/flutter_base_05/IOS_RELEASE_CHECKLIST.md`

---

### 3b. Xcode Cloud iOS (TestFlight / App Store)

**Purpose**:
- Same **production dart-defines** as `build_ipa.sh` / `build_appbundle.sh`, but env files are **materialized on the CI runner** from Xcode Cloud workflow secrets (files are gitignored locally).

**Scripts** (`flutter_base_05/ios/ci_scripts/`):
- `ci_post_clone.sh` — Flutter install, `pub get`, `precache --ios`, `pod install` (no dart-defines here).
- `ci_pre_xcodebuild.sh` — decode `DUTCH_DART_DEFINES_PROD_B64` → `.env.dart.defines.prod`, release prep (deck, `LOGGING_SWITCH` off), `env_for_flutter_dart_defines.py` → JSON, validate `API_URL`, `flutter build ios --config-only --dart-define-from-file`.

**Shared helpers**:
- `playbooks/frontend/flutter_release_build_common.sh` — also used by `build_ipa.sh`.
- `playbooks/frontend/xcode_cloud_materialize_env.sh` — base64 secret → repo-root env files.

**Secrets** (App Store Connect → Xcode Cloud → Environment):
- `DUTCH_DART_DEFINES_PROD_B64` (required): `base64 -i .env.dart.defines.prod | pbcopy`
- `DUTCH_ENV_PROD_B64` (optional): `base64 -i .env.prod | pbcopy`

**Version**: committed `pubspec.yaml` + `sync_pubspec_version.sh` floor (`xcode_cloud_build_number.txt`) — no interactive bump on CI.

| Path | Dart-defines source |
|------|---------------------|
| `build_ipa.sh` | On-disk `.env.dart.defines.prod` |
| `build_appbundle.sh` | On-disk `.env.dart.defines.prod` |
| Xcode Cloud | `DUTCH_DART_DEFINES_PROD_B64` workflow secret |

---

### 4. `build_apk.sh`

**Purpose**:
- Automates building the **Android release APK** for Dutch.
- Keeps the app version in sync across:
  - `.env.prod` / `.env.dart.defines.prod` and `pubspec.yaml` (`sync_pubspec_version.sh`),
  - The backend’s update logic (`/public/check-updates`),
  - Flutter’s `build-name`/`build-number` (Android/iOS),
  - The downloadable APK path on the VPS.
- Optionally uploads the APK to the VPS and updates the mobile release manifest.

**Inputs**:
- **Dart-define SSOT:** repo-root `.env.prod` — every `KEY=value` becomes `--dart-define` via `dart_defines_from_env.sh` (including `API_URL`, `WS_URL`, `APP_VERSION`, JWT, AdMob, flags).
- Positional arg `local` or `vps` (default `vps`): **upload/deploy only** — does not change dart-defines.
- Interactive `bump_app_version_prompt` updates `APP_VERSION` in `.env.prod` before build.
- Optional env vars:
  - `VPS_SSH_TARGET` (default: `rop01_user@65.181.125.135`).
  - `VPS_SSH_KEY` (default: `~/.ssh/rop01_key`).
  - `MIN_SUPPORTED_VERSION` (defaults to `APP_VERSION`).

**What it does** (high level):

1. **Resolve repo root**:
   - `SCRIPT_DIR` = `playbooks/frontend`
   - `REPO_ROOT` = project root.

2. **Load `.env.prod` and bump version**:
   - Sources repo-root `.env.prod`, then runs `bump_app_version_prompt` (patch bump optional).

3. **Compute build number**:
   - Parses `APP_VERSION` as `major.minor.patch`.
   - Computes:

     ```bash
     BUILD_NUMBER = major * 10000 + minor * 100 + patch
     ```

     (e.g., `2.1.0` → `20100`).

4. **Build APK** from `flutter_base_05`:

   ```bash
     flutter build apk \
       --release \
       --build-name="$APP_VERSION" \
       --build-number="$BUILD_NUMBER" \
       --dart-define-from-file=/path/to/generated-from-.env.prod.json
   ```

   (Script builds the `--dart-define` array from `.env.prod` only — no script-side URL/JWT overrides.)

   Output APK:

   ```
   flutter_base_05/build/app/outputs/flutter-apk/app-release.apk
   ```

5. **If `BACKEND_TARGET=vps`**:
   - Uploads the APK to the VPS via `scp` using `VPS_SSH_KEY` and `VPS_SSH_TARGET`.
   - Installs it to:

     ```bash
     /var/www/dutch.reignofplay.com/downloads/v$APP_VERSION/app.apk
     ```

     (owned by `www-data`, mode `0644`).

   - Regenerates the mobile release manifest on the VPS at:

     ```bash
     /opt/apps/reignofplay/dutch/secrets/mobile_release.json
     ```

     with content like:

     ```json
     {
       "latest_version": "2.1.0",
       "min_supported_version": "2.1.0"
     }
     ```

   - Ensures the manifest is in place; the download base URL is provided via the VPS `.env` (see `app_dev/.env.example`). Deployment uses `.env` only; no secret files are used.

**Backend update behavior**:
- The Flask endpoint `/public/check-updates` reads `mobile_release.json` and the download base URL from app config (env from `.env`), then:
  - Compares the client-reported `current_version` with `latest_version`/`min_supported_version`.
  - Returns `update_available` / `update_required` and a `download_link` pointing at:

    ```
    https://dutch.reignofplay.com/downloads/v<latest_version>/app.apk
    ```

**Usage examples**:

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev

# 1) Ensure repo-root `.env.prod` has API_URL, WS_URL, APP_VERSION, secrets, and release flags (JWT_*, …).

# 2) Build + upload + update manifest for VPS (default)
./playbooks/frontend/build_apk.sh

# 3) Build only — skip VPS upload
./playbooks/frontend/build_apk.sh local

# 4) Use a custom SSH target (if needed)
VPS_SSH_TARGET="rop01_user@65.181.125.135" ./playbooks/frontend/build_apk.sh
```

---

### 5. `build_web.sh`

**Purpose**:
- Builds the Flutter **web** release and uploads it to the VPS so the app is served at **https://dutch.reignofplay.com** (and dutch.reignofplay.com). Nginx document root on the server is `/var/www/dutch.reignofplay.com`.

**Steps (high level)**:
1. Sets production deck config (testing_mode=false, predefined_hands enabled=false).
2. Runs `flutter build web` from `flutter_base_05` with `--dart-define` built only from repo-root `.env.prod`.
3. Output: `flutter_base_05/build/web/`. Cache-busts `index.html` with `?v=$APP_VERSION` for script/manifest/favicon.
4. If deploy arg is `vps` (default): rsyncs build to a temp dir on the VPS, then (unless deploying to a subdir) backs up existing root, cleans web root (preserving `app_media`, `sim_players`, `downloads`, `example`, `.well-known`), copies new files to `/var/www/dutch.reignofplay.com`, sets ownership to `www-data`. Use `./build_web.sh local` to build without deploy.

**Deploying to a subdirectory (`/example/`)**:
- On the VPS, nginx must expose `location /example/` → `/var/www/dutch.reignofplay.com/example/` (configure manually on the server).
- To deploy a separate app or static content to **https://dutch.reignofplay.com/example** (or the hostname your vhost uses):
  1. Build your Flutter app with **base-href** set to `/example/` (e.g. `flutter build web --base-href /example/`).
  2. Run: `DEPLOY_SUBDIR=example ./build_web.sh vps`
- The script uploads the build to the VPS temp dir, then copies into `$REMOTE_WEB_ROOT/example/` (clearing only that subdir). The main site docroot is left unchanged.

**Usage**:
```bash
# Build and deploy to main docroot
./playbooks/frontend/build_web.sh vps

# Build and deploy to …/example (build with base-href /example/ first)
DEPLOY_SUBDIR=example ./playbooks/frontend/build_web.sh vps
```

---

### Notes

- The APK build script is tightly integrated with the backend versioning and Nginx `/downloads/` setup; changing the directory layout on the VPS will require corresponding changes in `build_apk.sh` and the Flask config. Sensitive config is supplied via the VPS `.env` (see `app_dev/.env.example`).
