# Migration to dutch.mt (production domain)

Production is now **dutch.mt** instead of **dutch.reignofplay.com**. Below is what was changed and what you may still need to do on the server or in secrets.

## Summary of codebase changes

### 1. Python (Flask) – CORS
- **File:** `python_base_04/app.py`
- **Change:** Production CORS `origins` now include `https://dutch.mt` and `https://www.dutch.mt` (primary). `dutch.reignofplay.com` and reignofplay.com remain allowed.

### 2. Docker
- **File:** `docker-compose.yml`
- **Change:** `APP_URL=https://reignofplay.com` → `APP_URL=https://dutch.mt`

### 3. Flutter build
- **File:** `flutter_base_05/build.py`
- **Change:** `api_url = "https://dutch.reignofplay.com"` → `api_url = "https://dutch.mt"`

### 4. Playbooks – frontend (API_URL, WS_URL, URLs)
- **Files:**  
  `playbooks/frontend/launch_chrome.sh`,  
  `playbooks/frontend/launch_android_debug.sh`,  
  `playbooks/frontend/launch_oneplus.sh`,  
  `playbooks/frontend/build_web.sh`,  
  `playbooks/frontend/build_apk.sh`,  
  `playbooks/frontend/00_documentation.md`
- **Change:** Production `API_URL` and `WS_URL` now use `https://dutch.mt` and `wss://dutch.mt/ws`. Echo/expected URLs updated to dutch.mt. Upload paths remain `/var/www/dutch.reignofplay.com/...` (nginx serves dutch.mt from that root).

### 5. Playbooks – rop01
- **Files:**  
  `playbooks/rop01/00_documentation_and_instructions.md`,  
  `playbooks/rop01/11_add_players.py`,  
  `playbooks/rop01/12_upload_card_back_image.py`,  
  `playbooks/rop01/13_upload_table_logo_image.py`,  
  `playbooks/rop01/test_index.html`
- **Change:** All public-facing URLs (downloads, images, API, docs) now use `https://dutch.mt`. Doc updated so production = dutch.mt; server root path unchanged.

### 6. Comp player / asset URLs
- **Files:**  
  `playbooks/rop01/templates/comp_players.json`,  
  `playbooks/00_local/templates/comp_players.json`,  
  `Documentation/Dutch_game/COMP_PLAYER_IMPLEMENTATION.md`
- **Change:** All `https://dutch.reignofplay.com/...` picture/asset URLs replaced with `https://dutch.mt/...`.

### 7. Documentation
- **Files:** `Documentation/dutch_dashboard/PHP_ENV_VALUES.md`
- **Change:** Production API base URL example set to `https://dutch.mt`.

---

## What was not changed (by design)

- **Nginx site config** (`playbooks/rop01/04_setup_nginx.yml`): Both `dutch.mt` and `dutch.reignofplay.com` still use `root_dir: /var/www/dutch.reignofplay.com`. No change to domain list or paths.
- **Server paths:** Upload targets remain `/var/www/dutch.reignofplay.com/...` and `/opt/apps/reignofplay/dutch/...`. Only public URLs use dutch.mt.
- **cursor_automation** and **fmif.reignofplay.com**: Left as-is (other project).
- **reignofplay.com / www.reignofplay.com:** Unchanged; still point to `/var/www/reignofplay.com`.

---

## What you should do on the server / in secrets

1. **Secret `app_download_base_url`**  
   On the VPS, set the content of the file used for `APP_DOWNLOAD_BASE_URL` (e.g. `secrets/app_download_base_url`) to:
   ```text
   https://dutch.mt/downloads
   ```
   so the app update and download links use dutch.mt.

2. **Flask env (if you set APP_URL via env)**  
   If you override `APP_URL` in the Flask/Docker environment, set it to `https://dutch.mt`.

3. **Existing comp_players / assets**  
   If comp player or other asset URLs are stored in the DB or elsewhere (not only in the JSON templates), update those to `https://dutch.mt/...` where appropriate.

4. **Optional: retire dutch.reignofplay.com**  
   If you want to drop the old subdomain, you can remove the `dutch.reignofplay.com` block from `nginx_domains` in `04_setup_nginx.yml` and reload nginx. Keep the same `root_dir` for dutch.mt.

---

## Quick reference – production URLs

| Purpose        | URL |
|----------------|-----|
| Web app        | https://dutch.mt |
| API base       | https://dutch.mt |
| WebSocket      | wss://dutch.mt/ws |
| App downloads  | https://dutch.mt/downloads/v&lt;version&gt;/app.apk |
| Sim player pics| https://dutch.mt/sim_players/images/ |
| Sponsors (e.g. card back) | https://dutch.mt/sponsors/images/ |
