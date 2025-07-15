#!/bin/bash

LOG_FILE="$(dirname "$0")/generate_approle.log"
VAULT_ADDR="http://localhost:8200"

echo "===== $(date) Generating new AppRole secret =====" >> "$LOG_FILE" 2>&1

# Set Vault address
export VAULT_ADDR="$VAULT_ADDR"

# Use root token for authentication
export VAULT_TOKEN=$(cat ~/.vault-token)

echo "Authenticating to Vault..." >> "$LOG_FILE" 2>&1
if ! vault token lookup > /dev/null 2>&1; then
  echo "ERROR: Failed to authenticate to Vault" >> "$LOG_FILE"
  exit 1
fi

echo "Generating new AppRole secret ID..." >> "$LOG_FILE" 2>&1
NEW_SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/flask-app-approle/secret-id 2>>"$LOG_FILE")

if [ $? -ne 0 ] || [ -z "$NEW_SECRET_ID" ]; then
  echo "ERROR: Failed to generate new AppRole secret ID" >> "$LOG_FILE"
  exit 1
fi

echo "New secret ID generated: ${NEW_SECRET_ID:0:15}..." >> "$LOG_FILE"

# Store new secret ID in GCP Secret Manager
echo "Storing new secret ID in GCP Secret Manager..." >> "$LOG_FILE" 2>&1
if echo -n "$NEW_SECRET_ID" | sudo gcloud secrets versions add flask-app-approle-secret-id --data-file=- --project=vault-459512 2>>"$LOG_FILE"; then
  echo "✅ Secret ID stored in GCP Secret Manager successfully" >> "$LOG_FILE"
  echo "rop02 will automatically pick up the new secret within 12 hours, or run the update script manually:" >> "$LOG_FILE"
  echo "  ssh rop02 '/home/rop02_user/vault_scripts/update_approle_secret_rop02.sh'" >> "$LOG_FILE"
else
  echo "ERROR: Failed to store secret ID in GCP Secret Manager" >> "$LOG_FILE"
  exit 1
fi

echo "===== $(date) AppRole secret generation completed =====" >> "$LOG_FILE" 2>&1 