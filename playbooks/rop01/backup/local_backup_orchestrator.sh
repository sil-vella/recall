#!/bin/bash

# Local VPS Backup Orchestrator
# Runs from local machine, performs backup on remote VPS, downloads it locally.
# Connection details are read from the Ansible inventory (rop01_user group).

set -e

# Inventory path: default is playbooks/rop01/inventory.ini relative to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INVENTORY="${INVENTORY:-$SCRIPT_DIR/../inventory.ini}"

# Load connection details from inventory (ansible_host, ansible_user, ansible_ssh_private_key_file from [vm_name_user] group)
load_inventory_config() {
    if [ ! -f "$INVENTORY" ]; then
        echo "Error: Inventory not found: $INVENTORY (set INVENTORY= path or run from playbooks/rop01/backup/)" >&2
        exit 1
    fi
    local vm_name host_line
    vm_name=$(sed -n '/^\[all:vars\]/,/^\[/p' "$INVENTORY" | grep -E '^vm_name=' | head -1 | cut -d= -f2)
    if [ -z "$vm_name" ]; then
        echo "Error: Could not find vm_name in [all:vars] in $INVENTORY" >&2
        exit 1
    fi
    host_line=$(awk '/^\['"${vm_name}"'_user\]$/ { getline; print; exit }' "$INVENTORY")
    if [ -z "$host_line" ]; then
        echo "Error: Could not find host line under [${vm_name}_user] in $INVENTORY" >&2
        exit 1
    fi
    VPS_IP=$(echo "$host_line" | grep -oE 'ansible_host=[^ ]+' | cut -d= -f2)
    VPS_USER=$(echo "$host_line" | grep -oE 'ansible_user=[^ ]+' | cut -d= -f2)
    SSH_KEY=$(echo "$host_line" | grep -oE 'ansible_ssh_private_key_file=[^ ]+' | cut -d= -f2)
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    PROJECT_NAME="$vm_name"
    VPS_USERNAME="$VPS_USER"
    REMOTE_SCRIPT_PATH="/home/${VPS_USER}/simple_backup_restore.sh"
    REMOTE_BACKUP_DIR="/home/${VPS_USER}/backup"
}

load_inventory_config

# Local paths (not in inventory)
LOCAL_BACKUP_DIR="./backups"
# Download: 4 parallel streams. Set to 1 for single stream.
PARALLEL_DOWNLOAD_PARTS="${PARALLEL_DOWNLOAD_PARTS:-4}"
# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_config() {
    log_info "Checking configuration..."
    
    if [ ! -f "${SSH_KEY/#\~/$HOME}" ]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    # Test SSH connection
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes "$VPS_USER@$VPS_IP" "echo 'SSH connection OK'" &>/dev/null; then
        log_error "Cannot connect to VPS: $VPS_USER@$VPS_IP"
        log_error "Please check SSH key, IP address, and VPS status"
        exit 1
    fi
    
    log_success "Configuration OK"
}

ensure_remote_script() {
    log_info "Checking backup script on VPS..."
    LOCAL_SCRIPT="$SCRIPT_DIR/simple_backup_restore.sh"
    if command -v sha256sum &>/dev/null; then
        LOCAL_HASH=$(sha256sum "$LOCAL_SCRIPT" 2>/dev/null | awk '{print $1}')
    else
        LOCAL_HASH=$(shasum -a 256 "$LOCAL_SCRIPT" 2>/dev/null | awk '{print $1}')
    fi
    REMOTE_HASH=$(ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "sha256sum '$REMOTE_SCRIPT_PATH' 2>/dev/null | awk '{print \$1}'" || true)
    if [ -n "$REMOTE_HASH" ] && [ "$REMOTE_HASH" = "$LOCAL_HASH" ]; then
        log_success "Remote backup script unchanged, skipping upload"
        return
    fi
    if [ -n "$REMOTE_HASH" ]; then
        log_info "Script differs from local; uploading new one..."
    else
        log_info "No script on VPS (or unreadable); uploading..."
    fi
    # Stream script over SSH with tee (no temp file; works when disk is full or scp write fails)
    if ! cat "$LOCAL_SCRIPT" | ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "sudo tee '$REMOTE_SCRIPT_PATH' > /dev/null && sudo chown $VPS_USER:$VPS_USER '$REMOTE_SCRIPT_PATH' && chmod +x '$REMOTE_SCRIPT_PATH'"; then
        log_error "Upload failed. If the VPS has 'No space left on device', free space first: ssh ... 'df -h' and remove old files under /home/rop01_user/backup/"
        exit 1
    fi
    log_success "Backup script deployed to VPS"
}

backup_vps() {
    log_info "Starting remote VPS backup..."
    
    # Create local backup directory
    mkdir -p "$LOCAL_BACKUP_DIR"
    
    # Create timestamped log file name
    LOCAL_LOG_FILE="$LOCAL_BACKUP_DIR/backup_${PROJECT_NAME}_$(date '+%Y%m%d_%H%M%S').log"
    
    # Run backup on remote VPS with sudo (script requires root for system paths)
    log_info "Executing backup on VPS (sudo)..."
    if ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "sudo $REMOTE_SCRIPT_PATH backup" | tee "$LOCAL_LOG_FILE"; then
        log_success "Remote backup completed"
        log_info "Backup log saved to: $LOCAL_LOG_FILE"
    else
        log_error "Remote backup failed"
        exit 1
    fi
    
    # Get the latest backup filename (.tar.zst preferred, then .tar.gz)
    log_info "Identifying latest backup file..."
    LATEST_BACKUP=$(ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "ls -t $REMOTE_BACKUP_DIR/*.tar.zst $REMOTE_BACKUP_DIR/*.tar.gz 2>/dev/null | head -1")
    
    if [ -z "$LATEST_BACKUP" ]; then
        log_error "No backup file found on VPS"
        exit 1
    fi
    
    BACKUP_FILENAME=$(basename "$LATEST_BACKUP")
    log_info "Latest backup: $BACKUP_FILENAME"
    
    # Download: parallel parts (faster) or single stream (resumable with rsync)
    REMOTE_SIZE=$(ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "stat -c%s '$LATEST_BACKUP' 2>/dev/null" || echo "0")
    USE_PARALLEL=false
    if [ -n "$PARALLEL_DOWNLOAD_PARTS" ] && [ "$PARALLEL_DOWNLOAD_PARTS" -ge 2 ] 2>/dev/null && [ "${REMOTE_SIZE:-0}" -gt 52428800 ]; then
        USE_PARALLEL=true
    fi

    if [ "$USE_PARALLEL" = true ]; then
        log_info "Downloading backup in $PARALLEL_DOWNLOAD_PARTS parallel streams..."
        CHUNK=$((REMOTE_SIZE / PARALLEL_DOWNLOAD_PARTS))
        PART_PREFIX="${LATEST_BACKUP}.part-"
        if ! ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "cd $REMOTE_BACKUP_DIR && split -b $CHUNK '$LATEST_BACKUP' '$PART_PREFIX'"; then
            log_warning "Split failed (e.g. no space on device); cleaning up and falling back to single stream..."
            ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "rm -f $PART_PREFIX* 2>/dev/null"
            USE_PARALLEL=false
        fi
    fi
    if [ "$USE_PARALLEL" = true ]; then
        PARTS=()
        while IFS= read -r line; do PARTS+=( "$line" ); done < <(ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "ls -v $PART_PREFIX* 2>/dev/null")
        for part in "${PARTS[@]}"; do
            scp -i "$SSH_KEY" "$VPS_USER@$VPS_IP:$part" "$LOCAL_BACKUP_DIR/" &
        done
        wait
        cat "$LOCAL_BACKUP_DIR"/"$(basename "$PART_PREFIX")"* > "$LOCAL_BACKUP_DIR/$BACKUP_FILENAME"
        for part in "${PARTS[@]}"; do rm -f "$LOCAL_BACKUP_DIR/$(basename "$part")"; done
        log_info "Removing remote split parts (keeping last backup on VPS)..."
        ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "rm -f $PART_PREFIX*"
        log_success "Backup downloaded to: $LOCAL_BACKUP_DIR/$BACKUP_FILENAME"
    else
        log_info "Downloading backup to local machine..."
        if rsync -avz --progress -e "ssh -i $SSH_KEY" "$VPS_USER@$VPS_IP:$LATEST_BACKUP" "$LOCAL_BACKUP_DIR/"; then
            log_success "Backup downloaded to: $LOCAL_BACKUP_DIR/$BACKUP_FILENAME"
        else
            log_error "Failed to download backup"
            exit 1
        fi
        log_info "Keeping last backup on VPS (not deleted)."
    fi
    
    # Get backup size for info
    LOCAL_BACKUP_SIZE=$(du -h "$LOCAL_BACKUP_DIR/$BACKUP_FILENAME" | cut -f1)
    log_info "Downloaded backup size: $LOCAL_BACKUP_SIZE"
    
    log_success "Backup operation completed successfully!"
    log_info "Local backup location: $LOCAL_BACKUP_DIR/$BACKUP_FILENAME"
}

restore_vps() {
    log_info "Starting VPS restore from local backup..."
    
    # Find latest local backup
    LATEST_LOCAL_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/*.tar.zst "$LOCAL_BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    
    if [ -z "$LATEST_LOCAL_BACKUP" ]; then
        log_error "No local backup files found in $LOCAL_BACKUP_DIR"
        exit 1
    fi
    
    BACKUP_FILENAME=$(basename "$LATEST_LOCAL_BACKUP")
    log_info "Restoring from: $BACKUP_FILENAME"
    
    # Upload backup to VPS
    log_info "Uploading backup to VPS..."
    ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "mkdir -p '$REMOTE_BACKUP_DIR'"
    if scp -i "$SSH_KEY" "$LATEST_LOCAL_BACKUP" "$VPS_USER@$VPS_IP:$REMOTE_BACKUP_DIR/"; then
        log_success "Backup uploaded to VPS"
    else
        log_error "Failed to upload backup to VPS"
        exit 1
    fi
    
    # Run restore on VPS with sudo
    log_info "Executing restore on VPS (sudo)..."
    if ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "sudo $REMOTE_SCRIPT_PATH restore"; then
        log_success "Remote restore completed"
    else
        log_error "Remote restore failed"
        exit 1
    fi
    
    # Clean up uploaded backup
    log_info "Cleaning up uploaded backup file..."
    ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "rm -f '$REMOTE_BACKUP_DIR/$BACKUP_FILENAME'"
    
    log_success "Restore operation completed successfully!"
}

list_backups() {
    log_info "Available local backups:"
    if [ -d "$LOCAL_BACKUP_DIR" ] && [ "$(ls -A $LOCAL_BACKUP_DIR/*.tar.zst $LOCAL_BACKUP_DIR/*.tar.gz 2>/dev/null)" ]; then
        ls -lh "$LOCAL_BACKUP_DIR"/*.tar.zst "$LOCAL_BACKUP_DIR"/*.tar.gz 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    else
        echo "  No local backup files found"
    fi
    
    log_info "Available local backup logs:"
    if [ -d "$LOCAL_BACKUP_DIR" ] && [ "$(ls -A $LOCAL_BACKUP_DIR/*.log 2>/dev/null)" ]; then
        ls -lh "$LOCAL_BACKUP_DIR"/*.log 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    else
        echo "  No local log files found"
    fi
    
    log_info "Remote backups on VPS:"
    ssh -i "$SSH_KEY" "$VPS_USER@$VPS_IP" "ls -lh $REMOTE_BACKUP_DIR/*.tar.zst $REMOTE_BACKUP_DIR/*.tar.gz 2>/dev/null || echo '  No remote backup files found'"
}

cleanup_local() {
    log_info "Cleaning up old local backups and logs (keeping last 5 of each)..."
    if [ -d "$LOCAL_BACKUP_DIR" ]; then
        # Keep only the 5 most recent backups
        ls -t "$LOCAL_BACKUP_DIR"/*.tar.zst "$LOCAL_BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
        # Keep only the 5 most recent log files
        ls -t "$LOCAL_BACKUP_DIR"/*.log 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
        log_success "Local cleanup completed"
    else
        log_warning "Local backup directory does not exist"
    fi
}

show_config() {
    echo "Configuration (from inventory):"
    echo "  Inventory: $INVENTORY"
    echo "  Project / vm_name: $PROJECT_NAME"
    echo "  VPS IP: $VPS_IP"
    echo "  VPS User: $VPS_USER"
    echo "  SSH Key: $SSH_KEY"
    echo "  Remote Script: $REMOTE_SCRIPT_PATH"
    echo "  Remote Backup Dir: $REMOTE_BACKUP_DIR"
    echo "  Local Backup Dir: $LOCAL_BACKUP_DIR"
    echo ""
    echo "Override inventory: INVENTORY=/path/to/inventory.ini $0 config"
    echo ""
    echo "Requirements:"
    echo "  - VPS user ($VPS_USER) must have sudo privileges (passwordless recommended)"
    echo "  - Backup script runs with 'sudo' for system file access"
}

# Main script
case "$1" in
    "backup")
        check_config
        ensure_remote_script
        backup_vps
        ;;
    "restore")
        check_config
        ensure_remote_script
        restore_vps
        ;;
    "list")
        check_config
        list_backups
        ;;
    "cleanup")
        cleanup_local
        ;;
    "config")
        show_config
        ;;
    *)
        echo "Local VPS Backup Orchestrator"
        echo "Usage: $0 {backup|restore|list|cleanup|config}"
        echo ""
        echo "Commands:"
        echo "  backup   - Create backup on VPS and download it locally"
        echo "  restore  - Upload local backup to VPS and restore it"
        echo "  list     - List available local and remote backups"
        echo "  cleanup  - Clean up old local backups (keep last 5)"
        echo "  config   - Show current configuration"
        echo ""
        echo "Examples:"
        echo "  $0 backup    # Backup VPS and download locally"
        echo "  $0 restore   # Restore VPS from local backup"
        echo "  $0 list      # Show available backups"
        echo ""
        echo "Configuration:"
        echo "  Connection details are read from: $INVENTORY"
        echo "  Override: INVENTORY=/path/to/inventory.ini $0 backup"
        exit 1
        ;;
esac
