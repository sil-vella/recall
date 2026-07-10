# DR / update push pipeline (rop01)

Operator runbook for safely draining live traffic before stopping or updating Dutch app servers on rop01.

**Host:** `65.181.125.135` (hostname `reignofplay`)  
**URL:** `https://dutch.reignofplay.com`  
**App root:** `/opt/apps/reignofplay/dutch`

Drain is **two independent layers** that work together:

| Layer | Where it lives | What it does |
|-------|----------------|--------------|
| **Edge (nginx)** | **`rop01_server` repo** (not this repo) | Blocks new traffic at the reverse proxy before it reaches containers |
| **App (Flask + Dart)** | **This repo** (`app_dev`) | Graceful drain: reject new sessions, finish in-flight matches and store ops |

**Edge drain on rop01:** nginx snippet, `.draining` flag, SSH automation — documented and implemented in the **`rop01_server`** repository (*Dutch drain system (rop01)*). Use `automation/dutch_maintenance_mode/dutch_maintenance_mode.sh` there; do not configure nginx from this repo.

**Abort policy:** If poll times out, run app `exit-drain` and `dutch_maintenance_mode.sh --deactivate` on rop01. **Do not stop containers.**

---

## Repo split

| Concern | Repo |
|---------|------|
| Nginx drain gate, `.draining` flag, `--activate` / `--deactivate` script | **`rop01_server`** |
| Flask/Dart drain mode, ops APIs, `ops_drain.py`, poll / `ready` | **This repo** (`app_dev`) |
| Docker compose stop / pull / up, image build (`06`/`07`/`08`) | VPS + [`playbooks/rop01/`](../../playbooks/rop01/) |
| Backup / restore | Separate repo (not part of this pipeline) |

---

## Architecture

```
Client ──► nginx (443, dutch.mt vhost)     ← edge drain: rop01_server
              ├──► Flask :5001   REST, billing, /service/ops/*
              └──► Dart  :8080   /ws, internal /service/ops/*

Dart container ──► Flask :5001   /service/* for active matches (container network)
```

During drain:

1. **Edge (rop01_server)** — `.draining` flag → nginx **503** on new public/userauth/ws traffic.
2. **Flask `ops_module` (this repo)** — `drain_mode`; 503 on blocked routes; aggregates readiness.
3. **Dart (this repo)** — rejects new WS and matchmaking; allows in-game play until matches end.

Edge-only drain blocks new clients at nginx but does **not** gracefully drain in-flight matches — use **both layers** for production maintenance.

---

## App codebase in this repo

| Component | Location |
|-----------|----------|
| Flask drain API + HTTP 503 gate | [`python_base_04/core/modules/ops_module/`](../../python_base_04/core/modules/ops_module/) |
| Dart WS drain mode + ops HTTP | [`dart_bkend_base_01/lib/server/`](../../dart_bkend_base_01/lib/server/) |
| Operator CLI | [`python_base_04/tools/ops_drain.py`](../../python_base_04/tools/ops_drain.py) |

---

## Combined maintenance flow

```
Phase 1a — Edge drain (rop01_server)
    dutch_maintenance_mode.sh --activate
         │
Phase 1b — App drain (this repo)
    ops_drain.py enter
         │
Phase 2 — Poll (this repo)
    ops_drain.py poll  →  ready=true
         │
Phase 3 — Stop / update (VPS)
    docker compose stop / pull / up
         │
Phase 4 — Bring back
    ops_drain.py exit  +  dutch_maintenance_mode.sh --deactivate
```

---

## Before running `ops_drain.py`

From a machine that can reach production (only requirement for the app-layer CLI):

```bash
cd app_dev
set -a && source .env.prod && set +a
export OPS_DRAIN_BASE_URL=https://dutch.reignofplay.com
```

`DART_BACKEND_SERVICE_KEY` must match the VPS `.env` (same key Flask accepts on `/service/*`).

Optional: confirm `/health` returns 200. Build/push images (`06`/`07`) only when this session includes a deploy.

---

## Phase 1 — Enter drain

### 1a. Edge drain — **`rop01_server` repo**

Run from the rop01_server checkout (see *Dutch drain system (rop01)* there):

```bash
./automation/dutch_maintenance_mode/dutch_maintenance_mode.sh --activate
./automation/dutch_maintenance_mode/dutch_maintenance_mode.sh --status
```

Creates `/opt/apps/reignofplay/dutch/.draining` and reloads nginx. **Does not** call app drain APIs.

Manual equivalent on VPS:

```bash
sudo touch /opt/apps/reignofplay/dutch/.draining
sudo nginx -t && sudo systemctl reload nginx
```

**Edge behavior when active** (implemented in rop01_server; verified on production):

| Path | Behavior |
|------|----------|
| `GET /health` | Pass through → **200** |
| `/service/*` | Pass through (401 without `X-Service-Key`; not blocked at edge) |
| `/downloads*` | Unchanged (static/nginx rules as before) |
| `/ws`, `/userauth/*`, `/public/*`, `/stripe/*`, SPA/static | **503** |

Nginx config reference: `rop01_server` → `nginx/dutch.mt.md`.

Legacy Ansible maintenance page (302 HTML): [`playbooks/rop01/16_dutch_maintenance.yml`](../../playbooks/rop01/16_dutch_maintenance.yml) — separate from edge drain; optional for user-facing message.

### 1b. App drain — **this repo**

Do **together with 1a** (nginx first or immediately after):

```bash
python3 python_base_04/tools/ops_drain.py enter --base-url "$OPS_DRAIN_BASE_URL"
```

Or `curl`:

```bash
curl -sS -X POST "$OPS_DRAIN_BASE_URL/service/ops/enter-drain" \
  -H "X-Service-Key: $DART_BACKEND_SERVICE_KEY" \
  -H "Content-Type: application/json"
```

**What this does:**

- Sets `main_state.drain_mode = true`, `app_status = maintenance`
- POSTs Dart `/service/ops/drain-mode` with `{"enabled": true}`
- Dart rejects new WS connections and matchmaking (`create_room`, `join_room`, `join_random_game`, `start_match`)
- Flask returns **503** (`DRAIN_MODE`) on blocked routes except allowlisted `/service/*` for in-flight matches

**Allowlisted Flask paths during drain:**

- `/health`, `/service/health`, `/service/ops/*`
- `/service/auth/validate`
- `/service/dutch/deduct-game-coins`, `update-game-stats`, `get-init-data`, `rematch-tournament-snapshot`, `attach-tournament-match-room`

---

## Phase 2 — Poll until ready

```bash
python3 python_base_04/tools/ops_drain.py poll \
  --base-url "$OPS_DRAIN_BASE_URL" \
  --max-wait 1800 \
  --interval 15 \
  --stable-polls 2
```

**Ready when:**

- `active_matches == 0` (Dart; `game_ended` does not count)
- `store_in_flight == 0` (`play_coin_purchases` with `status: "processing"`)
- `drain_mode == true`
- Two consecutive clear polls

**`ready` does not require zero connections** — `dart_connections` may be > 0 (post-game lobby).

**On timeout — abort:**

```bash
python3 python_base_04/tools/ops_drain.py exit --base-url "$OPS_DRAIN_BASE_URL"
# rop01_server: dutch_maintenance_mode.sh --deactivate
# Do NOT stop containers
```

Status:

```bash
python3 python_base_04/tools/ops_drain.py status --base-url "$OPS_DRAIN_BASE_URL"
```

**`GET /service/ops/drain-status` response shape:**

```json
{
  "drain_mode": true,
  "active_matches": 0,
  "store_in_flight": 0,
  "dart_connections": 1,
  "room_count": 1,
  "checks": { "matches_clear": true, "store_clear": true },
  "ready": true,
  "dart_reachable": true
}
```

---

## Phase 3 — Stop or update (VPS)

Only after `ready: true`. Documented on VPS / rop01_server; not automated from this repo.

### Update

```bash
cd /opt/apps/reignofplay/dutch
docker compose stop dutch_dart-game-server
docker compose pull
docker compose up -d
curl -sS http://127.0.0.1:5001/health
```

Or from dev machine: `ansible-playbook ... 08_deploy_docker_compose.yml -e vm_name=rop01`

### Drain-stop (no deploy)

```bash
docker compose stop dutch_dart-game-server dutch_flask-external
# Mongo + Redis keep running
```

---

## Phase 4 — Bring back online

1. App drain off (if still active):

   ```bash
   python3 python_base_04/tools/ops_drain.py exit --base-url "$OPS_DRAIN_BASE_URL"
   ```

2. Edge drain off — **`rop01_server` repo:**

   ```bash
   ./automation/dutch_maintenance_mode/dutch_maintenance_mode.sh --deactivate
   ```

3. Smoke checks:

   | Check | Expected |
   |-------|----------|
   | `curl …/health` | 200 |
   | `curl …/public/check-updates` | 200 |
   | `ops_drain.py status` | `drain_mode: false` |

---

## Verification

### Edge drain (rop01_server)

```bash
./automation/dutch_maintenance_mode/dutch_maintenance_mode.sh --status
# edge drain: ACTIVE (.../.draining)

curl -sS -o /dev/null -w '%{http_code}\n' https://dutch.reignofplay.com/health
# 200

curl -sS -o /dev/null -w '%{http_code}\n' https://dutch.reignofplay.com/public/check-updates
# 503

curl -sS -o /dev/null -w '%{http_code}\n' https://dutch.reignofplay.com/userauth/login
# 503

curl -sS -o /dev/null -w '%{http_code}\n' \
  https://dutch.reignofplay.com/service/ops/drain-status
# 401 without X-Service-Key (pass through at edge, not 503)

curl -sS -o /dev/null -w '%{http_code}\n' https://dutch.reignofplay.com/downloads/
# unchanged (e.g. 403 per static dir rules)
```

With service key, `/service/ops/drain-status` → **200**.

### App drain (this repo)

```bash
python3 python_base_04/tools/ops_drain.py status --base-url "$OPS_DRAIN_BASE_URL"
# ready: true when safe to stop containers (while drain_mode: true)
```

---

## API reference (app codebase)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/service/ops/enter-drain` | `X-Service-Key` | Enable drain (Flask + Dart) |
| POST | `/service/ops/exit-drain` | `X-Service-Key` | Disable drain |
| GET | `/service/ops/drain-status` | `X-Service-Key` | Readiness aggregate |
| POST | `/service/ops/drain-mode` | `X-Service-Key` | Dart only — `{"enabled": true\|false}` |
| GET | `/service/ops/drain-status` | `X-Service-Key` | Dart only — match/connection counts |

Dart WS event when blocked: `server_maintenance`.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Edge only, no app drain | In-flight matches not tracked; use both layers |
| In-flight IAP verify interrupted | Poll `store_in_flight == 0`; Flask blocks new verify |
| Stripe webhook 503 at edge | Stripe retries |
| Active match killed on hard stop | Poll `active_matches == 0` before Phase 3 |
| `ready` with open WS | Expected; connections ≠ active matches |

---

## Local dev test (no nginx)

Skip Phase 1a; app drain only:

```bash
set -a && source .env.local && set +a
export OPS_DRAIN_BASE_URL=http://127.0.0.1:5001
# MONGODB_DIRECT_CONNECTION=true when host Flask → Docker Mongo on :27018
# DART_BACKEND_NOTIFY_URL=http://127.0.0.1:8080

python3 python_base_04/tools/ops_drain.py enter
python3 python_base_04/tools/ops_drain.py poll --max-wait 120 --interval 5
python3 python_base_04/tools/ops_drain.py exit
```

---

## Related docs

| Doc | Scope |
|-----|--------|
| **`rop01_server`** — *Dutch drain system (rop01)* | Edge drain, nginx, `dutch_maintenance_mode.sh`, verification |
| [`PRODUCTION_SYSTEM.md`](PRODUCTION_SYSTEM.md) | Architecture, deploy flow, logging |
| [`playbooks/rop01/00_documentation_and_instructions.md`](../../playbooks/rop01/00_documentation_and_instructions.md) | Image build + `08_deploy` |
