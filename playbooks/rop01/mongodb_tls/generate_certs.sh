#!/usr/bin/env bash
# Generate private CA + MongoDB server cert for Dutch stack TLS.
# Run on rop01 as root, or from your machine via install_mongo_tls_certs.sh.
set -euo pipefail

TLS_DIR="${TLS_DIR:-/opt/apps/reignofplay/dutch/data/mongodb/tls}"
DAYS_CA="${DAYS_CA:-3650}"
DAYS_SERVER="${DAYS_SERVER:-825}"
CN="${TLS_CA_CN:-rop01-dutch-mongo-ca}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force]

Create:
  ${TLS_DIR}/ca.pem ca-key.pem mongod.pem

Options:
  --force   Regenerate even if ca.pem exists (destructive — requires client updates)
EOF
}

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [[ -f "${TLS_DIR}/ca.pem" && "${FORCE}" -eq 0 ]]; then
  echo "CA already exists: ${TLS_DIR}/ca.pem (use --force to regenerate)"
  exit 0
fi

mkdir -p "${TLS_DIR}"
chmod 700 "${TLS_DIR}"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

openssl genrsa -out "${WORK}/ca-key.pem" 4096
openssl req -x509 -new -nodes -key "${WORK}/ca-key.pem" -sha256 -days "${DAYS_CA}" \
  -out "${WORK}/ca.pem" -subj "/CN=${CN}"

openssl genrsa -out "${WORK}/mongod-key.pem" 2048
openssl req -new -key "${WORK}/mongod-key.pem" -out "${WORK}/mongod.csr" -subj "/CN=dutch_mongodb-external"
cat > "${WORK}/mongod.ext" <<EOF
subjectAltName = DNS:dutch_mongodb-external,DNS:dutch_external_app_mongodb,DNS:localhost,IP:127.0.0.1
extendedKeyUsage = serverAuth, clientAuth
EOF
openssl x509 -req -in "${WORK}/mongod.csr" -CA "${WORK}/ca.pem" -CAkey "${WORK}/ca-key.pem" \
  -CAcreateserial -out "${WORK}/mongod-cert.pem" -days "${DAYS_SERVER}" -sha256 \
  -extfile "${WORK}/mongod.ext"

cat "${WORK}/mongod-cert.pem" "${WORK}/mongod-key.pem" > "${WORK}/mongod.pem"

install -m 644 "${WORK}/ca.pem" "${TLS_DIR}/ca.pem"
install -m 600 "${WORK}/ca-key.pem" "${TLS_DIR}/ca-key.pem"
install -m 644 "${WORK}/mongod.pem" "${TLS_DIR}/mongod.pem"
chmod 755 "${TLS_DIR}"

echo "TLS certs installed under ${TLS_DIR}"
ls -la "${TLS_DIR}"
