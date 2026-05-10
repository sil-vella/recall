# Update check URL and manifest location

## Exact URL used to check updates

The app calls the backend with:

- **Path:** `GET /public/check-updates?current_version=<installed_version>`
- **Base URL:** From `API_URL` (compile-time `--dart-define=API_URL=...`).
  - **VPS APK (build_apk.sh default):** `https://dutch.reignofplay.com`
  - **Local build:** `http://10.0.2.2:8081` or value from env.

**Full URL (VPS):**
```text
https://dutch.reignofplay.com/public/check-updates?current_version=2.0.4
```
(No trailing slash; `current_version` is the app’s `PackageInfo.version`.)

**Code references:**
- Flutter: `flutter_base_05/lib/core/services/version_check_service.dart` → `route = '/public/check-updates?current_version=$currentVersion'`; URL = `Config.apiUrl` + route (`ConnectionsApiModule(baseUrl)` with `baseUrl` from `Config.apiUrl`).
- Backend: `python_base_04/core/modules/system_actions_module/system_actions_main.py` → `_register_route_helper("/public/check-updates", self.check_updates, methods=["GET"])`.

---

## Where the manifest file lives (VPS)

- **On the VPS:** The file is on the **host**, not baked into the image.
  - **Path on host:** `/opt/apps/reignofplay/dutch/data/mobile_release.json`
- **In the Flask container:** The same file is **bind-mounted** read-only:
  - **Path in container:** `/app/data/mobile_release.json`
  - **Env in container:** `MOBILE_RELEASE_MANIFEST=/app/data/mobile_release.json`
  - **Compose:** `docker-compose.yml` → `volumes: - /opt/apps/reignofplay/dutch/data/mobile_release.json:/app/data/mobile_release.json:ro`

So the file is **on the VPS host**; the container only sees it via the bind mount.  
`build_apk.sh` updates the **host** file (scp + ssh mv); no container rebuild is required for manifest changes.

---

## Expected manifest structure

Valid JSON with two keys (backend uses these and falls back to `Config.APP_VERSION` if missing):

```json
{
  "latest_version": "2.0.4",
  "min_supported_version": "2.0.4"
}
```

- `latest_version`: version of the APK offered for download.
- `min_supported_version`: if the app’s version is **below** this, the backend sets `update_required: true`.

---

## Verify on VPS

```bash
# Host file (source of truth)
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 'cat /opt/apps/reignofplay/dutch/data/mobile_release.json'

# Container (should match host via bind mount)
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 'docker exec dutch_external_app_flask cat /app/data/mobile_release.json'
```

If the container content does not match the host, recreate the Flask container so the mount is re-applied:

```bash
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 'cd /opt/apps/reignofplay/dutch && sg docker -c "docker compose up -d --force-recreate dutch_flask-external"'
```
