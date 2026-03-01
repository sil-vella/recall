# Where Flask Gets DB/Redis Credentials (Local vs VPS)

## How config is read

All MongoDB/Redis settings come from `utils/config/config.py`:

- **`get_config_value()`**: Files → Vault → Env → default (used for host, port, service name, user, db name)
- **`get_sensitive_config_value()`**: Vault → Files → Env → default (used for passwords)
- **`get_file_first_config_value()`**: Files → Env → default (used for other options)

File reads go through **`read_secret_file(secret_name)`**, which tries (in order):

1. `/run/secrets/{secret_name}` (Kubernetes)
2. **`/app/secrets/{secret_name}`** (Docker: mounted volume)
3. **`./secrets/{secret_name}`** (local run: relative to process CWD)

So: **files win over environment variables** for the same key (except for sensitive, where Vault is tried first and we don’t use Vault on VPS).

---

## Local (your working setup)

- **Flask process**: Usually run from repo (e.g. `python_base_04/`), so CWD is something like `…/app_dev/python_base_04/`.
- **Secrets path**: `./secrets/` → **`python_base_04/secrets/`**.
- **Connection params** (from secret files in that dir):
  - `mongodb_service_name`, `mongodb_port`, `redis_host`, `redis_port` (and optionally `mongodb_*`, `redis_*`).
- **Passwords**: `mongodb_root_password`, `mongodb_user_password`, `redis_password` (same directory).
- With **local Docker** (e.g. `docker-compose.debug.yml`): MongoDB/Redis containers mount `./python_base_04/secrets` as `/app/secrets`. So:
  - Containers read passwords from `/app/secrets/...`.
  - If Flask runs on the **host**, it uses `./secrets/` = `python_base_04/secrets/` and connects to `localhost:27018` / `localhost:6380` (or whatever is in the secret files). So **local creds** = everything in `python_base_04/secrets/`.

---

## VPS (production)

- **Flask container**: Runs with WORKDIR `/app`; secrets mount: **`/opt/apps/reignofplay/dutch/secrets` → `/app/secrets`** (from `docker-compose.yml`).
- **Secrets path**: **`/app/secrets/`** (so same `read_secret_file` logic hits the mounted dir).
- **Where those files come from**:
  1. Playbook **copies** `local_repo_root/python_base_04/secrets/` → `{{ app_dir }}/secrets/` on the VPS (`08_deploy_docker_compose.yml`), with `force: no` (only copy if missing or content changed).
  2. Playbook **overwrites** these four files on the VPS so connection params are correct inside Docker:
     - `mongodb_port` → `27017`
     - `mongodb_service_name` → `dutch_mongodb-external`
     - `redis_host` → `dutch_redis-external`
     - `redis_port` → `6379`
- **Passwords**: Not overwritten by the playbook. They are whatever was copied from **local** `python_base_04/secrets/` (e.g. `mongodb_root_password`, `mongodb_user_password`, `redis_password`).

So on VPS, **connection** comes from the four overwritten files (+ any other file-based or env defaults). **Credentials** (passwords) come from the same copied secret files as local.

---

## Why “DB connection failed” or login can fail on VPS

1. **Connection params**
   - If the four overwritten files weren’t applied (e.g. playbook not run, or wrong path), Flask might still read old/local values (e.g. `localhost`, `27018`) from previously copied files and try to connect to the wrong host/port.
   - **Fix**: Re-run deploy so the playbook overwrites the four files again; then restart Flask so it reloads config:  
     `docker compose -f … restart dutch_flask-external`.

2. **Password mismatch**
   - MongoDB and Redis on VPS read their passwords **at container startup** from the same mount: `/app/secrets` = `{{ app_dir }}/secrets/`.
   - If the VPS MongoDB/Redis **data** was first created with different passwords (e.g. old deploy, manual setup, or different secrets), the running DB still expects those **old** passwords. After that, if we copy **new** secrets from local (different passwords), Flask will use the new passwords and get “auth failed” or “connection failed”.
   - **Fix**: Either
     - Reset VPS MongoDB/Redis data and run a fresh deploy so they initialize with the **current** local secrets, or
     - Make sure the secret files on the VPS (and what you copy from local) match the passwords that were used when that VPS MongoDB/Redis was first initialized.

3. **Stale config in Flask**
   - Config is loaded at import/startup. If you change secret files on the VPS but don’t restart Flask, the process still has the old values.
   - **Fix**: After updating secrets on VPS, restart Flask:  
     `docker compose -f … restart dutch_flask-external`.

---

## Summary table

| Item                  | Local (host)           | Local (Flask in Docker) | VPS (Flask container)        |
|-----------------------|------------------------|--------------------------|-----------------------------|
| Secrets directory     | `./secrets` → repo dir | `/app/secrets` (mounted) | `/app/secrets` (mounted)    |
| Host/port source      | Secret files           | Secret files             | Secret files (4 overwritten by playbook) |
| Password source       | Secret files           | Secret files             | Same copied secret files    |
| Must match MongoDB/Redis | Yes (same files)   | Yes (same mount)         | Yes (same mount; DB init = first password used) |

So: **local and VPS both get creds from the same logical place (file-based config)**. Local uses `python_base_04/secrets/`; VPS uses that same set of files **copied** to the server and then **four connection files overwritten**. The usual VPS issue is either wrong connection params (fix with playbook + restart Flask) or MongoDB/Redis having been initialized with different passwords than the ones in the copied files (fix by aligning or resetting DB/Redis).
