# AppRole Secret Refresh System

This system provides automated AppRole secret rotation for the Flask application using GCP Secret Manager as the coordination layer.

## Architecture

- **rop01**: Vault server with root access - generates new AppRole secrets
- **rop02**: Flask application server - consumes AppRole secrets
- **GCP Secret Manager**: Central storage for secret coordination

## Components

### rop01 Scripts

**Location**: `/home/rop01_user/vault_scripts/`

- `generate_new_approle_secret.sh`: Generates new AppRole secret and stores in GCP
  - Uses Vault root token to generate secrets
  - Uses `sudo gcloud` (root has GCP authentication)
  - Stores secrets in GCP Secret Manager

### rop02 Scripts

**Location**: `/home/rop02_user/vault_scripts/`

- `update_approle_secret_rop02.sh`: Retrieves secrets from GCP and updates K8s
  - Uses gcloud CLI (user has GCP authentication)
  - Updates Kubernetes secret `vault-approle-creds` in `flask-app` namespace
  - Restarts Flask deployment to pick up new credentials

### Automation

**rop02 Cron Job**: Runs every 12 hours (AppRole secrets have 24h TTL)
```bash
0 */12 * * * /home/rop02_user/vault_scripts/update_approle_secret_rop02.sh
```

## Usage

### Manual Secret Rotation

1. **Generate new secret on rop01**:
   ```bash
   ssh rop01 '/home/rop01_user/vault_scripts/generate_new_approle_secret.sh'
   ```

2. **Apply new secret on rop02** (optional - will happen automatically):
   ```bash
   ssh rop02 '/home/rop02_user/vault_scripts/update_approle_secret_rop02.sh'
   ```

### Logs

- **rop01**: `/home/rop01_user/vault_scripts/generate_approle.log`
- **rop02**: `/home/rop02_user/vault_scripts/update_approle_rop02.log`

## Security Notes

- rop01 uses Vault root token (stored in `~/.vault-token`)
- rop02 uses GCP service account authentication
- All secrets are stored in GCP Secret Manager with versioning
- AppRole secrets have 24-hour TTL for security

## Monitoring

Check logs regularly to ensure:
- Secret generation succeeds on rop01
- Secret retrieval and application succeeds on rop02
- Flask deployment restarts successfully
- Vault authentication tests pass 