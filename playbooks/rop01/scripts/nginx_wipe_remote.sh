#!/usr/bin/env bash
# Run from your machine (not on VPS). Uninstalls nginx and removes config on the VPS.
# Does NOT remove /var/www or any content directories.
# Usage: ./scripts/nginx_wipe_remote.sh

set -e
HOST="${1:-65.181.125.135}"
USER="${2:-root}"
KEY="${3:-$HOME/.ssh/rop01_key}"

echo "Stopping nginx..."
ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "$USER@$HOST" 'systemctl stop nginx 2>/dev/null || true'

echo "Purging nginx packages..."
ssh -i "$KEY" "$USER@$HOST" 'apt-get remove -y --purge nginx nginx-common 2>/dev/null || true'

echo "Removing /etc/nginx..."
ssh -i "$KEY" "$USER@$HOST" 'rm -rf /etc/nginx'

echo "Done. Nginx uninstalled and config removed. /var/www and other dirs unchanged."
