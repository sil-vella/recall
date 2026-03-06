# Local Redis connection (Flask local, Redis in container)

When you run **Flask locally** (e.g. "Flask Local Debug" or "Flask + Dart WebSocket (Full Stack)" from `.vscode/launch.json`) but **Redis in a Docker container**, Flask must use host-accessible Redis host/port.

---

## Where Redis config comes from

| Source | File / mechanism |
|--------|------------------|
| **Config defaults** | `python_base_04/utils/config/config.py`: `REDIS_HOST` default = `redis-master-master.flask-app.svc.cluster.local`, `REDIS_PORT` = `6379` (K8s/production). |
| **Env vars** | Config uses `get_config_value(..., "REDIS_HOST", ...)` and `get_config_value(..., "REDIS_PORT", ...)` so **environment variables** override defaults. |
| **Launch** | "Flask Local Debug" uses `"envFile": "${workspaceFolder}/.env"` → Flask loads **`.env`** at workspace root. |
| **RedisManager** | `python_base_04/core/managers/redis_manager.py` → `_initialize_connection_pool()` reads `Config.REDIS_HOST`, `Config.REDIS_PORT`, `Config.REDIS_PASSWORD`. |

So for **local Flask**, set in **`.env`**:

- `REDIS_HOST=localhost`
- `REDIS_PORT=6380`

Container Redis is exposed as **6380:6379** in both `docker-compose.yml` and `docker-compose.debug.yml` (service `dutch_redis-external`, container name `dutch_external_app_redis`). From the host, use `localhost:6380`.

---

## Summary

- **Production (all in containers):** Flask container gets `REDIS_HOST=dutch_redis-external`, `REDIS_PORT=6379` from docker-compose `environment:`.
- **Local (Flask on host, Redis in container):** `.env` must set `REDIS_HOST=localhost` and `REDIS_PORT=6380` so Flask can reach the container. Without these, Config falls back to the K8s default hostname, which does not resolve locally → connection failed → token store/validity fails → 401 on `/userauth/` routes.
