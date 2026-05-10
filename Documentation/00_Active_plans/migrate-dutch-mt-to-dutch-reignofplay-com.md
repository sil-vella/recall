# Migrate production canonical host: dutch.reignofplay.com → dutch.reignofplay.com

**Status**: In Progress  
**Created**: 2026-05-10  
**Last Updated**: 2026-05-10

## Objective

Make **https://dutch.reignofplay.com** the only canonical public URL for the Dutch app (API, web, downloads, WS). Retire **dutch.reignofplay.com** from product surfaces, redirects, and configs in controlled steps without breaking shipped clients until the final cutover.

## Implementation steps

- [x] **Step 1 — Repo defaults + CORS (dual-origin)**: Defaults and build scripts use `dutch.reignofplay.com`. Flask CORS allows **both** `dutch.reignofplay.com` and `dutch.reignofplay.com` so old and new origins work during migration.
- [x] **Step 2 — Production env + redeploy**: `.env.prod` + deploy playbook push updated download base and Stripe return URLs; `docker-compose.yml` already sets `APP_URL`; VPS `.env` regenerated and compose pulled/up via `08_deploy_docker_compose.yml` with `-e vps_deploy_skip_compose_confirm=true`.
- [ ] **Step 3 — Nginx / TLS / redirects** (manual on VPS): Make `dutch.reignofplay.com` the primary `server_name`; **301** from `dutch.reignofplay.com` and `www.dutch.reignofplay.com` to the new host; adjust Certbot if needed. Repo no longer ships `04_*` nginx bootstrap—only `16_dutch_maintenance*.yml` touch nginx snippets for Dutch.
- [ ] **Step 4 — External consoles**: Google OAuth, Stripe (return URLs / webhooks), RevenueCat, Play/App Store listings, DNS — align with the new host.
- [ ] **Step 5 — Remove dutch.reignofplay.com**: Drop `dutch.reignofplay.com` / `www.dutch.reignofplay.com` from CORS, playbooks, docs, and sample JSON; optional DB backfill of stored URLs; remove nginx `server_name` for old host when traffic is gone.

## Current progress

Steps 1–2 done: repo defaults, dual CORS, `.env.prod` canonical URLs, non-interactive deploy flag, VPS `.env` + compose redeployed.

## Next steps

Step 3: Nginx 301 from `dutch.reignofplay.com` / `www.dutch.reignofplay.com` to `dutch.reignofplay.com` (and optional cert primary rename).

## Files modified

_(Updated after each step.)_

- Step 1: `python_base_04/app.py`, `docker-compose.yml`, `playbooks/rop01/templates/env.j2`, `playbooks/rop01/08_deploy_docker_compose.yml`, `playbooks/rop01/group_vars/rop01_user/vault.yml.example`, `flutter_base_05/build.py`, `playbooks/frontend/build_web.sh`, `build_apk.sh`, `build_appbundle.sh`, `launch_chrome.sh`, `launch_oneplus.sh`, `launch_android_debug.sh`, `python_base_04/utils/config/config.py`, `python_base_04/utils/config/CONFIG_SOURCES.md`, `playbooks/rop01/11_add_players.py`, `12_upload_card_back_image.py`, `13_upload_table_logo_image.py`, `15_upload_promotional_bundle.py`
- Step 2: `.env.prod` (download base + Stripe checkout URLs), `Documentation/security/ENV_SETUP_LOCAL_AND_DOCKER.md`, `08_deploy_docker_compose.yml` (`vps_deploy_skip_compose_confirm` for non-interactive pull/up)

## Notes

- Nginx vhost playbooks (`04_setup_nginx.yml`, `04b_update_nginx_site_templates.yml`) and `templates/nginx-site.conf.j2` were removed; vhost changes are SSH/manual. `16_dutch_maintenance*.yml` still edit `/etc/nginx/sites-available/dutch.reignofplay.com` for maintenance mode.
- `.env.prod` is local/secret — keep URLs aligned when changing canonical host.
