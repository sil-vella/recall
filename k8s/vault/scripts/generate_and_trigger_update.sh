#!/bin/bash

LOG_FILE="$(dirname "$0")/generate_and_trigger.log"
VAULT_ADDR="http://localhost:8200"

echo "===== $(date) Generating new AppRole secret and triggering update =====" >> "$LOG_FILE" 2>&1

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

# Store new secret ID in GCP Secret Manager using SSH to rop02
echo "Storing new secret ID in GCP Secret Manager via rop02..." >> "$LOG_FILE" 2>&1
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rop02_user@10.0.0.3 "
  echo -n '$NEW_SECRET_ID' | /home/rop02_user/google-cloud-sdk/bin/gcloud secrets versions add flask-app-approle-secret-id --data-file=-
" >> "$LOG_FILE" 2>&1; then
  echo "✅ Secret ID stored in GCP Secret Manager successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to store secret ID in GCP Secret Manager" >> "$LOG_FILE"
  exit 1
fi

# Trigger immediate update on rop02
echo "Triggering immediate update on rop02..." >> "$LOG_FILE" 2>&1
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rop02_user@10.0.0.3 "/home/rop02_user/vault_scripts/update_approle_secret_rop02.sh" >> "$LOG_FILE" 2>&1; then
  echo "✅ AppRole secret updated on rop02 successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to update AppRole secret on rop02" >> "$LOG_FILE"
  exit 1
fi

echo "===== $(date) AppRole secret generation and update completed =====" >> "$LOG_FILE" 2>&1 