# Google Play Billing (server verify)

Server-side verification for **consumable coin packs** and **`premium_subscription`** uses the [Google Play Android Developer API](https://developers.google.com/android-publisher) (Android Publisher). The Flutter app completes purchases on-device; Flask validates purchase tokens and updates entitlements.

**SSOT for secrets:** repo root [`.env.prod`](../../.env.prod) (not Vault). Client builds use [`.env.dart.defines.prod`](../../.env.dart.defines.prod) only for Flutter dart-defines.

---

## 1. One-time: Play Console + service account

1. [Play Console → Setup → API access](https://play.google.com/console/developers/api-access)
2. Link or create a Google Cloud project; enable **Google Play Android Developer API**.
3. Create a **service account** → **Create new key** → JSON.
4. In Play Console, **Invite user** for that service account → grant access to app **`com.reignofplay.dutch`** with permissions to view financial/order data (subscriptions + in-app products).
5. Wait a few minutes for permissions to propagate.

Save the key locally (never commit):

```text
app_dev/secrets/google-play-publisher.json
```

See also [`secrets/README.md`](../../secrets/README.md).

---

## 2. `.env.prod` (deploy SSOT)

Add to **`.env.prod`** at repo root:

```bash
# Google Play — server verify (coins + premium_subscription)
GOOGLE_PLAY_PACKAGE_NAME=com.reignofplay.dutch
# Path inside the Flask container (must match docker-compose mount)
GOOGLE_PLAY_SERVICE_ACCOUNT_FILE=/app/secrets/google-play-publisher.json
```

Deploy flow: [`playbooks/rop01/08_deploy_docker_compose.yml`](../../playbooks/rop01/08_deploy_docker_compose.yml) reads `.env.prod` → templates [`env.j2`](../../playbooks/rop01/templates/env.j2) → VPS `/opt/apps/reignofplay/dutch/.env`.

[`python_base_04/utils/config/config.py`](../../python_base_04/utils/config/config.py) reads `GOOGLE_PLAY_*` from environment only.

---

## 3. VPS layout

| Host path | Container path |
|-----------|----------------|
| `/opt/apps/reignofplay/dutch/data/secrets/google-play-publisher.json` | `/app/secrets/google-play-publisher.json` |

[`docker-compose.yml`](../../docker-compose.yml) mounts `data/secrets` → `/app/secrets:ro` on `dutch_flask-external`.

Ansible **08_deploy** copies `secrets/google-play-publisher.json` from your laptop to `data/secrets/` on the VPS when the local file exists.

---

## 4. Deploy and restart

```bash
# From app_dev — run your usual rop01 deploy (08_deploy_docker_compose.yml)
# Then on VPS:
cd /opt/apps/reignofplay/dutch
docker compose up -d
# Recreate flask if volume/env changed:
docker compose up -d --force-recreate dutch_flask-external
```

---

## 5. Verify

**Module health** (no JWT):

```http
GET https://dutch.reignofplay.com/modules/play_billing_module/health
```

Expect `"status": "healthy"` and `"service_account_file_readable": true`.

If **degraded**, SSH:

```bash
docker exec dutch_external_app_flask ls -la /app/secrets/
docker exec dutch_external_app_flask printenv GOOGLE_PLAY_PACKAGE_NAME GOOGLE_PLAY_SERVICE_ACCOUNT_FILE
```

**App:** Account → **Premium** (subscribe or **Sync with server**) → tier **PREMIUM**; ads off via `AdExperiencePolicy`. Buy coins screen is coin packs only.

**API routes** ([`play_billing_main.py`](../../python_base_04/core/modules/play_billing_module/play_billing_main.py)):

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/userauth/play/verify-coin-purchase` | Consumable coins (+11% if tier is premium) |
| POST | `/userauth/play/verify-subscription` | Set `subscription_tier` = `premium` |
| GET | `/userauth/play/subscription-status` | Re-check stored token; lapse → `regular` |

---

## 6. Test purchases without real money

Official guide: [Test Google Play Billing](https://developer.android.com/google/play/billing/test)

- Add Gmail accounts under **Play Console → Settings → License testing**.
- Install from **internal test** (or license-tester sideload rules).
- Use **Test card, always approves** at checkout (test purchase banner shown).
- Test subscriptions renew faster (e.g. ~5 minutes for monthly).
- **Server verify still required** — license testers hit the same `verify-subscription` endpoint.

Optional: [Play Billing Lab](https://play.google.com/store/apps/details?id=com.google.android.apps.play.billingtestcompanion) for accelerated subscription states.

---

## 7. Recover after server was misconfigured

If Play charged but tier stayed `regular` because verify returned 503:

1. Fix steps 1–5 above.
2. In the app: **Buy coins** → **Sync with server** (restore purchases).
3. Or ops: set `modules.dutch_game.subscription_tier` to `premium` in Mongo (one-off).

---

## Related

- Premium + ads: [`Documentation/00_Active_plans/admob-subscription-tier-gating.md`](../00_Active_plans/admob-subscription-tier-gating.md)
- Product IDs: `premium_subscription`, base plans in `flutter_base_05/assets/dutch_coin_catalog.json`
