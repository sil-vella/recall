# Environment Setup: Local Runs and Docker

This document describes how environment variables are loaded for **local development** (VS Code launch) and for **Docker** runs, so both use the same single source: `app_dev/.env`.

## Single source: `app_dev/.env`

All sensitive and environment-specific values live in:

```
app_dev/.env
```

- Used by **Docker Compose** and by **local launch configurations**.
- **Do not commit** `.env` if it contains real secrets (see `.gitignore`).
- Create from `.env.example` or copy from a secure location; playbooks create it on VPS.

## Docker runs

Compose reads `.env` from the project root (where `docker-compose.yml` lives, i.e. `app_dev/`).

### Flask (`dutch_flask-external`)

- **`env_file: .env`** — All variables from `app_dev/.env` are injected into the container.
- **`environment:`** — Selected vars are also set explicitly (e.g. `DART_BACKEND_SERVICE_KEY=${DART_BACKEND_SERVICE_KEY}`). `${VAR}` is resolved by Compose from the host environment (which Compose loads from `.env` when you run `docker-compose up`).

So Flask in Docker gets `JWT_SECRET_KEY`, `DART_BACKEND_SERVICE_KEY`, `MONGODB_*`, `REDIS_*`, `GOOGLE_*`, etc. from `.env`.

### Dart Game Server (`dutch_dart-game-server`)

- **`env_file: .env`**
- **`environment:`** — `PORT=8080`, `DART_BACKEND_SERVICE_KEY=${DART_BACKEND_SERVICE_KEY}`

So the Dart backend in Docker gets the same `DART_BACKEND_SERVICE_KEY` as Flask, required for Dart → Python service calls (e.g. `/service/auth/validate`).

### Summary (Docker)

| Service              | How it gets `.env` |
|----------------------|--------------------|
| dutch_flask-external | `env_file: .env` + `environment: ... ${VAR}` |
| dutch_dart-game-server | `env_file: .env` + `environment: - DART_BACKEND_SERVICE_KEY=${...}` |
| dutch_mongodb-external | `env_file: .env` + `environment: ...` |
| dutch_redis-external | `env_file: .env` + `environment: ...` |

## Local runs (VS Code launch)

When running **outside Docker** (e.g. Flask and Dart from VS Code), both processes must see the same variables from `app_dev/.env`. This is done via `.vscode/launch.json`.

### Flask Local Debug

- **Config:** `"Flask Local Debug"` in `launch.json`
- **Mechanism:** **`envFile`: `"${workspaceFolder}/.env"`**
- The Python debugger loads `app_dev/.env` into the process environment before starting `app.debug.py`.
- Flask (Config) then reads `JWT_SECRET_KEY`, `DART_BACKEND_SERVICE_KEY`, etc. from the environment.

### Start Dart Game Service

- **Config:** `"Start Dart Game Service"` in `launch.json`
- **Mechanism:** Shell command sources `.env` then runs Dart:
  ```bash
  set -a && source "${workspaceFolder}/.env" && set +a && cd "${workspaceFolder}/dart_bkend_base_01" && dart run app.debug.dart
  ```
- **`set -a`** — Export all variables that are set in the shell (so `source .env` exports every `KEY=value`).
- **`source "${workspaceFolder}/.env"`** — Load `app_dev/.env` (workspaceFolder is the repo root, e.g. `app_dev`).
- **`cwd`:** `"${workspaceFolder}"` so that the shell runs from the repo root where `.env` exists.

So Dart gets `DART_BACKEND_SERVICE_KEY` and any other vars it reads from the environment (e.g. from `Config` in Dart).

### Compound: Flask + Dart WebSocket (Full Stack)

- **Config:** `"Flask + Dart WebSocket (Full Stack)"` runs both **Flask Local Debug** and **Start Dart Game Service**.
- Both use the same `app_dev/.env`; no separate secret files are required for the service key when using this compound.

### Summary (Local)

| Process | How it gets `.env` |
|--------|---------------------|
| Flask  | `envFile`: `${workspaceFolder}/.env` in launch.json |
| Dart   | `set -a && source "${workspaceFolder}/.env" && set +a` in the launch command, `cwd`: `${workspaceFolder}` |

## Important variables

For Dart ↔ Python service auth and general app config, ensure these are set in `.env` (and match between Flask and Dart when both run):

| Variable | Used by | Purpose |
|----------|---------|---------|
| `DART_BACKEND_SERVICE_KEY` | Flask, Dart | Shared secret for Dart → Python calls (e.g. `/service/auth/validate`). Must be identical on both sides. |
| `JWT_SECRET_KEY` | Flask | JWT signing/verification. |
| `ENCRYPTION_KEY` | Flask | App encryption. |
| `MONGODB_*`, `REDIS_PASSWORD` | Flask, services | DB and cache (Docker or local). |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | Flask | Google OAuth. |

## Verification

- **Dart:** On each token validation request, the Dart backend logs (e.g. to `server.log`):  
  `Dart service key: usePythonServiceKey=..., key_configured=...`  
  Use `key_configured=true` to confirm the service key is set.
- **Python:** On each `/service/*` request, Python logs:  
  `Service auth: DART_BACKEND_SERVICE_KEY configured=..., X-Service-Key present=..., match=...`  
  Use `match=True` to confirm the key matches.

See also: [WEBSOCKET_JWT_FLOW.md](./WEBSOCKET_JWT_FLOW.md), [SECURITY_AND_AUTHENTICATION.md](./SECURITY_AND_AUTHENTICATION.md).
