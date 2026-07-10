# VPS backup strategy (rop01)

What to back up from the production VPS for the current Dutch stack: bind-mounted data, static files, secrets, and MongoDB. Containers and Docker images are **not** the backup target — host paths and logical DB dumps are.

**Related docs**

| Doc | Scope |
|-----|--------|
| [`PRODUCTION_SYSTEM.md`](PRODUCTION_SYSTEM.md) | Architecture, deploy flow, logging |
| [`playbooks/rop01/08a_reset_db_redis_data.yml`](../../playbooks/rop01/08a_reset_db_redis_data.yml) | Optional `mongodb.bak.*` / `redis.bak.*` tar before credential reset only |
| [`playbooks/rop01/00_documentation_and_instructions.md`](../../playbooks/rop01/00_documentation_and_instructions.md) | Deploy playbooks and VPS layout |

**App root:** `/opt/apps/reignofplay/dutch`  
**Nginx docroot:** `/var/www/dutch.reignofplay.com`

---

## Mental model

| Layer | Where it lives | Back up? |
|-------|----------------|----------|
| App code | Docker Hub images (`silvella/dutch_*`) | No — rebuild from `06`/`07` + git |
| Runtime config | VPS `.env` + `data/secrets/` | **Yes** |
| SSOT data | Mongo `external_system` | **Yes — top priority** |
| User uploads | `data/avatars/` | **Yes** |
| Public static | `/var/www/dutch.reignofplay.com/` | **Yes** (partially in repo) |
| Cache / sessions | Redis AOF under `data/redis/data` | Optional |
| Nginx / TLS | `/etc/nginx/`, Let's Encrypt | Medium priority |
| Compose file | `docker-compose.yml` on VPS | Low — same as repo after `08_deploy` |

Containers are disposable. Back up **host paths they mount**, not container filesystems.

---

## Tier 1 — Must back up

Data loss here means real user or business impact.

### 1. MongoDB (`external_system`)

**Path:** `/opt/apps/reignofplay/dutch/data/mongodb/data/db`  
**Preferred method:** `mongodump` (logical, portable). Raw WiredTiger dir tar is a secondary option only.

Mongo is SSOT for:

- `users` — accounts, coins, levels, tiers, progression
- `comp_players`, games/wins, `dutch_match_win_outcomes`
- `tournaments`, `leaderboards`
- Purchase ledgers: `play_coin_purchases`, `apple_coin_purchases`, subscriptions, `credit_purchases`, `failed_payments`
- `notifications`, `admob_rewarded_claims`, audit/event collections

**Cadence:** daily (or every 6–12h with active users).  
**Retention:** 7–30 daily, 4 weekly, 1 monthly.  
**Destination:** off-VPS (laptop, S3, Backblaze, second machine). On-disk-only backups do not protect against ransomware or total VPS loss.

Example (Mongo running, credentials from VPS `.env`):

```bash
# On rop01 (after: set -a && source /opt/apps/reignofplay/dutch/.env && set +a)
STAMP=$(date +%F-%H%M)
DUMP_DIR="/tmp/mongodump-${STAMP}"

docker exec dutch_external_app_mongodb mongodump \
  -u external_app_user -p "${MONGODB_PASSWORD}" \
  --authenticationDatabase external_system \
  -d external_system \
  -o "/tmp/dump-${STAMP}"

docker cp "dutch_external_app_mongodb:/tmp/dump-${STAMP}" "${DUMP_DIR}"
tar -czf "/tmp/mongodump-${STAMP}.tar.gz" -C /tmp "dump-${STAMP}"
# scp/rsync off-box, then remove /tmp artifacts on VPS
```

### 2. Secrets and environment

| Path | Contents |
|------|----------|
| `/opt/apps/reignofplay/dutch/.env` | JWT, DB/Redis passwords, Stripe, Google OAuth, service keys, image tags |
| `/opt/apps/reignofplay/dutch/data/secrets/` | `apple-iap-key.p8`, Google Play service account JSON, etc. |

Local `app_dev/.env.prod` and gitignored secrets may mirror this, but **the VPS is live truth** — back up encrypted, off-box.

**Cadence:** on every credential change + weekly snapshot.

### 3. User avatars

**Path:** `/opt/apps/reignofplay/dutch/data/avatars/`  
Profile images uploaded by users — not stored in Mongo blobs; not fully in git.

**Cadence:** daily, or bundle with the Mongo backup job.

---

## Tier 2 — Important

Painful to rebuild; only partly recoverable from the repo.

### 4. Nginx static tree

**Path:** `/var/www/dutch.reignofplay.com/`

| Subtree | What | In repo? |
|---------|------|----------|
| `downloads/` | Released APKs | Maybe locally from `build_apk.sh` |
| `app_media/` | Promotional ads, card backs, table designs, event media | Partially (`app_media/` + upload scripts) |
| `sim_players/images/` | Comp player images | Upload via `11_add_players.py` |
| Landing (`index.html`, `static_landing_*`) | Marketing site | Yes (`website/`) |

**Cadence:** weekly tar, or after any upload playbook (`12`–`18`, `15`).

### 5. Small app data files

| Path | Purpose |
|------|---------|
| `/opt/apps/reignofplay/dutch/data/mobile_release.json` | Force-update manifest |
| `/opt/apps/reignofplay/dutch/.deployed_image_tag` | Running Flask image tag |

Include in the same weekly archive.

### 6. Nginx and TLS

**Paths:** `/etc/nginx/sites-enabled/` (or site includes), certbot certs under `/etc/letsencrypt/`  
Maintained manually on the server (not by current deploy playbooks). Loss means downtime until nginx is re-edited and certs re-issued.

**Cadence:** after nginx changes + monthly snapshot.

---

## Tier 3 — Optional / low value

### 7. Redis

**Path:** `/opt/apps/reignofplay/dutch/data/redis/data`  
Cache, init-stats cache, ephemeral session markers — rebuilds from Mongo after restore. Weekly tar only if warm cache matters; not critical for disaster recovery.

### 8. Docker logs

Compose uses `json-file` with `max-size: 10m`, `max-file: 5`. Useful for incidents, not DR.

### 9. Raw Mongo data dir (08a-style tar)

[`08a_reset_db_redis_data.yml`](../../playbooks/rop01/08a_reset_db_redis_data.yml) can tar `data/mongodb/` before a credential reset. Fine as a **secondary** backup, but:

- Harder to restore across Mongo versions/images
- Needs Mongo stopped or a filesystem snapshot for consistency

Use **`mongodump` as primary**; raw tar or provider snapshot as secondary.

---

## Tier 0 — Provider-level

Enable **VPS VM snapshot / automated backup** from the hosting panel (regardless of app-level backups):

- Weekly full snapshot minimum
- Daily if cheaply available
- Keep at least one snapshot outside the same failure domain as live disk

A pre-incident snapshot would have avoided total data loss from the Jul 2026 Mongo ransomware event.

---

## Suggested minimum stack

```
Daily (cron on VPS):
  1. mongodump external_system → encrypted tar
  2. rsync/scp to off-VPS destination
  3. Include: .env, data/secrets/, data/avatars/

Weekly:
  4. tar /var/www/dutch.reignofplay.com/{downloads,app_media,sim_players}
  5. tar /etc/nginx/ + note certbot paths (or rely on provider snapshot)

Monthly:
  6. Test restore mongodump into local docker-compose.debug
  7. Verify one avatar URL, one APK URL, and a login flow
```

---

## Do not back up from VPS

| Item | Why |
|------|-----|
| Flask / Dart container images | On Docker Hub; tags in `app_dev/.env.prod` |
| Prometheus / Grafana dirs | Commented out in compose |
| Git repo | Source-controlled; `08_deploy` reproduces compose + `.env` template |
| Catalog JSON (`DUTCH_TABLES_JSON`, achievements, etc.) | In app image / repo; re-seed via `09`/`10` playbooks if needed |

---

## If you only do three things

1. **Daily `mongodump` off-VPS** (encrypted)
2. **Weekly VPS provider snapshot**
3. **Weekly tar of `data/secrets/` + `data/avatars/` + `/var/www/.../app_media` + `downloads`**

---

## Current gaps (as of Jul 2026)

- No scheduled backup playbook or cron on rop01
- `08a` archives (`mongodb.bak.*.tar.gz`) only exist if `08a_reset_db_redis` was run with `-e reset_db_redis=yes`
- No automated off-box copy

Automated backup can be added as `playbooks/rop01/backup_vps.yml` + a cron script when ready.
