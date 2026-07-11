#!/usr/bin/env bash
# Shared Mongo TLS helpers for backup/restore scripts.
# TLS material: /opt/apps/reignofplay/dutch/data/mongodb/tls/ on VPS
# In-container path: /etc/mongo-tls/

MONGO_TLS_CA_IN_CONTAINER="${MONGO_TLS_CA_IN_CONTAINER:-/etc/mongo-tls/ca.pem}"
MONGO_TLS_HOST_DIR="${MONGO_TLS_HOST_DIR:-/opt/apps/reignofplay/dutch/data/mongodb/tls}"

# Returns 0 when prod Mongo TLS is active (CA file present on host).
mongo_tls_active_on_host() {
  [[ -f "${MONGO_TLS_HOST_DIR}/ca.pem" ]]
}

_mongo_tls_enabled() {
  if [[ "${BACKUP_LOCAL_DEV:-0}" == "1" ]]; then
    return 1
  fi
  if [[ "${MONGO_TLS_ENABLED:-auto}" == "0" ]]; then
    return 1
  fi
  if [[ "${MONGO_TLS_ENABLED:-auto}" == "1" ]] || mongo_tls_active_on_host; then
    return 0
  fi
  return 1
}

# mongodump / mongorestore (legacy --ssl flags in mongo tools 8.x)
mongo_tls_dump_args() {
  if _mongo_tls_enabled; then
    printf '%s\n' --ssl "--sslCAFile=${MONGO_TLS_CA_IN_CONTAINER}"
  fi
}

# mongosh (--tls flags)
mongo_tls_shell_args() {
  if _mongo_tls_enabled; then
    printf '%s\n' --tls "--tlsCAFile=${MONGO_TLS_CA_IN_CONTAINER}"
  fi
}

# Backward-compatible alias for mongosh
mongo_tls_cli_args() {
  mongo_tls_shell_args
}
