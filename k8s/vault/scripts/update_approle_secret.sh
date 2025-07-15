#!/bin/bash

# AppRole Secret Update Script (for rop02)
# Reads latest AppRole secret ID from GCP and updates Kubernetes secret

LOG_FILE="$(dirname "$0")/update_approle.log"
ROLE_ID="b272c720-2106-78c5-b872-4a095860d703"
FLASK_NAMESPACE="flask-app"
GCP_SERVICE_ACCOUNT_FILE="/k8s/vault/on_vps/vault-service-account.json"

echo "===== $(date) Starting AppRole secret update =====" >> "$LOG_FILE" 2>&1

# Set GCP authentication (if service account file exists)
if [ -f "$GCP_SERVICE_ACCOUNT_FILE" ]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$GCP_SERVICE_ACCOUNT_FILE"
  echo "Using GCP service account file: $GCP_SERVICE_ACCOUNT_FILE" >> "$LOG_FILE" 2>&1
else
  echo "GCP service account file not found, using default authentication" >> "$LOG_FILE" 2>&1
fi

# Retrieve latest secret ID from GCP Secret Manager
echo "Retrieving latest AppRole secret ID from GCP..." >> "$LOG_FILE" 2>&1
NEW_SECRET_ID=$(gcloud secrets versions access latest --secret="flask-app-approle-secret-id" 2>>"$LOG_FILE")

if [ $? -ne 0 ] || [ -z "$NEW_SECRET_ID" ]; then
  echo "ERROR: Failed to retrieve AppRole secret ID from GCP" >> "$LOG_FILE"
  exit 1
fi

echo "Retrieved secret ID: ${NEW_SECRET_ID:0:15}..." >> "$LOG_FILE"

# Check if this is different from current K8s secret
echo "Checking current Kubernetes secret..." >> "$LOG_FILE" 2>&1
CURRENT_SECRET_ID=$(kubectl get secret vault-approle-creds -n $FLASK_NAMESPACE -o jsonpath='{.data.secret_id}' 2>/dev/null | base64 -d)

if [ "$CURRENT_SECRET_ID" = "$NEW_SECRET_ID" ]; then
  echo "Secret ID unchanged, no update needed" >> "$LOG_FILE"
  echo "===== $(date) AppRole secret update completed (no change) =====" >> "$LOG_FILE" 2>&1
  exit 0
fi

echo "Secret ID changed, updating Kubernetes secret..." >> "$LOG_FILE"
echo "Old: ${CURRENT_SECRET_ID:0:15}..." >> "$LOG_FILE"
echo "New: ${NEW_SECRET_ID:0:15}..." >> "$LOG_FILE"

# Update Kubernetes secret
echo "Updating Kubernetes secret..." >> "$LOG_FILE" 2>&1
if kubectl create secret generic vault-approle-creds \
  --from-literal=role_id="$ROLE_ID" \
  --from-literal=secret_id="$NEW_SECRET_ID" \
  -n $FLASK_NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f - >> "$LOG_FILE" 2>&1; then
  echo "✅ Kubernetes secret updated successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to update Kubernetes secret" >> "$LOG_FILE"
  exit 1
fi

# Restart Flask deployment to pick up new credentials
echo "Restarting Flask deployment..." >> "$LOG_FILE" 2>&1
if kubectl rollout restart deployment/flask-app -n $FLASK_NAMESPACE >> "$LOG_FILE" 2>&1; then
  echo "✅ Flask deployment restart initiated" >> "$LOG_FILE"
else
  echo "ERROR: Failed to restart Flask deployment" >> "$LOG_FILE"
  exit 1
fi

# Wait for rollout to complete
echo "Waiting for deployment rollout to complete..." >> "$LOG_FILE" 2>&1
if kubectl rollout status deployment/flask-app -n $FLASK_NAMESPACE --timeout=120s >> "$LOG_FILE" 2>&1; then
  echo "✅ Flask deployment rollout completed successfully" >> "$LOG_FILE"
else
  echo "WARNING: Flask deployment rollout may have failed or timed out" >> "$LOG_FILE"
fi

# Test the new credentials against Vault (through proxy)
echo "Testing new AppRole credentials against Vault..." >> "$LOG_FILE" 2>&1
if curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$NEW_SECRET_ID\"}" \
  http://10.0.0.1:8200/v1/auth/approle/login | grep -q "client_token" 2>>"$LOG_FILE"; then
  echo "✅ New AppRole credentials tested successfully against Vault" >> "$LOG_FILE"
else
  echo "WARNING: New AppRole credentials test failed against Vault" >> "$LOG_FILE"
fi

echo "===== $(date) AppRole secret update completed =====" >> "$LOG_FILE" 2>&1 