#!/bin/bash

# Setup script for GCP-based AppRole refresh
# This script sets up automated AppRole secret rotation using GCP Secret Manager

set -e

echo "🚀 Setting up GCP-based AppRole Secret Refresh"
echo "=============================================="

# Check if running from correct directory
if [ ! -f "playbooks/rop02/12_setup_gcp_approle_refresh.yml" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    echo "Expected to find: playbooks/rop02/12_setup_gcp_approle_refresh.yml"
    exit 1
fi

# Copy the refresh script to the correct location
echo "📁 Copying refresh script..."
mkdir -p k8s/vault/scripts/
cp k8s/vault/scripts/refresh_approle_secret_gcp.sh k8s/vault/scripts/refresh_approle_secret_gcp.sh

echo "🔧 Running Ansible playbook to set up GCP AppRole refresh..."
cd playbooks/rop02/

# Run the setup playbook
ansible-playbook -i inventory.ini 12_setup_gcp_approle_refresh.yml \
    -e vault_vm_name=rop01

echo ""
echo "✅ Setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Add the SSH public key (shown above) to rop02's authorized_keys"
echo "2. Test the refresh manually:"
echo "   ssh rop01 'cd /k8s/vault/scripts && sudo ./refresh_approle_secret.sh'"
echo ""
echo "3. Monitor the logs:"
echo "   ssh rop01 'sudo tail -f /k8s/vault/scripts/refresh_approle.log'"
echo ""
echo "4. Verify GCP secret:"
echo "   ssh rop01 'gcloud secrets versions access latest --secret=flask-app-approle-secret-id'"
echo ""
echo "🔄 The system will automatically refresh AppRole secrets daily at 3 AM" 