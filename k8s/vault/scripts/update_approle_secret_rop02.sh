#!/bin/bash

LOG_FILE="$(dirname "$0")/update_approle_rop02.log"
GCLOUD_PATH="/home/rop02_user/google-cloud-sdk/bin/gcloud"

echo "===== $(date) Starting AppRole secret update on rop02 =====" >> "$LOG_FILE" 2>&1

# Verify gcloud is available
if [ ! -f "$GCLOUD_PATH" ]; then
  echo "ERROR: gcloud not found at $GCLOUD_PATH" >> "$LOG_FILE"
  exit 1
fi

# Get the new secret ID from GCP Secret Manager
echo "Retrieving secret ID from GCP Secret Manager..." >> "$LOG_FILE" 2>&1
NEW_SECRET_ID=$($GCLOUD_PATH secrets versions access latest --secret=flask-app-approle-secret-id 2>>"$LOG_FILE")

if [ $? -ne 0 ] || [ -z "$NEW_SECRET_ID" ]; then
  echo "ERROR: Failed to retrieve secret ID from GCP Secret Manager" >> "$LOG_FILE"
  exit 1
fi

echo "Retrieved secret ID: ${NEW_SECRET_ID:0:15}..." >> "$LOG_FILE"

# Get the role ID (should be static)
ROLE_ID="b272c720-2106-78c5-b872-4a095860d703"

# Update Kubernetes secret
echo "Updating Kubernetes secret..." >> "$LOG_FILE" 2>&1
if kubectl delete secret vault-approle-creds -n flask-app --ignore-not-found=true >> "$LOG_FILE" 2>&1 && \
   kubectl create secret generic vault-approle-creds \
     --from-literal=role_id="$ROLE_ID" \
     --from-literal=secret_id="$NEW_SECRET_ID" \
     -n flask-app >> "$LOG_FILE" 2>&1; then
  echo "✅ Kubernetes secret updated successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to update Kubernetes secret" >> "$LOG_FILE"
  exit 1
fi

# Restart Flask deployment to pick up new credentials
echo "Restarting Flask deployment..." >> "$LOG_FILE" 2>&1
if kubectl rollout restart deployment/flask-app -n flask-app >> "$LOG_FILE" 2>&1 && \
   kubectl rollout status deployment/flask-app -n flask-app --timeout=120s >> "$LOG_FILE" 2>&1; then
  echo "✅ Flask deployment restarted successfully" >> "$LOG_FILE"
else
  echo "WARNING: Flask deployment restart may have failed, check manually" >> "$LOG_FILE"
fi

# Test the new credentials by checking if Flask pod can authenticate to Vault
echo "Testing new AppRole credentials..." >> "$LOG_FILE" 2>&1
if curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$NEW_SECRET_ID\"}" \
  http://10.0.0.1:8200/v1/auth/approle/login | grep -q "client_token" >> "$LOG_FILE" 2>&1; then
  echo "✅ New AppRole credentials tested successfully" >> "$LOG_FILE"
else
  echo "WARNING: New AppRole credentials test failed" >> "$LOG_FILE"
fi

echo "===== $(date) AppRole secret update completed on rop02 =====" >> "$LOG_FILE" 2>&1 