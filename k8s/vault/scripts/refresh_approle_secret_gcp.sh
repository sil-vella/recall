#!/bin/bash

LOG_FILE="$(dirname "$0")/refresh_approle.log"
VAULT_ADDR="http://localhost:8200"
GCP_SERVICE_ACCOUNT_FILE="/k8s/vault/on_vps/vault-service-account.json"

echo "===== $(date) Starting AppRole secret refresh =====" >> "$LOG_FILE" 2>&1

# Set GCP authentication
export GOOGLE_APPLICATION_CREDENTIALS="$GCP_SERVICE_ACCOUNT_FILE"

# Verify GCP authentication
echo "Verifying GCP authentication..." >> "$LOG_FILE" 2>&1
if [ ! -f "$GCP_SERVICE_ACCOUNT_FILE" ]; then
  echo "ERROR: GCP service account file not found: $GCP_SERVICE_ACCOUNT_FILE" >> "$LOG_FILE"
  exit 1
fi

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
NEW_SECRET_ID=$(vault write -field=secret_id auth/approle/role/flask-app-approle/secret-id 2>>"$LOG_FILE")

if [ $? -ne 0 ] || [ -z "$NEW_SECRET_ID" ]; then
  echo "ERROR: Failed to generate new AppRole secret ID" >> "$LOG_FILE"
  exit 1
fi

echo "New secret ID generated: ${NEW_SECRET_ID:0:15}..." >> "$LOG_FILE"

# Store new secret ID in GCP Secret Manager
echo "Storing new secret ID in GCP Secret Manager..." >> "$LOG_FILE" 2>&1
if echo -n "$NEW_SECRET_ID" | gcloud secrets versions add flask-app-approle-secret-id --data-file=- 2>>"$LOG_FILE"; then
  echo "✅ Secret ID stored in GCP Secret Manager successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to store secret ID in GCP Secret Manager" >> "$LOG_FILE"
  exit 1
fi

# Get the role ID (should be static)
ROLE_ID="b272c720-2106-78c5-b872-4a095860d703"

# Update Kubernetes secret on rop02
echo "Updating Kubernetes secret on rop02..." >> "$LOG_FILE" 2>&1
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rop02_user@10.0.0.3 "
  kubectl delete secret vault-approle-creds -n flask-app --ignore-not-found=true
  kubectl create secret generic vault-approle-creds \
    --from-literal=role_id='$ROLE_ID' \
    --from-literal=secret_id='$NEW_SECRET_ID' \
    -n flask-app
  echo 'Kubernetes secret updated successfully'
" >> "$LOG_FILE" 2>&1; then
  echo "✅ Kubernetes secret updated on rop02" >> "$LOG_FILE"
else
  echo "ERROR: Failed to update Kubernetes secret on rop02" >> "$LOG_FILE"
  exit 1
fi

# Restart Flask deployment to pick up new credentials
echo "Restarting Flask deployment..." >> "$LOG_FILE" 2>&1
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rop02_user@10.0.0.3 "
  kubectl rollout restart deployment/flask-app -n flask-app
  kubectl rollout status deployment/flask-app -n flask-app --timeout=120s
" >> "$LOG_FILE" 2>&1; then
  echo "✅ Flask deployment restarted successfully" >> "$LOG_FILE"
else
  echo "WARNING: Flask deployment restart may have failed, check manually" >> "$LOG_FILE"
fi

# Test the new credentials
echo "Testing new AppRole credentials..." >> "$LOG_FILE" 2>&1
if curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$NEW_SECRET_ID\"}" \
  http://10.0.0.1:8200/v1/auth/approle/login | grep -q "client_token" 2>>"$LOG_FILE"; then
  echo "✅ New AppRole credentials tested successfully" >> "$LOG_FILE"
else
  echo "WARNING: New AppRole credentials test failed" >> "$LOG_FILE"
fi

echo "===== $(date) AppRole secret refresh completed =====" >> "$LOG_FILE" 2>&1 