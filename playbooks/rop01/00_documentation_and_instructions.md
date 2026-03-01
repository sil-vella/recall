### Overview

This document summarizes the full VPS setup and deployment flow for the Dutch stack, from SSH key provisioning through Docker, Nginx, database setup, and the mobile app update pipeline.

The playbooks and scripts live in `playbooks/rop01/` and `playbooks/frontend/`, and target a single VPS at `65.181.125.135` with:
- **Initial root access** via SSH
- A non-root application user `rop01_user`
- Application root directory: `/opt/apps/reignofplay/dutch`

**Important Configuration Note**: 
- **Deployment uses a single `.env` file on the VPS**; no secret files are copied or mounted. Sensitive data (passwords, JWT, service keys, Google OAuth) and connection parameters are provided via docker-compose environment variables loaded from `{{ app_dir }}/.env`.
- **Where values come from**: The playbook creates `{{ app_dir }}/.env` from `playbooks/rop01/templates/env.j2`. For each variable, the template uses (in order): **Ansible vars** (host_vars, -e, vault) → **your shell environment** (e.g. from `source .env` or exported vars) → default (or empty). See `app_dev/.env.example` for the list of variable names.
- **Easiest: use your local .env.** From `app_dev` run:
  ```bash
  set -a && source .env && set +a
  ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01
  ```
  The playbook will read `MONGODB_ROOT_PASSWORD`, `MONGODB_PASSWORD`, `JWT_SECRET_KEY`, etc. from your environment and write them into the VPS `.env` file.
- **Alternatively**: Use **host_vars** (e.g. `playbooks/rop01/host_vars/rop01_user_host.yml`, do not commit) or **ansible-vault** to encrypt that file, or pass vars with **-e**.

---

### 1. SSH Key and Inventory Setup (`01_setup_ssh_key.sh` + `inventory.ini`)

- **Script**: `playbooks/rop01/01_setup_ssh_key.sh`
- **Inventory**: `playbooks/rop01/inventory.ini`

**What it does**:
- Generates an **ED25519** SSH key pair at `~/.ssh/rop01_key` and `~/.ssh/rop01_key.pub`.
- Optionally backs up existing keys and can automatically:
  - Copy the public key to the VPS (using `ssh-copy-id` or `sshpass`), and
  - Test SSH connectivity.
- Optionally adds an SSH config entry:

  ```
  Host rop01_vps
      HostName 65.181.125.135
      User root
      IdentityFile ~/.ssh/rop01_key
      IdentitiesOnly yes
  ```

**Inventory groups** used by playbooks:
- `[rop01_root]`: connects as `root` with key `~/.ssh/rop01_key`.
- `[rop01_user]`: connects as `rop01_user` with the same key.

This establishes passwordless SSH for both root and the future app user, used by all subsequent playbooks.

---

### 2. VPS Security Hardening (`02_configure_security.yml`)

- **Playbook**: `playbooks/rop01/02_configure_security.yml`
- **Hosts**: `{{ vm_name }}_root` (root on the VPS)

**Key actions**:
- Creates the non-root user `{{ vm_name }}_user` (for `vm_name=rop01` → `rop01_user`).
- Grants passwordless sudo via `/etc/sudoers.d/rop01_user`.
- Creates `~rop01_user/.ssh` and installs the local `~/.ssh/rop01_key.pub` as `authorized_keys`.
- Configures SSH daemon for key-based authentication.
- Handles package manager locks, installs security packages (fail2ban, AppArmor, auditd, etc.).
- Syncs system time and performs a full OS update/upgrade.

From this point onward, **all app playbooks** run as `rop01_user` (with `become: true`).

---

### 3. Firewall and Network Rules (`03_setup_firewall.yml`)

- **Playbook**: `playbooks/rop01/03_setup_firewall.yml` (not shown here, but part of the flow)

Typical responsibilities (as implemented in this project):
- Configure `ufw` or equivalent to allow required ports:
  - `22` (SSH)
  - `80` / `443` (HTTP/HTTPS for Nginx)
  - `5001` (Flask app behind Nginx)
  - `8080` (Dart WebSocket server)
  - `9090` (Prometheus)
  - `3001` (Grafana)
- Deny everything else by default.

This ensures the VPS exposes only the necessary services.

---

### 4. Nginx + SSL + Domains (`04_setup_nginx.yml` + `templates/nginx-site.conf.j2`)

- **Playbook**: `playbooks/rop01/04_setup_nginx.yml`
- **Template**: `playbooks/rop01/templates/nginx-site.conf.j2`
- **Hosts**: `{{ vm_name }}_user`

**Domains configuration** (default when `vm_name=rop01`):
- `reignofplay.com` and `www.reignofplay.com` → static root `/var/www/reignofplay.com`.
- `dutch.mt` (production) and `dutch.reignofplay.com` → app root `/var/www/dutch.reignofplay.com`, backed by:
  - Flask backend on **port 5001** (`backend_port: 5001`)
  - Dart WebSocket server on **port 8080** (`backend_ws_port: 8080`).
- Production is **dutch.mt**; both dutch.mt and dutch.reignofplay.com use the same app root and backend.

**What the playbook does**:
- Installs Nginx + Certbot.
- Creates site directories under `/var/www/` and default `index.html` pages.
- Renders and enables Nginx site configs from `nginx-site.conf.j2`.
- Obtains and configures **Let’s Encrypt** certificates for the domains.
- Adds security headers into `nginx.conf`.
- Sets up a daily Certbot renewal cron job.

**Key Nginx behavior for `dutch.mt` / `dutch.reignofplay.com`** (from `nginx-site.conf.j2`):
- Reverse proxy API requests:

  ```nginx
  location / {
      proxy_pass http://127.0.0.1:5001;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```

- WebSocket proxy at `/ws` → Dart server on `127.0.0.1:8080`.
- **Static downloads** directory we added:

  ```nginx
  location /downloads/ {
      alias {{ item.root_dir | default('/var/www/' + item.domain) }}/downloads/;
      autoindex off;
      default_type application/octet-stream;
      add_header Content-Disposition "attachment";
  }
  ```

This serves `https://dutch.mt/downloads/...` (and dutch.reignofplay.com) directly from the filesystem.

---

### 5. Docker & App Deployment (`05_install_docker.yml`, `08_deploy_docker_compose.yml`)

#### 5.1 Docker installation (`05_install_docker.yml`)

- Installs Docker Engine + Docker Compose plugin on the VPS.
- Adds `rop01_user` to the `docker` group so it can run Docker commands via `sg docker`.

#### 5.2 Deploying the stack (`08_deploy_docker_compose.yml`)

- **Playbook**: `playbooks/rop01/08_deploy_docker_compose.yml`
- **Hosts**: `{{ vm_name }}_user`

**Directory layout** created:
- `app_dir`: `/opt/apps/reignofplay/dutch`
  - `.env` (created by playbook from template; used by `docker compose`; mode 0600, owner/group `vps_user`)
- `data_dir`: `/opt/apps/reignofplay/dutch/data`
  - `mongodb/` (MongoDB data volume)
  - `redis/` (Redis data volume)
  - `prometheus/config` + `prometheus/storage`
  - `grafana/` (Grafana data + provisioning + dashboards)

**VPS `.env` file** (at `{{ app_dir }}/.env`):
- The playbook creates the VPS `.env` from the template `playbooks/rop01/templates/env.j2`. It includes at least: `VPS_APP_UID`, `VPS_APP_GID`, `MONGODB_ROOT_PASSWORD`, `MONGODB_PASSWORD`, `REDIS_PASSWORD`, `JWT_SECRET_KEY`, `ENCRYPTION_KEY`, `DART_BACKEND_SERVICE_KEY`, `DUTCH_MT_DASHBOARD_SERVICE_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.
- **Required variables** must be provided via Ansible (e.g. vault, `group_vars`, `host_vars`, or `-e`). If a variable is not set, the template writes an empty value; ensure all required values are supplied for production. See `app_dev/.env.example` for the full list of variable names.

**Docker Compose file**:
- Copied from repo root `docker-compose.yml` to the VPS at `/opt/apps/reignofplay/dutch/docker-compose.yml`.
- Services:
  - `dutch_mongodb-external` (Bitnami MongoDB, `27018:27017`)
  - `dutch_redis-external` (Bitnami Redis, `6380:6379`)
  - `dutch_flask-external` (Flask app, `5001:5001`)
  - `dutch_prometheus` (Prometheus, `9090:9090`)
  - `dutch_grafana` (Grafana, `3001:3000`)
  - `dutch_dart-game-server` (Dart WebSocket server, `8080:8080`)

**Configuration**: Flask and other services receive sensitive data and connection params via **environment variables** loaded from the VPS `.env` file (no secret file mounts). The compose file uses `env_file: .env` and `environment:` entries; sensitive values are read from `.env` at runtime.

**Playbook flow**:
- Creates application directories and the VPS `.env` from the template (values from Ansible vars).
- Validates `docker compose` availability.
- Validates `docker-compose.yml` syntax.
- Optionally pulls latest images and runs `docker compose up -d`.
- Waits for Flask (5001), MongoDB (27018), and Redis (6380) to be reachable.
- Optionally restarts Grafana if dashboards changed.

To re-run deployment manually (ensure required `.env` variables are provided via vault, group_vars, host_vars, or `-e`):

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01
```

If running from another directory, set the repo root for Grafana/provisioning paths:

```bash
ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01 -e local_repo_root=/path/to/app_dev
```

#### 5.3 When you changed DB/Redis credentials

If you have **changed** `MONGODB_PASSWORD` or `REDIS_PASSWORD` (or root passwords) in your `.env`, the existing MongoDB/Redis data on the VPS was created with the old credentials. Bitnami only applies env passwords at **first** initialization. To switch to the new credentials you must reset the data and re-initialize:

1. **Reset** MongoDB and Redis data on the VPS (stops stack, backs up then removes `data/mongodb` and `data/redis`, so they are recreated empty on next deploy):
   ```bash
   set -a && source .env && set +a
   ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08a_reset_db_redis_data.yml -e vm_name=rop01 -e reset_db_redis=yes
   ```
2. **Deploy** so the new `.env` is written and the stack starts with fresh DB/Redis:
   ```bash
   ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01
   ```
3. **Recreate** DB structure and seed data (run with same env so `MONGODB_PASSWORD` matches):
   ```bash
   ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/09_setup_apps_database_structure.yml -e vm_name=rop01
   ```

Backups (if the dirs existed) are written under `{{ data_dir }}/` as `mongodb.bak.<epoch>.tar.gz` and `redis.bak.<epoch>.tar.gz`.

---

### 6. Flask Docker Image Build & Push (`06_build_and_push_docker.py`)

- **Script**: `playbooks/rop01/06_build_and_push_docker.py`

**What it does**:
- Builds the Flask Docker image from `python_base_04/Dockerfile` with build context `python_base_04/`.
- Temporarily comments out `custom_log(...)` calls (to avoid noisy logs or syntax traps), builds, then restores them.
- Tags and pushes the image to Docker Hub as:

  ```
  silvella/dutch_flask_app:latest
  ```

**Configuration**: The image does not bundle secret files; configuration (passwords, JWT, service keys, connection params) is supplied at **run time** via the VPS `.env` file and docker-compose environment variables.

**Usage**:

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
python3 playbooks/rop01/06_build_and_push_docker.py
```

After pushing, re-run `08_deploy_docker_compose.yml` so the VPS pulls and starts the new image.

---

### 6.1 Dart Docker Image Build & Push (`07_build_and_push_dart_docker.py`)

- **Script**: `playbooks/rop01/07_build_and_push_dart_docker.py`

**What it does**:
- Builds the Dart WebSocket server Docker image from `dart_bkend_base_01/Dockerfile`.
- **Disables logging**: Sets `LOGGING_SWITCH = false` in all Dart source files before build
- Tags and pushes the image to Docker Hub as:

  ```
  silvella/dutch_dart_game_server:latest
  ```

**Usage**:

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
python3 playbooks/rop01/07_build_and_push_dart_docker.py
```

After pushing, re-run `08_deploy_docker_compose.yml` so the VPS pulls and starts the new image.

---

### 7. Mobile App Build & Update Flow (`playbooks/frontend/build_apk.sh`)

- **Script**: `playbooks/frontend/build_apk.sh`

**Inputs**:
- Backend target: `local` or `vps` (default `vps`).
- Mobile app version: read from **`APP_VERSION`** in repo root **`.env`** (or env); falls back to `2.0.0`. No secret files.

**What the script does**:
1. **Disable logging**: Sets `LOGGING_SWITCH = false` in all Flutter source files before build
2. **Resolve repo root** and read **`APP_VERSION`** from:
   - Environment (e.g. after sourcing **`app_dev/.env`**), or falls back to `2.0.0`.
3. **Derive build number** for Flutter:

   - Splits `APP_VERSION` into `major.minor.patch`.
   - Computes `BUILD_NUMBER = major * 10000 + minor * 100 + patch`.
4. **Sets backend URLs**:
   - For `vps` (default):

     ```bash
     API_URL="https://dutch.mt"
     WS_URL="wss://dutch.mt/ws"
     ```

   - For `local`: uses your LAN IP for the Python and Dart services.
5. **Builds the release APK** from `flutter_base_05`:

   ```bash
   flutter build apk \
     --release \
     --build-name="$APP_VERSION" \
     --build-number="$BUILD_NUMBER" \
     --dart-define=API_URL="$API_URL" \
     --dart-define=WS_URL="$WS_URL" \
     --dart-define=APP_VERSION="$APP_VERSION" \
     ... (JWT/AdMob/Stripe/debug flags)
   ```

   Output: `flutter_base_05/build/app/outputs/flutter-apk/app-release.apk`.

6. **If target is `vps`**:
   - Uses SSH (default `rop01_user@65.181.125.135`, key `~/.ssh/rop01_key`).
   - Uploads the APK to a temp path on the VPS and then moves it (with `sudo`) to:

     ```bash
     /var/www/dutch.reignofplay.com/downloads/v$APP_VERSION/app.apk
     ```

   - Fixes ownership and permissions (`www-data:www-data`, `0644`).
   - Generates/updates the mobile release manifest on the VPS at **`/opt/apps/reignofplay/dutch/data/mobile_release.json`** (see `build_apk.sh`). Content format: `{ "latest_version": "<APP_VERSION>", "min_supported_version": "<MIN_SUPPORTED_VERSION>" }`. `MIN_SUPPORTED_VERSION` defaults to `APP_VERSION` unless overridden via env. Download base URL for the app comes from VPS `.env` (**`APP_DOWNLOAD_BASE_URL`**).

**Result**:
- A new APK is available at:

  ```
  https://dutch.mt/downloads/v<APP_VERSION>/app.apk
  ```

- The backend’s update endpoint `/public/check-updates` will advertise this version and download link without needing a Flask restart.

**Usage**:

```bash
cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev

# 1) Set APP_VERSION in .env (e.g. APP_VERSION=2.1.0) or run build_apk.sh and bump when prompted
# 2) Build + upload for VPS
./playbooks/frontend/build_apk.sh          # default is vps
# (Optional) Build for local backend only:
./playbooks/frontend/build_apk.sh local
```

---

### 8. Version Check Endpoint & Manifest (`/public/check-updates`)

- **Module**: `python_base_04/core/modules/system_actions_module/system_actions_main.py`
- **Route**: `/public/check-updates?current_version=<version>`

**Behavior**:
- At startup, `SystemActionsModule` registers `/public/check-updates` as a public Flask endpoint.
- On each request, it:
  1. Attempts to load `mobile_release.json` from the path configured by the app (e.g. env or default path).

  2. Reads:
     - `latest_version` → `server_version`
     - `min_supported_version` → threshold for `update_required`.
  3. Uses `current_version` from the query string (`current_version`), defaulting to `server_version`.
  4. Compares semantic versions (major/minor/patch) to determine:
     - `update_available = client < latest`
     - `update_required = client < min_supported`.
  5. Builds a `download_link` if `update_available` is `true`:

     ```
     {APP_DOWNLOAD_BASE_URL}/v{server_version}/app.apk
     ```

- `APP_DOWNLOAD_BASE_URL` comes from `Config.APP_DOWNLOAD_BASE_URL` (env var, e.g. from VPS `.env`).

**Example responses**:

- **Old client (2.0.0) vs server 2.1.0**:

  ```json
  {
    "server_version": "2.1.0",
    "min_supported_version": "2.1.0",
    "current_version": "2.0.0",
    "update_available": true,
    "update_required": true,
    "download_link": "https://dutch.mt/downloads/v2.1.0/app.apk",
    "manifest_path": "...",
    ...
  }
  ```

- **Up-to-date client (2.1.0)**:

  ```json
  {
    "server_version": "2.1.0",
    "min_supported_version": "2.1.0",
    "current_version": "2.1.0",
    "update_available": false,
    "update_required": false,
    "download_link": "",
    "manifest_path": "...",
    ...
  }
  ```

This is what the Flutter `VersionCheckService` calls on startup.

---

### 9. Initial Database Seeding (Local) (`00_local/10_setup_apps_database_structure.yml`)

- **Playbook**: `playbooks/00_local/10_setup_apps_database_structure.yml`
- **Purpose**: Seed a **local** MongoDB (Docker) with an initial modular database structure and dummy data for development.

**What it does** (local dev only):
- Targets `localhost` and uses `docker exec` to reach a local MongoDB container.
- Empties the `external_system` database (drops existing collections).
- Creates and populates:
  - `users` collection with modular user documents (profile, preferences, modules, audit data).
  - `user_modules` registry describing available modules (`wallet`, `subscription`, `referrals`, `in_app_purchases`, `dutch_game`).
  - `user_audit_logs` collection with sample audit events.
- Prints a detailed summary of collections and documents.

This is for local iteration only; production uses the non-destructive updater below.

---

### 10. Non-Destructive DB Module Update (VPS) (`09_setup_apps_database_structure.yml` / `10_setup_apps_database_structure(update_existing).yml`)

There are two relevant playbooks for **remote** MongoDB structure:

- `playbooks/rop01/09_setup_apps_database_structure.yml` – initial production seeding (similar to local seeding, used earlier in the project).
- `playbooks/rop01/10_setup_apps_database_structure(update_existing).yml` – non-destructive updater for existing production data.

#### 10.1 `10_setup_apps_database_structure(update_existing).yml`

- **Hosts**: `{{ vm_name }}_user`
- **Mongo target**: remote container `dutch_external_app_mongodb` on the VPS.

**Key variables**:
- `mongodb_container_name`: `dutch_external_app_mongodb`
- `database_name`: `external_system`
- `app_user`: `external_app_user`
- `app_password`: from **env** `MONGODB_PASSWORD` (e.g. `set -a && source .env && set +a` before running) or Ansible var `mongodb_password`; fallback for backwards compat. Use the same password as in the VPS `.env` so DB setup matches compose.
- Connects via `docker exec ... mongosh` (host `localhost`, port `27018`).

**What it does**:
1. **Waits** for MongoDB to be ready using `db.adminCommand('ping')` inside the container.
2. Creates `/tmp/add_missing_modules.js` locally containing a Mongo script that:
   - Ensures `user_modules` includes:
     - `in_app_purchases` module definition.
     - `dutch_game` module definition (and updates its schema to include `coins` and `subscription_tier` if missing).
   - Iterates all users in `users` collection and:
     - Adds a default `modules.in_app_purchases` block if missing.
     - Adds a default `modules.dutch_game` block if missing.
     - Adds or updates `coins` and `subscription_tier` for existing `dutch_game` entries, and normalizes `subscription_tier="free"` to `"promotional"`.
     - Updates `updated_at` timestamps as needed.
   - **Adds `is_comp_player` field**:
     - Creates index on `is_comp_player` field
     - Adds `is_comp_player: false` to all existing users that don't have it
   - **Creates computer players**:
     - Creates 5 computer players with predefined usernames:
       - `alex.morris87`
       - `lena_kay`
       - `jordanrivers`
       - `samuel.b`
       - `nina_holt`
     - Each with 1000 coins, active status, and `is_comp_player: true`
3. Copies the script into the MongoDB container and executes it via `mongosh`.
4. Prints a detailed log of operations and a verification summary:
   - Total modules in `user_modules`.
   - Number of users.
   - Number of users with `in_app_purchases` and `dutch_game` modules.
   - Number of computer players created.
5. Cleans up the temporary script and prints a final, human-readable summary.

**Guarantees**:
- **Non-destructive**: does not drop any collections or remove existing user data.
- Only adds/patches fields required for the new modules.

---

### 11. End-to-End Release Flow (Summary)

To perform a full **mobile app + backend** release with versioned updates:

1. **Ensure SSH works**:

   ```bash
   ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135
   ```

2. **Bump backend mobile version** (set in `.env` so Flask and build scripts use it):

   ```bash
   # In app_dev/.env set: APP_VERSION=2.2.0
   # Or run build_apk.sh and answer 'y' to bump; it updates .env automatically.
   ```

3. **Build and push Docker images (if backend code changed)**:

   ```bash
   # Build and push Flask image
   python3 playbooks/rop01/06_build_and_push_docker.py
   
   # Build and push Dart WebSocket server image
   python3 playbooks/rop01/07_build_and_push_dart_docker.py
   ```

4. **Deploy updated stack** (ensure required `.env` variables are provided via vault, group_vars, host_vars, or `-e`; see `app_dev/.env.example`):

   ```bash
   cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
   ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01
   ```

5. **Build and upload new APK + update manifest**:

   ```bash
   cd /Users/sil/Documents/Work/reignofplay/Dutch/app_dev
   ./playbooks/frontend/build_apk.sh
   ```

   This creates `/downloads/v2.2.0/app.apk` and updates `mobile_release.json` accordingly.
   
   **Note**: The build script automatically disables `LOGGING_SWITCH` in all Flutter source files before building the release APK.

6. **Optionally update MongoDB structure** (if new modules/fields were introduced):

   ```bash
   cd playbooks/rop01
   ansible-playbook -i inventory.ini 10_setup_apps_database_structure(update_existing).yml -e vm_name=rop01
   ```

7. **Sanity-check version endpoint**:

   ```bash
   curl "https://dutch.mt/public/check-updates?current_version=2.1.0"
   ```

   - Expect `server_version: "2.2.0"`.
   - `download_link` should point at `/downloads/v2.2.0/app.apk`.

At that point, the Flutter app (on web or mobile) will detect the new version via `/public/check-updates` and, if you implement the launcher UI, guide users to download/install the new APK automatically.
