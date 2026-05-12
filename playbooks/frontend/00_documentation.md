### Tools Scripts Overview

This directory contains helper scripts for running and building the Dutch Flutter app and integrating it with the Python backend and the VPS.

Scripts:
- `launch_chrome.sh` – run the Flutter web app in Chrome; `--dart-define` values come only from repo-root `.env.local`.
- `launch_oneplus.sh` – run the Flutter app on a physical Android device; same dart-define SSOT (`.env.local`).
- `build_web.sh` – build Flutter web release and upload to VPS (dutch.reignofplay.com). Optional `DEPLOY_SUBDIR=example` deploys to dutch.reignofplay.com/example.
- `build_apk.sh` – build a release APK, bump the platform version, upload it to the VPS downloads directory, and update the mobile release manifest.
- `optimize_logging_calls.py` – optimize logging calls by converting runtime checks to compile-time conditionals for better performance.

---

### 1. `launch_chrome.sh`

**Purpose**:
- Launches the Flutter web app (`flutter_base_05`) in Chrome on your Mac.
- Mirrors merged `flutter run` output into `python_base_04/tools/logger/server.log` for debugging (see `Documentation/debug/AGENT_DEBUG_LOGS.md`).
- **Dart-define SSOT:** repo-root `.env.local` (see `playbooks/frontend/dart_defines_from_env.sh`). Set `API_URL`, `WS_URL`, JWT, AdMob, Stripe, logging flags there — scripts do not override them.

**What it runs**:
- `cd flutter_base_05`
- `flutter run -d chrome --web-port=3002 --web-hostname=localhost` with `--dart-define` built only from `.env.local`.
- Pipes merged `flutter run` stdout/stderr through `filter_logs`, which appends each line (with a UTC prefix and `[FLUTTER]`) to:

    ```
    python_base_04/tools/logger/server.log
    ```

  and prints the same lines to the integrated terminal.

This is the recommended way to run the **web** version; point it at local or VPS by editing `API_URL` / `WS_URL` in `.env.local`.

---

### 2. `launch_oneplus.sh`

**Purpose**:
- Launches the Flutter app on a selected **Android** device (shortcuts for OnePlus, Samsung, Xiaomi tablet, DOOGEE).
- Uses the same dart-define SSOT as the Chrome launcher (repo-root `.env.local`).
- Mirrors merged `flutter run` output into `python_base_04/tools/logger/server.log` (same scheme as Chrome; see `Documentation/debug/AGENT_DEBUG_LOGS.md`).

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
- All merged `flutter run` lines are written to `server.log` and echoed to the terminal.

Use this script for **manual testing on a physical device**.

---

### 3. `build_apk.sh`

**Purpose**:
- Automates building the **Android release APK** for Dutch.
- Keeps the app version in sync across:
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

1. **Disable logging**: 
   - Sets `LOGGING_SWITCH = false` in all Flutter source files before build
   - Ensures production builds don't include debug logging

2. **Resolve repo root**:
   - `SCRIPT_DIR` = `playbooks/frontend`
   - `REPO_ROOT` = project root.

3. **Load `.env.prod` and bump version**:
   - Sources repo-root `.env.prod`, then runs `bump_app_version_prompt` (patch bump optional).

4. **Compute build number**:
   - Parses `APP_VERSION` as `major.minor.patch`.
   - Computes:

     ```bash
     BUILD_NUMBER = major * 10000 + minor * 100 + patch
     ```

     (e.g., `2.1.0` → `20100`).

5. **Build APK** from `flutter_base_05`:

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

6. **If `BACKEND_TARGET=vps`**:
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

# 1) Ensure repo-root `.env.prod` has API_URL, WS_URL, APP_VERSION, secrets, and release flags (DEBUG_MODE, JWT_*, …).

# 2) Build + upload + update manifest for VPS (default)
./playbooks/frontend/build_apk.sh

# 3) Build only — skip VPS upload
./playbooks/frontend/build_apk.sh local

# 4) Use a custom SSH target (if needed)
VPS_SSH_TARGET="rop01_user@65.181.125.135" ./playbooks/frontend/build_apk.sh
```

---

### 4. `build_web.sh`

**Purpose**:
- Builds the Flutter **web** release and uploads it to the VPS so the app is served at **https://dutch.reignofplay.com** (and dutch.reignofplay.com). Nginx document root on the server is `/var/www/dutch.reignofplay.com`.

**Steps (high level)**:
1. Sets production deck config (testing_mode=false, predefined_hands enabled=false), disables `LOGGING_SWITCH` in Dart sources.
2. Runs `flutter build web` from `flutter_base_05` with `--dart-define` built only from repo-root `.env.prod`.
3. Output: `flutter_base_05/build/web/`. Cache-busts `index.html` with `?v=$APP_VERSION` for script/manifest/favicon.
4. If deploy arg is `vps` (default): rsyncs build to a temp dir on the VPS, then (unless deploying to a subdir) backs up existing root, cleans web root (preserving `sponsors`, `sim_players`, `downloads`, `example`, `.well-known`), copies new files to `/var/www/dutch.reignofplay.com`, sets ownership to `www-data`. Use `./build_web.sh local` to build without deploy.

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

### 5. `optimize_logging_calls.py`

**Purpose**:
- Optimizes logging performance by converting runtime checks to compile-time conditionals.
- Allows Dart's compiler to eliminate dead code when `LOGGING_SWITCH = false`.
- Creates automatic backups before making changes.

**What it does**:

1. **Creates backups** (Step 1):
   - Creates timestamped backup directory: `backups/YYYYMMDD_HHMMSS_logging_optimization/`
   - Makes exact copies of:
     - `flutter_base_05/`
     - `dart_bkend_base_01/`
   - Verifies backups by checking file counts and sizes
   - Aborts if backup fails

2. **Optimizes logging calls** (Step 2):
   - Scans `backend_core/shared_logic/` directories in both Flutter and Dart backend projects
   - Finds all logger calls with `isOn: LOGGING_SWITCH` parameter
   - Converts from:
     ```dart
     _logger.info('message', isOn: LOGGING_SWITCH);
     ```
   - To:
     ```dart
     if (LOGGING_SWITCH) {
       _logger.info('message');
     }
     ```

**Performance benefits**:
- **Zero runtime overhead** when `LOGGING_SWITCH = false`:
  - No method call overhead
  - No string interpolation overhead
  - No runtime checks
- **Smaller bundle size**: Dead code is eliminated at compile-time by Dart's tree-shaking
- **Better performance**: Especially important for Flutter web builds where every millisecond counts

**Why this matters**:
- The old pattern (`isOn: LOGGING_SWITCH`) still executes method calls and string interpolation even when disabled
- The new pattern (`if (LOGGING_SWITCH)`) allows the compiler to completely remove the code block when the constant is `false`
- With hundreds of logging calls, this can significantly improve performance

**Usage**:

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
python3 playbooks/frontend/optimize_logging_calls.py
```

**Output**:
- Shows backup creation progress
- Lists each file processed and number of calls converted
- Displays summary with backup location
- Backup location is shown for easy restoration if needed

**Restoring from backup**:

If you need to restore the original code:

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
# Find the backup directory
ls backups/

# Restore (example)
cp -r backups/20260119_155914_logging_optimization/flutter_base_05/* flutter_base_05/
cp -r backups/20260119_155914_logging_optimization/dart_bkend_base_01/* dart_bkend_base_01/
```

**When to run**:
- After adding new logging calls with `isOn: LOGGING_SWITCH`
- Before production builds to ensure optimal performance
- Periodically to keep codebase optimized

**Note**: This script only processes files in `backend_core/shared_logic/` directories. Other logging calls in the codebase may still use the old pattern.

---

### Notes

- All three scripts assume the project root is `Recall/app_dev` and that the Python backend log file is at:

  ```
  python_base_04/tools/logger/server.log
  ```

- The APK build script is tightly integrated with the backend versioning and Nginx `/downloads/` setup; changing the directory layout on the VPS will require corresponding changes in `build_apk.sh` and the Flask config. Sensitive config is supplied via the VPS `.env` (see `app_dev/.env.example`).
