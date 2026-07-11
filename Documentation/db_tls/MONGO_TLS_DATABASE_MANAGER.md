# Mongo TLS — Flask client (`DatabaseManager`)

> **Canonical guide:** [MONGODB_TLS.md](../MONGODB_TLS.md)

## Implementation

[`python_base_04/core/managers/database_manager.py`](../../python_base_04/core/managers/database_manager.py) — `_setup_mongodb_connection()` reads `MONGODB_SSL*` from [`Config`](../../python_base_04/utils/config/config.py) and passes PyMongo `tls` / `tlsCAFile` (and optional cert/key) when `MONGODB_SSL=true`.

## Compose (Flask service)

Set in [`docker-compose.yml`](../../docker-compose.yml):

```yaml
environment:
  MONGODB_SSL: "true"
  MONGODB_SSL_CA_FILE: /etc/mongo-tls/ca.pem
volumes:
  - ./data/mongodb/tls:/etc/mongo-tls:ro
```

## Deploy

TLS ships in the Flask Docker image. Use the normal release path:

1. `playbooks/rop01/06_build_and_push_docker.py`
2. `playbooks/rop01/08_deploy_docker_compose.yml`
3. `docker compose up -d --force-recreate` on VPS

See [MONGODB_TLS.md § Deploy flow](../MONGODB_TLS.md#deploy-flow-normal-releases).
