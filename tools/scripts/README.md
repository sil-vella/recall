### Tools Scripts Overview

This directory contains helper scripts for running and building the Cleco Flutter app and integrating it with the Python backend and the VPS.

Scripts:
- `launch_chrome.sh` – run the Flutter web app in Chrome, pointing at either LOCAL or VPS backend.
- `launch_oneplus.sh` – run the Flutter app on a physical Android device (OnePlus, id `84fbcf31`) with the same backend options.
- `build_apk.sh` – build a release APK, bump the platform version, upload it to the VPS downloads directory, and update the mobile release manifest.

---

### 1. `launch_chrome.sh`

**Purpose**:
- Launches the Flutter web app (`flutter_base_05`) in Chrome on your Mac.
- Streams only filtered `AppLogger` output into the shared Python `server.log` file.
- Allows a simple switch between LOCAL and VPS backends.

**Backend selection**:
- First argument: `local` (default) or `vps`.

```bash
# LOCAL backend (default)
./tools/scripts/launch_chrome.sh
# or
./tools/scripts/launch_chrome.sh local

# VPS backend
./tools/scripts/launch_chrome.sh vps
```

**Local vs VPS behavior**:
- `local`:
  - `API_URL="http://localhost:5001"`
  - `WS_URL="ws://localhost:8080"`
- `vps`:
  - `API_URL="https://cleco.reignofplay.com"`
  - `WS_URL="wss://cleco.reignofplay.com/ws"`

**What it runs**:
- `cd flutter_base_05`
- `flutter run -d chrome --web-port=3002 --web-hostname=localhost` with a set of `--dart-define` flags (API_URL, WS_URL, JWT, AdMob, Stripe, logging, etc.).
- Pipes all stdout/stderr through a `filter_logs` function that:
  - Extracts lines coming from `[AppLogger]` in Flutter logs.
  - Writes them to the shared Python log file:

    ```
    /Users/sil/Documents/Work/reignofplay/Recall/app_dev/python_base_04/tools/logger/server.log
    ```

This is the recommended way to run the **web** version against either the local backend or the live VPS.

---

### 2. `launch_oneplus.sh`

**Purpose**:
- Launches the Flutter app on the connected **OnePlus** Android device with id `84fbcf31`.
- Uses the same environment (`API_URL`, `WS_URL`, JWT, AdMob, Stripe, logging) as the Chrome launcher.
- Streams filtered `AppLogger` output into the shared Python `server.log`.

**Prerequisites**:
- `adb` installed and on your `PATH`.
- OnePlus device connected and visible via `adb devices` as `84fbcf31`.

**Backend selection**:

```bash
# LOCAL backend
./tools/scripts/launch_oneplus.sh
# or
./tools/scripts/launch_oneplus.sh local

# VPS backend
./tools/scripts/launch_oneplus.sh vps
```

**Local vs VPS behavior**:
- `vps`:
  - `API_URL="https://cleco.reignofplay.com"`
  - `WS_URL="wss://cleco.reignofplay.com/ws"`
- `local`:
  - Uses your LAN IP for the Python/Dart backend (currently `192.168.178.81:5001` for Flask and `:8080` for WebSockets).

**What it runs**:
- Confirms the OnePlus device is connected.
- `cd flutter_base_05`.
- Runs:

  ```bash
  flutter run \
    -d 84fbcf31 \
    --dart-define=API_URL=... \
    --dart-define=WS_URL=... \
    ... (JWT/AdMob/Stripe/logging defines)
  ```

- All logs are filtered to `AppLogger` messages and written to the shared `server.log`, plus colorized in the terminal.

Use this script for **manual testing on the physical device** against either local or VPS backends.

---

### 3. `build_apk.sh`

**Purpose**:
- Automates building the **Android release APK** for Cleco.
- Keeps the app version in sync across:
  - The backend’s update logic (`/public/check-updates`),
  - Flutter’s `build-name`/`build-number` (Android/iOS),
  - The downloadable APK path on the VPS.
- Optionally uploads the APK to the VPS and updates the mobile release manifest.

**Inputs**:
- `BACKEND_TARGET` – positional arg (`local` or `vps`, default `vps`).
- `python_base_04/secrets/app_version` – single-line semantic version (e.g. `2.1.0`).
- Optional env vars:
  - `VPS_SSH_TARGET` (default: `rop01_user@65.181.125.135`).
  - `VPS_SSH_KEY` (default: `~/.ssh/rop01_key`).
  - `MIN_SUPPORTED_VERSION` (defaults to `APP_VERSION`).

**What it does** (high level):

1. **Disable logging**: 
   - Sets `LOGGING_SWITCH = false` in all Flutter source files before build
   - Ensures production builds don't include debug logging

2. **Resolve repo root**:
   - `SCRIPT_DIR` = `tools/scripts`
   - `REPO_ROOT` = project root.

3. **Read app version**:
   - Reads `APP_VERSION` from `python_base_04/secrets/app_version`, or falls back to `2.0.0` if not present.

4. **Compute build number**:
   - Parses `APP_VERSION` as `major.minor.patch`.
   - Computes:

     ```bash
     BUILD_NUMBER = major * 10000 + minor * 100 + patch
     ```

     (e.g., `2.1.0` → `20100`).

5. **Select backend URLs**:
   - For `vps` (default):

     ```bash
     API_URL="https://cleco.reignofplay.com"
     WS_URL="wss://cleco.reignofplay.com/ws"
     ```

   - For `local`: uses the LAN IP for the backend services.

6. **Build APK** from `flutter_base_05`:

   ```bash
   flutter build apk \
     --release \
     --build-name="$APP_VERSION" \
     --build-number="$BUILD_NUMBER" \
     --dart-define=API_URL="$API_URL" \
     --dart-define=WS_URL="$WS_URL" \
     --dart-define=APP_VERSION="$APP_VERSION" \
     ...
   ```

   Output APK:

   ```
   flutter_base_05/build/app/outputs/flutter-apk/app-release.apk
   ```

7. **If `BACKEND_TARGET=vps`**:
   - Uploads the APK to the VPS via `scp` using `VPS_SSH_KEY` and `VPS_SSH_TARGET`.
   - Installs it to:

     ```bash
     /var/www/cleco.reignofplay.com/downloads/v$APP_VERSION/app.apk
     ```

     (owned by `www-data`, mode `0644`).

   - Regenerates the mobile release manifest on the VPS at:

     ```bash
     /opt/apps/reignofplay/cleco/secrets/mobile_release.json
     ```

     with content like:

     ```json
     {
       "latest_version": "2.1.0",
       "min_supported_version": "2.1.0"
     }
     ```

   - Ensures the manifest and `app_download_base_url` secret are readable by the Flask container.

**Backend update behavior**:
- The Flask endpoint `/public/check-updates` reads `mobile_release.json` and `app_download_base_url` from `/app/secrets/`, then:
  - Compares the client-reported `current_version` with `latest_version`/`min_supported_version`.
  - Returns `update_available` / `update_required` and a `download_link` pointing at:

    ```
    https://cleco.reignofplay.com/downloads/v<latest_version>/app.apk
    ```

**Usage examples**:

```bash
cd /Users/sil/Documents/Work/reignofplay/Recall/app_dev

# 1) Set the new app version
echo "2.1.0" > python_base_04/secrets/app_version

# 2) Build + upload + update manifest for VPS
./tools/scripts/build_apk.sh

# 3) Build only for local backend
./tools/scripts/build_apk.sh local

# 4) Use a custom SSH target (if needed)
VPS_SSH_TARGET="rop01_user@65.181.125.135" ./tools/scripts/build_apk.sh
```

---

### Notes

- All three scripts assume the project root is `Recall/app_dev` and that the Python backend log file is at:

  ```
  python_base_04/tools/logger/server.log
  ```

- The APK build script is tightly integrated with the backend versioning and Nginx `/downloads/` setup; changing the directory layout on the VPS or the secrets mount path will require corresponding changes in `build_apk.sh` and the Flask config.
