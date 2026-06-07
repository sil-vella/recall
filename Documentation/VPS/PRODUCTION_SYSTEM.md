# VPS production system

Operations reference for the Dutch stack on the VPS (`rop01`): hardened Gunicorn, versioned Docker deploys, observability via container stdout, and incident grep patterns.

**Related docs**

| Doc | Scope |
|-----|--------|
| [`playbooks/rop01/00_documentation_and_instructions.md`](../../playbooks/rop01/00_documentation_and_instructions.md) | Ansible deploy playbooks |
| [`Documentation/python_base_04/VPS_PRODUCTION.md`](../python_base_04/VPS_PRODUCTION.md) | Flask-focused quick reference (nginx checklist, cache keys) |
| [`Documentation/Logging/LOGGING_SYSTEM.md`](../Logging/LOGGING_SYSTEM.md) | Local dev only (`customlog`, `DUTCH_DEV_LOG`, `global.log`) |

---

## Why this exists

A production incident (June 2026) showed:

- Flask ran as **one Gunicorn sync worker** with a **120s timeout** and **no request access logging**.
- A stuck worker produced `WORKER TIMEOUT` while Dart kept calling `/service/auth/validate` — clients saw auth/lobby failures and ghost waiting rooms.

The current system addresses that with:

| Area | Before | Now |
|------|--------|-----|
| Gunicorn | 1 sync worker, 120s timeout | 2 `gthread` workers, 4 threads each, 60s timeout |
| Request logging | None | Access log on stdout with duration (`%(D)s` µs) |
| Slow paths | Invisible | `[WARNING] slow_request …` above threshold |
| Worker hangs | Hard to diagnose | `[CRITICAL] WORKER TIMEOUT` + access lines with timing |
| Deploy tags | `:latest` only | Versioned `{APP_VERSION}-{git_sha}` in `.env.prod` |
| Health | Manual | Compose healthcheck + deploy assert on `/health` |

---

## Architecture on the VPS

**App root:** `/opt/apps/reignofplay/dutch`

| Container | Image | Port | Role |
|-----------|-------|------|------|
| `dutch_external_app_flask` | `silvella/dutch_flask_app:${FLASK_IMAGE_TAG}` | 5001 | REST API, `/service/*` (Dart → Flask) |
| `dutch_dart_game_server` | `silvella/dutch_dart_game_server:${DART_IMAGE_TAG}` | 8080 | WebSocket game server |
| `dutch_external_app_mongodb` | `bitnami/mongodb:latest` | 27018 | Database |
| `dutch_external_app_redis` | `redis:8-alpine` | 6380 | Cache / pub-sub |

**Traffic**

```
Mobile app ──► nginx (443) ──► Flask :5001  (REST, auth, init-data)
                         └──► Dart  :8080  (/ws game)
Dart container ──► Flask :5001  (internal /service/* — not in nginx logs)
```

Gunicorn config: [`python_base_04/gunicorn.conf.py`](../../python_base_04/gunicorn.conf.py)  
Runtime helpers: [`python_base_04/utils/prod_runtime.py`](../../python_base_04/utils/prod_runtime.py)

---

## Release and deploy

### Flow

```bash
cd app_dev
python3 playbooks/rop01/06_build_and_push_docker.py   # Flask → upserts FLASK_IMAGE_TAG in .env.prod
python3 playbooks/rop01/07_build_and_push_dart_docker.py   # Dart → upserts DART_IMAGE_TAG in .env.prod
ansible-playbook -i playbooks/rop01/inventory.ini \
  playbooks/rop01/08_deploy_docker_compose.yml \
  -e vm_name=rop01
```

Non-interactive deploy (skip compose prompt):

```bash
ansible-playbook ... -e vps_deploy_skip_compose_confirm=true
```

### Image tag SSOT

Build scripts write tags into **`app_dev/.env.prod`** (only `FLASK_IMAGE_TAG` / `DART_IMAGE_TAG` lines are upserted):

```
FLASK_IMAGE_TAG=2.0.40-e78c587d
DART_IMAGE_TAG=2.0.40-e78c587d
```

Playbook **08** reads those keys and templates them into the VPS `.env`. Deploy resolution order:

1. `-e flask_image_tag=...` / `-e dart_image_tag=...` (override)
2. Values from `app_dev/.env.prod`
3. Shell `FLASK_IMAGE_TAG` / `DART_IMAGE_TAG`
4. `latest`

After a successful deploy, the running Flask tag is also stored at:

```text
/opt/apps/reignofplay/dutch/.deployed_image_tag
```

Each build pushes **one new image** under two tags: the versioned tag and `:latest`. Old versioned tags may remain on Docker Hub but are not re-pushed.

---

## Logging system

### Design

Production observability is **Docker stdout**, not `global.log` or `customlog`.

| Source | On VPS? | Notes |
|--------|---------|-------|
| Gunicorn access + error | Yes | Primary signal for API and `/service/*` |
| Flask `slow_request` / `internal_error` | Yes | Stdlib logging to stdout |
| `customlog` / `DUTCH_DEV_LOG` | **No** | Disabled at build (06/07) and not used in prod |
| JWT, passwords, request bodies | **Never** | By policy |

Docker log driver: `json-file`, `max-size=10m`, `max-file=5` per service (see [`docker-compose.yml`](../../docker-compose.yml)).

### Log types

#### 1. Gunicorn access log (every HTTP request)

```bash
cd /opt/apps/reignofplay/dutch
docker compose logs -f dutch_flask-external
```

Example:

```text
172.18.0.2 - - [06/Jun/2026:12:35:13 +0000] "POST /service/dutch/get-init-data HTTP/1.1" 200 17908 "-" "Dart/3.12 (dart:io)" 19396
127.0.0.1 - - [06/Jun/2026:12:35:45 +0000] "GET /health HTTP/1.1" 200 983 "-" "curl/8.14.1" 4802
```

**Last field = duration in microseconds** (`%(D)s`):

| Value | Meaning |
|-------|---------|
| `19396` | ~19 ms |
| `5000000` | 5 s |
| `60000000` | 60 s (Gunicorn timeout territory) |

Includes **internal** Dart→Flask calls (`/service/auth/validate`, `/service/dutch/*`) that never appear in nginx access logs.

#### 2. Gunicorn error log (worker lifecycle)

```text
[CRITICAL] WORKER TIMEOUT (pid:123)
```

Grep:

```bash
docker compose logs dutch_flask-external 2>&1 | grep -E 'WORKER TIMEOUT|CRITICAL'
```

#### 3. Slow request warnings (Flask)

Logged when handler time exceeds `SLOW_REQUEST_THRESHOLD_MS` (default **5000**):

```text
[WARNING] slow_request method=POST path=/service/auth/validate status=200 duration_ms=61234
```

Implementation: `@app.after_request` in [`python_base_04/app.py`](../../python_base_04/app.py).

Grep:

```bash
docker compose logs dutch_flask-external 2>&1 | grep slow_request
```

#### 4. Internal server errors (500)

Default (`LOG_TRACEBACKS=false`):

```text
[ERROR] internal_error method=POST path=/api/example type=ValueError
```

With `LOG_TRACEBACKS=true`: full Python traceback via `logger.exception`.

**Prod practice:** keep `LOG_TRACEBACKS=false`. Enable only as **break-glass** during an active incident (reproduce → capture → turn off → redeploy). Always-on tracebacks in Docker logs risk leaking paths, library details, and occasionally sensitive values in stack frames.

#### 5. Nginx (client-facing only)

Typically `/var/log/nginx/` (e.g. `dutch*.access.log`). Shows client IP, status (`504`, `499`), public paths — **not** internal `/service/*`.

```bash
sudo grep ' 504 ' /var/log/nginx/dutch*.access.log*
sudo grep 'GET /ws' /var/log/nginx/dutch*.access.log*   # WebSocket upgrades (expect 101)
```

Recommended nginx timeouts: `proxy_read_timeout 65s` (just above Gunicorn `60s`). See [`VPS_PRODUCTION.md`](../python_base_04/VPS_PRODUCTION.md).

#### 6. Dart game server

```bash
docker compose logs -f dutch_dart-game-server
```

Sparse in production unless dev logging is enabled at build time. WS issues: use nginx `GET /ws` lines and Flask logs for auth/init-data, not Dart stdout alone.

---

## How to check logging (cheat sheet)

SSH to the VPS, then:

```bash
cd /opt/apps/reignofplay/dutch

# Live tail (Flask — main ops view)
docker compose logs -f dutch_flask-external

# Last 100 lines
docker compose logs --tail=100 dutch_flask-external

# What image is running
cat .deployed_image_tag
docker compose ps

# Health
curl -sf http://127.0.0.1:5001/health | python3 -m json.tool

# Metrics (internal CIDR only; from inside container)
docker exec dutch_external_app_flask curl -sf http://127.0.0.1:5001/metrics | head
```

### Incident grep patterns

```bash
cd /opt/apps/reignofplay/dutch

# Worker hang / recycle
docker compose logs dutch_flask-external 2>&1 | grep -E 'WORKER TIMEOUT|CRITICAL'

# Auth validate slowness (last column = µs; > 60000000 ≈ 60s)
docker compose logs dutch_flask-external 2>&1 | grep 'service/auth/validate'

# App slow-request warnings
docker compose logs dutch_flask-external 2>&1 | grep slow_request

# 500 errors (type/path only unless LOG_TRACEBACKS=true)
docker compose logs dutch_flask-external 2>&1 | grep internal_error

# Nginx upstream timeouts
sudo grep ' 504 ' /var/log/nginx/dutch*.access.log*
```

---

## Environment variables (VPS `.env`)

Templated from [`playbooks/rop01/templates/env.j2`](../../playbooks/rop01/templates/env.j2). Controller SSOT: `app_dev/.env.prod`.

### Gunicorn

| Variable | Default | Purpose |
|----------|---------|---------|
| `GUNICORN_WORKERS` | `2` | Worker processes |
| `GUNICORN_THREADS` | `4` | Threads per worker (`gthread`) |
| `GUNICORN_TIMEOUT` | `60` | Kill stuck workers (seconds) |

### Logging / errors

| Variable | Default | Purpose |
|----------|---------|---------|
| `SLOW_REQUEST_THRESHOLD_MS` | `5000` | Flask slow-request warning threshold |
| `LOG_TRACEBACKS` | `false` | Full 500 tracebacks (break-glass only) |

### Docker images

| Variable | Set by | Purpose |
|----------|--------|---------|
| `FLASK_IMAGE_TAG` | `06_build_and_push_docker.py` | Flask compose image tag |
| `DART_IMAGE_TAG` | `07_build_and_push_dart_docker.py` | Dart compose image tag |

### Metrics

| Variable | Default | Purpose |
|----------|---------|---------|
| `METRICS_COLLECTION_ENABLED` | `true` | Custom Prometheus collector |
| `METRICS_ALLOWED_CIDRS` | `127.0.0.1,172.16.0.0/12` | Who may call `GET /metrics` |

Do **not** expose `/metrics` on public nginx.

### Redis read cache

| Variable | Default | Purpose |
|----------|---------|---------|
| `DUTCH_REDIS_READ_CACHE_ENABLED` | `true` | Master toggle |
| `DUTCH_CACHE_INIT_STATS_TTL` | `30` | `get-init-data` stats |
| `DUTCH_CACHE_CATALOG_TTL` | `3600` | Catalog blobs |
| `DUTCH_CACHE_BROADCAST_TTL` | `60` | Broadcast payload |

**Not cached:** `POST /service/auth/validate`.

Details: [`VPS_PRODUCTION.md`](../python_base_04/VPS_PRODUCTION.md).

---

## Health checks

| Layer | Check |
|-------|--------|
| HTTP | `GET /health` → `healthy` or `degraded` (200), `unhealthy` (503) |
| Docker | Compose + Dockerfile healthcheck every 30s |
| Deploy | `08_deploy_docker_compose.yml` fails if `/health` bad after `compose up` |

---

## Dev vs production logging

| | Local dev | VPS production |
|--|-----------|----------------|
| API | `customlog` + `DUTCH_DEV_LOG=1` → `global.log` | Off |
| Flask requests | Optional dev tooling | Gunicorn access log (stdout) |
| Dart WS | Verbose with dev defines | Minimal stdout |
| Tracebacks | Full in debug | `LOG_TRACEBACKS=false` unless break-glass |

Launch scripts: [`playbooks/frontend/run_*_to_global_log.sh`](../../playbooks/frontend/) — **not used on VPS**.

---

## Temporary: enable full 500 tracebacks

Only during an active investigation:

1. Set `LOG_TRACEBACKS=true` in `app_dev/.env.prod` (or pass via Ansible).
2. Redeploy with playbook **08**.
3. Reproduce the error once; save relevant log lines.
4. Set `LOG_TRACEBACKS=false` and redeploy again.

Do not leave enabled as baseline prod config.
