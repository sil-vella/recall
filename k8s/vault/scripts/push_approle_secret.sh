#!/bin/bash

# AppRole Secret Push Script (for rop01)
# Generates new AppRole secret ID, stores in GCP, and pushes to rop02

LOG_FILE="$(dirname "$0")/push_approle.log"
VAULT_ADDR="http://localhost:8200"
ROLE_ID="b272c720-2106-78c5-b872-4a095860d703"

echo "===== $(date) Starting AppRole secret push =====" >> "$LOG_FILE" 2>&1

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

# Store new secret ID in GCP Secret Manager
echo "Storing new secret ID in GCP Secret Manager..." >> "$LOG_FILE" 2>&1
if echo -n "$NEW_SECRET_ID" | gcloud secrets versions add flask-app-approle-secret-id --data-file=- 2>>"$LOG_FILE"; then
  echo "✅ Secret ID stored in GCP Secret Manager successfully" >> "$LOG_FILE"
else
  echo "ERROR: Failed to store secret ID in GCP Secret Manager" >> "$LOG_FILE"
  exit 1
fi

# Test the new credentials against Vault
echo "Testing new AppRole credentials..." >> "$LOG_FILE" 2>&1
if curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$NEW_SECRET_ID\"}" \
  http://localhost:8200/v1/auth/approle/login | grep -q "client_token" 2>>"$LOG_FILE"; then
  echo "✅ New AppRole credentials tested successfully against Vault" >> "$LOG_FILE"
else
  echo "WARNING: New AppRole credentials test failed against Vault" >> "$LOG_FILE"
fi

# Create a temporary file with the new secret
TEMP_SECRET_FILE="/tmp/new_approle_secret_$$"
cat > "$TEMP_SECRET_FILE" << EOF
ROLE_ID=$ROLE_ID
SECRET_ID=$NEW_SECRET_ID
EOF

echo "Pushing new secret to rop02..." >> "$LOG_FILE" 2>&1

# Copy the secret file to rop02 and execute update
if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$TEMP_SECRET_FILE" rop02_user@10.0.0.3:/tmp/new_approle_secret 2>>"$LOG_FILE"; then
  echo "Secret file transferred to rop02" >> "$LOG_FILE"
else
  echo "ERROR: Failed to transfer secret file to rop02" >> "$LOG_FILE"
  rm -f "$TEMP_SECRET_FILE"
  exit 1
fi

# Execute the update on rop02
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rop02_user@10.0.0.3 "
  source /tmp/new_approle_secret
  echo 'Updating Kubernetes secret with new AppRole credentials...'
  kubectl create secret generic vault-approle-creds \
    --from-literal=role_id=\"\$ROLE_ID\" \
    --from-literal=secret_id=\"\$SECRET_ID\" \
    -n flask-app \
    --dry-run=client -o yaml | kubectl apply -f -
  
  echo 'Restarting Flask deployment...'
  kubectl rollout restart deployment/flask-app -n flask-app
  kubectl rollout status deployment/flask-app -n flask-app --timeout=120s
  
  echo 'Cleaning up temporary file...'
  rm -f /tmp/new_approle_secret
  
  echo 'AppRole secret update completed on rop02'
" 2>>"$LOG_FILE"; then
  echo "✅ AppRole secret successfully updated on rop02" >> "$LOG_FILE"
else
  echo "ERROR: Failed to update AppRole secret on rop02" >> "$LOG_FILE"
fi

# Clean up temporary file
rm -f "$TEMP_SECRET_FILE"

echo "===== $(date) AppRole secret push completed =====" >> "$LOG_FILE" 2>&1 