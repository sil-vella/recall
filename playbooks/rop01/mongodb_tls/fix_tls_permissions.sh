#!/usr/bin/env bash
# Fix TLS file permissions so mongod (non-root in container) can read certs.
set -euo pipefail

TLS_DIR="${TLS_DIR:-/opt/apps/reignofplay/dutch/data/mongodb/tls}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

chmod 755 "${TLS_DIR}"
chmod 644 "${TLS_DIR}/ca.pem" "${TLS_DIR}/mongod.pem"
chmod 600 "${TLS_DIR}/ca-key.pem" 2>/dev/null || true
echo "TLS permissions fixed under ${TLS_DIR}"
ls -la "${TLS_DIR}"
