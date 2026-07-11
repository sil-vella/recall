#!/usr/bin/env bash
# Generate Mongo TLS certs on rop01 (greenfield or cert rotation).
# Compose + Flask TLS client are in repo docker-compose.yml and database_manager.py.
#
# Usage:
#   playbooks/rop01/mongodb_tls/install_mongo_tls_certs.sh
#   playbooks/rop01/mongodb_tls/install_mongo_tls_certs.sh --dry-run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROP01_SSH_KEY="${ROP01_SSH_KEY:-${HOME}/.ssh/rop01_key}"
ROP01_SSH_USER="${ROP01_SSH_USER:-rop01_user}"
ROP01_SSH_HOST="${ROP01_SSH_HOST:-65.181.125.135}"
REMOTE_TLS_DIR="/opt/backups/scripts/mongodb_tls"
DUTCH_ROOT="/opt/apps/reignofplay/dutch"

SSH_OPTS=(-i "${ROP01_SSH_KEY}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '1,8p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

if [[ ! -r "${ROP01_SSH_KEY}" ]]; then
  log "ERROR: SSH key not readable: ${ROP01_SSH_KEY}"
  exit 1
fi

log "upload cert scripts to ${REMOTE_TLS_DIR}"
ssh "${SSH_OPTS[@]}" "${ROP01_SSH_USER}@${ROP01_SSH_HOST}" "mkdir -p /tmp/mongodb_tls_upload"
scp "${SSH_OPTS[@]}" \
  "${SCRIPT_DIR}/generate_certs.sh" \
  "${SCRIPT_DIR}/fix_tls_permissions.sh" \
  "${SCRIPT_DIR}/mongo_tls_common.sh" \
  "${SCRIPT_DIR}/load_mongo_tls_args.sh" \
  "${ROP01_SSH_USER}@${ROP01_SSH_HOST}:/tmp/mongodb_tls_upload/"

ssh "${SSH_OPTS[@]}" "${ROP01_SSH_USER}@${ROP01_SSH_HOST}" bash -s <<REMOTE
set -euo pipefail
sudo mkdir -p '${REMOTE_TLS_DIR}'
sudo install -m 700 /tmp/mongodb_tls_upload/generate_certs.sh '${REMOTE_TLS_DIR}/'
sudo install -m 700 /tmp/mongodb_tls_upload/fix_tls_permissions.sh '${REMOTE_TLS_DIR}/'
sudo install -m 644 /tmp/mongodb_tls_upload/mongo_tls_common.sh '${REMOTE_TLS_DIR}/'
sudo install -m 644 /tmp/mongodb_tls_upload/load_mongo_tls_args.sh '${REMOTE_TLS_DIR}/'
rm -rf /tmp/mongodb_tls_upload
REMOTE

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "dry-run: would run generate_certs.sh + fix_tls_permissions.sh on VPS"
  exit 0
fi

log "generate certs on VPS (${DUTCH_ROOT}/data/mongodb/tls/)"
ssh "${SSH_OPTS[@]}" "${ROP01_SSH_USER}@${ROP01_SSH_HOST}" "sudo bash -s" <<REMOTE
set -euo pipefail
bash '${REMOTE_TLS_DIR}/generate_certs.sh'
bash '${REMOTE_TLS_DIR}/fix_tls_permissions.sh'
ls -la '${DUTCH_ROOT}/data/mongodb/tls/'
REMOTE

log "done — redeploy compose if first-time TLS: ansible-playbook … 08_deploy_docker_compose.yml"
