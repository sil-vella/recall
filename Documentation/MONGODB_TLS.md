# MongoDB TLS (production)

Production MongoDB on rop01 uses **TLS in transit** (`requireTLS` on `mongod`, PyMongo client TLS in Flask). Certs are a private CA on the VPS; client certificates are not required.

Local dev (`docker-compose.debug.yml`) stays **without TLS**; `MONGODB_SSL` defaults to `false` in `Config`.

## Source of truth (repo)

| Component | Location |
|-----------|----------|
| Flask PyMongo TLS | [`python_base_04/core/managers/database_manager.py`](../python_base_04/core/managers/database_manager.py) — `_setup_mongodb_connection()` |
| Config env vars | [`python_base_04/utils/config/config.py`](../python_base_04/utils/config/config.py) — `MONGODB_SSL*` |
| Compose (prod) | [`docker-compose.yml`](../docker-compose.yml) |
| Flask quick reference | [`Documentation/db_tls/MONGO_TLS_DATABASE_MANAGER.md`](db_tls/MONGO_TLS_DATABASE_MANAGER.md) |

## Compose (already in repo)

**Mongo** — `requireTLS` + cert volume:

```yaml
command:
  - mongod
  - --replSet
  - rs0
  - --bind_ip_all
  - --dbpath
  - /data/db
  - --tlsMode
  - requireTLS
  - --tlsCertificateKeyFile
  - /etc/mongo-tls/mongod.pem
  - --tlsCAFile
  - /etc/mongo-tls/ca.pem
  - --tlsAllowConnectionsWithoutCertificates
volumes:
  - ./data/mongodb/tls:/etc/mongo-tls:ro
```

**Flask** — client TLS via env + same CA mount:

```yaml
environment:
  MONGODB_SSL: "true"
  MONGODB_SSL_CA_FILE: /etc/mongo-tls/ca.pem
volumes:
  - ./data/mongodb/tls:/etc/mongo-tls:ro
```

## Deploy flow (normal releases)

1. **Build and push Flask image** — `playbooks/rop01/06_build_and_push_docker.py`  
   Tags `silvella/dutch_flask_app:${FLASK_IMAGE_TAG}` and records the tag in `.env.prod`.
2. **Deploy compose + `.env`** — `ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/08_deploy_docker_compose.yml -e vm_name=rop01`
3. **Recreate containers** on VPS (if images changed):
   ```bash
   cd /opt/apps/reignofplay/dutch
   sudo docker compose up -d --force-recreate dutch_flask-external dutch_mongodb-external
   ```
4. **Verify TLS**:
   ```bash
   curl -sf http://127.0.0.1:5001/health
   docker exec dutch_external_app_mongodb mongosh --tls --tlsCAFile /etc/mongo-tls/ca.pem --quiet --eval 'db.adminCommand({ping:1}).ok'
   ```

No bind-mounts or VPS-side patches to `database_manager.py` — TLS is in the Flask image.

## Cert generation (greenfield / rotation)

Certs live on the VPS at `/opt/apps/reignofplay/dutch/data/mongodb/tls/` (`ca.pem`, `mongod.pem`).

From your machine:

```bash
playbooks/rop01/mongodb_tls/install_mongo_tls_certs.sh
```

Or on the VPS as root:

```bash
playbooks/rop01/mongodb_tls/generate_certs.sh
playbooks/rop01/mongodb_tls/fix_tls_permissions.sh
```

Then deploy repo `docker-compose.yml` (step 2 above) and recreate mongo + flask.

## Script inventory (`playbooks/rop01/mongodb_tls/`)

| Script | Purpose |
|--------|---------|
| `install_mongo_tls_certs.sh` | Upload + run cert generation on rop01 |
| `generate_certs.sh` | Private CA + server cert (SANs: service/container names, localhost) |
| `fix_tls_permissions.sh` | Cert dir permissions for `mongod` |
| `mongo_tls_common.sh` | TLS args for `mongodump` / `mongosh` in backup scripts |
| `load_mongo_tls_args.sh` | Source helper for backup shell scripts |
| `mongosh_tls.py` | Python helper for rop01 ops scripts |

Shared Ansible var for ops playbooks: [`playbooks/rop01/vars/mongodb_tls.yml`](../playbooks/rop01/vars/mongodb_tls.yml) (`mongodb_mongosh_tls_args`).

## Greenfield checklist

1. Generate certs (`install_mongo_tls_certs.sh` or `generate_certs.sh` on VPS)
2. Deploy repo `docker-compose.yml` (includes TLS for mongo + flask)
3. Build/push Flask image (`06_build_and_push_docker.py`) — `DatabaseManager` already wires `MONGODB_SSL*`
4. `docker compose up -d --force-recreate` on VPS
5. Verify `/health` and `mongosh --tls`
