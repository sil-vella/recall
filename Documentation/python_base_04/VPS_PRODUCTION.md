# Flask VPS production operations

Reference for running the Dutch Flask API on the VPS (`dutch_flask-external` / `dutch_external_app_flask`). Covers logging, health checks, caching, metrics, nginx tuning, and incident grep patterns.

Related deploy docs: [`playbooks/rop01/00_documentation_and_instructions.md`](../../playbooks/rop01/00_documentation_and_instructions.md).

---

## Process model (Gunicorn)

Configured in [`python_base_04/gunicorn.conf.py`](../../python_base_04/gunicorn.conf.py), env overrides in VPS `.env`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `GUNICORN_WORKERS` | `2` | Worker processes |
| `GUNICORN_THREADS` | `4` | Threads per worker (`gthread`) |
| `GUNICORN_TIMEOUT` | `60` | Kill stuck workers (seconds) |

Game WebSocket traffic uses the **Dart** container (`/ws` → `:8080`). Flask handles REST + internal `/service/*` from Dart.

---

## Where logs live

### Flask (primary for API + `/service/*`)

```bash
cd /opt/apps/reignofplay/dutch
docker compose logs -f dutch_flask-external
# or
docker logs -f dutch_external_app_flask
```

**Gunicorn access log** (stdout): every request including internal `POST /service/auth/validate`. Last field is duration in **microseconds** (`%(D)s`).

**Gunicorn error log** (stdout): worker lifecycle, `[CRITICAL] WORKER TIMEOUT (pid:N)`.

**Slow requests** (stdout): `[WARNING] slow_request method=... path=... status=... duration_ms=...` when above `SLOW_REQUEST_THRESHOLD_MS` (default `5000`).

Docker log rotation (compose): `json-file`, `max-size=10m`, `max-file=5` per service.

### Nginx (client-facing HTTP)

Typically under `/var/log/nginx/` (e.g. `dutch.mt.access.log`, rotated `.1` files). Shows status codes (`504`, `499`), client IP, path — **not** internal Dart→Flask calls.

### Dart game server

```bash
docker compose logs -f dutch_dart-game-server
```

Sparse unless `DUTCH_DEV_LOG=1`. For WS upgrades use nginx access log (`GET /ws` → `101`).

---

## Useful grep patterns

On VPS after an incident:

```bash
# Worker hang / recycle
docker compose logs dutch_flask-external 2>&1 | grep -E 'WORKER TIMEOUT|CRITICAL'

# Slow internal auth (microseconds > 60_000_000 ≈ 60s)
docker compose logs dutch_flask-external 2>&1 | grep 'service/auth/validate'

# App slow-request warnings
docker compose logs dutch_flask-external 2>&1 | grep slow_request

# Nginx upstream timeouts
sudo grep ' 504 ' /var/log/nginx/dutch*.access.log*
```

---

## Health checks

- **HTTP:** `GET http://127.0.0.1:5001/health` — returns `healthy` or `degraded` (200) or `unhealthy` (503).
- **Docker:** compose + Dockerfile healthcheck curls same endpoint every 30s.
- **Deploy:** `08_deploy_docker_compose.yml` fails if `/health` is not `healthy` or `degraded` after `compose up`.

Deployed image tag recorded at: `/opt/apps/reignofplay/dutch/.deployed_image_tag`

---

## Metrics

- **Endpoint:** `GET /metrics` (Prometheus text format).
- **Access:** restricted to `METRICS_ALLOWED_CIDRS` (default `127.0.0.1,172.16.0.0/12`). Public nginx must **not** expose `/metrics`.
- **Custom collector:** enabled when `METRICS_COLLECTION_ENABLED=true` (default in prod `.env`).

Verify from inside the Flask container:

```bash
docker exec dutch_external_app_flask curl -sf http://127.0.0.1:5001/health
docker exec dutch_external_app_flask curl -sf http://127.0.0.1:5001/metrics | head
```

---

## Redis read cache

Hot-path caching (multi-worker safe), prefix `dutch:cache:`:

| Key pattern | TTL env | Purpose |
|-------------|---------|---------|
| `init_stats:{user_id}` | `DUTCH_CACHE_INIT_STATS_TTL` (30s) | `get-init-data` user stats |
| `catalog:{type}:{revision}` | `DUTCH_CACHE_CATALOG_TTL` (3600s) | Built catalog JSON blobs |
| `broadcast:{user_id}:{rank}` | `DUTCH_CACHE_BROADCAST_TTL` (60s) | Global broadcast payload |

Toggle: `DUTCH_REDIS_READ_CACHE_ENABLED=true`

Invalidation: `init_stats` cleared on `update_game_stats`; `catalog:*` cleared on `reload-catalogs`.

**Not cached:** `POST /service/auth/validate` (token validity).

---

## Nginx manual checklist

Apply when editing `/etc/nginx/sites-available/dutch.reignofplay.com` (or current vhost):

| Setting | Recommended | Why |
|---------|-------------|-----|
| `proxy_read_timeout` | `65s` | Just above Gunicorn `60s` |
| `proxy_connect_timeout` | `10s` | Fast fail on dead upstream |
| Static `/app_media/`, `/public/` | `expires 7d` where assets are versioned | Offload Flask |
| `/metrics` | `deny all;` or omit location | Metrics are internal only |
| JWT / userauth routes | **Do not** `proxy_cache` | User-specific responses |

API upstream: `http://127.0.0.1:5001`  
WebSocket upstream: `http://127.0.0.1:8080` (`/ws`)

---

## Build and deploy tags

### Release flow (unchanged numbering)

```bash
cd app_dev
python3 playbooks/rop01/06_build_and_push_docker.py   # Flask → upserts FLASK_IMAGE_TAG in .env.prod
python3 playbooks/rop01/07_build_and_push_dart_docker.py   # Dart → upserts DART_IMAGE_TAG in .env.prod
ansible-playbook -i playbooks/rop01/inventory.ini \
  playbooks/rop01/08_deploy_docker_compose.yml \
  -e vm_name=rop01
```

Step **08** resolves image tags from `app_dev/.env.prod` (no manual `-e` unless overriding):

1. `-e flask_image_tag=...` / `-e dart_image_tag=...` if passed
2. `FLASK_IMAGE_TAG` / `DART_IMAGE_TAG` in `app_dev/.env.prod` (written by steps **06** and **07**)
3. Shell `FLASK_IMAGE_TAG` / `DART_IMAGE_TAG` if set
4. `latest`

After deploy, running Flask tag: `/opt/apps/reignofplay/dutch/.deployed_image_tag`

---

## What we do not log in production

- JWT / refresh tokens
- Passwords or request bodies with credentials
- Full tracebacks unless `LOG_TRACEBACKS=true`

Dev tracing (`customlog`, `DUTCH_DEV_LOG`) remains off on VPS; use Gunicorn access logs instead.
