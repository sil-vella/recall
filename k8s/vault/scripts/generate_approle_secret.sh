#!/bin/bash

# AppRole Secret Generation Script (for rop01)
# Generates new AppRole secret ID and stores it in GCP Secret Manager

LOG_FILE="$(dirname "$0")/generate_approle.log"
VAULT_ADDR="http://localhost:8200"

echo "===== $(date) Starting AppRole secret generation =====" >> "$LOG_FILE" 2>&1

# Set Vault address and authenticate
export VAULT_ADDR="$VAULT_ADDR"
export VAULT_TOKEN=$(cat ~/.vault-token)

echo "Authenticating to Vault..." >> "$LOG_FILE" 2>&1
if ! vault token lookup > /dev/null 2>&1; then
  echo "ERROR: Failed to authenticate to Vault" >> "$LOG_FILE"
  exit 1
fi

echo "Generating new AppRole secret ID..." >> "$LOG_FILE" 2>&1
NEW_SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/flask-app-approle/secret-id 2>>"$LOG_FILE")

if [ $? -ne 0 ] || [ -z "$NEW_SECRET_ID" ]; then
  echo "ERROR: Failed to generate new AppRole secret ID" >> "$LOG_FILE"
  exit 1
fi

echo "New secret ID generated: ${NEW_SECRET_ID:0:15}..." >> "$LOG_FILE"

# Store new secret ID in GCP Secret Manager (root already authenticated)
echo "Storing new secret ID in GCP Secret Manager..." >> "$LOG_FILE" 2>&1
if echo -n "$NEW_SECRET_ID" | gcloud secrets versions add flask-app-approle-secret-id --data-file=- 2>>"$LOG_FILE"; then
  echo "✅ Secret ID stored in GCP Secret Manager successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to store secret ID in GCP Secret Manager" >> "$LOG_FILE"
  exit 1
fi

# Test the new credentials against Vault
ROLE_ID="b272c720-2106-78c5-b872-4a095860d703"
echo "Testing new AppRole credentials..." >> "$LOG_FILE" 2>&1
if curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$NEW_SECRET_ID\"}" \
  http://localhost:8200/v1/auth/approle/login | grep -q "client_token" 2>>"$LOG_FILE"; then
  echo "✅ New AppRole credentials tested successfully against Vault" >> "$LOG_FILE"
else
  echo "WARNING: New AppRole credentials test failed against Vault" >> "$LOG_FILE"
fi

echo "===== $(date) AppRole secret generation completed =====" >> "$LOG_FILE" 2>&1
echo "Next step: Run update script on rop02 to deploy the new secret" >> "$LOG_FILE" 2>&1 