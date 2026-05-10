# Environment Setup: Local, Docker, and VPS

This document describes how environment variables are loaded for **local development** (VS Code launch), **Docker** runs, and **VPS deployment**, and where credentials come from.

## Single source for local and Docker: `app_dev/.env`

For local runs and for Docker Compose (when you run from `app_dev/`), all sensitive and environment-specific values live in:

```
app_dev/.env
```

- Used by **Docker Compose** and by **local launch configurations**.
- **Do not commit** `.env` if it contains real secrets (see `.gitignore`).
- Create it with the variable names listed in **VPS section** below (or from a secure copy). The playbook **creates** the VPS `.env` from a template; it does not copy `app_dev/.env` to the server.

## Where VPS credentials come from

On the VPS, the file `/opt/apps/reignofplay/dutch/.env` is **generated** by playbook `08_deploy_docker_compose.yml` from the template `playbooks/rop01/templates/env.j2`. Values are resolved in this order:

1. **Ansible variables** — e.g. `mongodb_root_password`, `redis_password`, `jwt_secret_key` (from `host_vars/`, `group_vars/`, vault, or `-e key=value`).
2. **Otherwise**: **Environment of the machine running Ansible** — `lookup('env', 'MONGODB_ROOT_PASSWORD')` etc. read from the shell where you run `ansible-playbook`.

So you can supply VPS creds in any of these ways:

| Method | How |
|--------|-----|
| **Automatic from `app_dev/.env`** | Run the playbook from `app_dev/`. The playbook **reads `app_dev/.env`** in a first play (localhost), parses it, and uses those values when generating the VPS `.env`. No manual paste or `source` needed. |
| **Use your shell environment** | From `app_dev/`: run `set -a && source .env && set +a`, then run the playbook. Exported vars are used if the file wasn’t read or a value was missing. |
| **Ansible-only** | Set vars in `playbooks/rop01/group_vars/rop01_user/vault.yml` (encrypted with Ansible Vault), or in host_vars (do not commit), or pass `-e mongodb_root_password=...` etc. |

Required variables for the template (see `playbooks/rop01/templates/env.j2`): `VPS_APP_UID`, `VPS_APP_GID`, `MONGODB_ROOT_PASSWORD`, `MONGODB_PASSWORD`, `REDIS_PASSWORD`, `JWT_SECRET_KEY`, `ENCRYPTION_KEY`, `DART_BACKEND_SERVICE_KEY`, `DUTCH_MT_DASHBOARD_SERVICE_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `APP_VERSION`, `APP_DOWNLOAD_BASE_URL`, and optionally `CREDIT_SYSTEM_API_KEY`. If not set, the template writes an empty value. **Bitnami Redis and MongoDB** require a password (or `ALLOW_EMPTY_PASSWORD=yes` in the compose file for development). For production, set real passwords via one of the methods above.

## Using Ansible Vault (most secure for VPS)

Store VPS secrets in an **encrypted** vars file so they are safe at rest and the repo can hold the encrypted file. Only someone with the vault password can deploy.

### 1. Create the vault file (one-time)

From the repo root (`app_dev/`):

```bash
mkdir -p playbooks/rop01/group_vars/rop01_user
ansible-vault create playbooks/rop01/group_vars/rop01_user/vault.yml
```

You will be prompted for a **vault password** (choose a strong one; store it in a password manager). Ansible will open an editor. Paste the variables below, replace placeholder values with your real secrets, then save and exit.

Variable names must match what `env.j2` expects (Ansible var names use lowercase and underscores):

```yaml
# VPS .env secrets (used by 08_deploy_docker_compose.yml via env.j2)
mongodb_root_password: "your-mongodb-root-password"
mongodb_password: "your-mongodb-app-user-password"
redis_password: "your-redis-password"
jwt_secret_key: "your-jwt-secret-key"
encryption_key: "your-encryption-key"
dart_backend_service_key: "your-dart-backend-service-key"
dutch_mt_dashboard_service_key: "your-dashboard-service-key"   # optional
google_client_id: "your-google-client-id"
google_client_secret: "your-google-client-secret"
app_version: "2.0.0"
app_download_base_url: "https://dutch.reignofplay.com/downloads"
# credit_system_api_key: ""   # optional
```

`VPS_APP_UID` and `VPS_APP_GID` are set by the playbook from the server user; do not put them in the vault.

### 2. Run the playbook with the vault password

Whenever you run a playbook that uses these vars (e.g. 08):

```bash
cd app_dev
ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01 --ask-vault-pass
```

Enter the vault password when prompted. Ansible decrypts the vars in memory and the template writes them into the VPS `.env` file.

### 3. Optional: vault password from a file

To avoid typing the password each time (e.g. in CI), use a password file with strict permissions:

```bash
echo -n 'your-vault-password' > playbooks/rop01/.vault_pass
chmod 600 playbooks/rop01/.vault_pass
# Add .vault_pass to .gitignore — never commit it
ansible-playbook ... --vault-password-file playbooks/rop01/.vault_pass
```

### 4. Edit or view the vault later

```bash
ansible-vault edit playbooks/rop01/group_vars/rop01_user/vault.yml   # prompts for password
ansible-vault view playbooks/rop01/group_vars/rop01_user/vault.yml    # view only
```

The encrypted file `group_vars/rop01_user/vault.yml` can be committed to the repo; only the vault password must stay secret. See also `playbooks/rop01/group_vars/rop01_user/vault.yml.example` for the list of variable names (no real values).

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
