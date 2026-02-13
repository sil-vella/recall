#!/bin/bash

# Simple VPS Backup and Restore Script
# Focuses on critical configurations only

set -e

# Configuration - Auto-detect project username; backup dir in user home so orchestrator can scp
PROJECT_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | head -1)
BACKUP_NAME="${PROJECT_USER}-vps-backup"
BACKUP_DIR="/home/${PROJECT_USER}/backup"
CRITICAL_PATHS=(
    # rop01 / Dutch stack
    "/opt/apps/reignofplay/dutch"
    "/var/www"
    "/etc/nginx"
    "/var/log/nginx"
    "/etc/letsencrypt"
    "/var/lib/letsencrypt"
    "/var/mail/vhosts"
    "/etc/postfix"
    "/etc/dovecot"
    # common system (/home often large; add back if you have space)
    # "/home"
    "/root"
    "/etc/ssh"
    "/etc/systemd/system"
    "/etc/fail2ban"
    "/etc/iptables"
    "/etc/ufw"
    "/var/spool/cron"
    "/etc/crontab"
    "/etc/cron.d"
    "/etc/cron.daily"
    "/etc/cron.weekly"
    "/etc/cron.monthly"
    "/etc/cron.hourly"
    "/etc/hosts"
    "/etc/resolv.conf"
    "/etc/passwd"
    "/etc/group"
    "/etc/shadow"
    "/etc/sudoers"
    "/etc/sudoers.d"
    # optional (other VPS; skipped if missing)
    "/etc/rancher"
    "/var/lib/rancher"
    "/etc/wireguard"
    "/var/lib/kubelet"
    "/var/lib/cni"
)

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_info "Current user: $(whoami), EUID: $EUID"
        exit 1
    fi
}

backup_vps() {
    log_info "Starting VPS backup..."
    log_info "Backup started at: $(date)"
    log_info "Backup initiated by user: $(whoami)"
    log_info "System: $(hostname) - $(uname -a)"

    mkdir -p "$BACKUP_DIR"
    if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
        chown "${SUDO_UID}:${SUDO_GID}" "$BACKUP_DIR" 2>/dev/null || true
    fi

    # Keep at most 1 backup on VPS: remove any existing before creating new one
    log_info "Removing old backups on VPS (max 1 kept)..."
    rm -f "$BACKUP_DIR"/*.tar.zst "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true

    # Require at least 1G free on backup dir's filesystem (avoid "No space left on device")
    MIN_FREE_KB="${BACKUP_MIN_FREE_KB:-1048576}"
    AVAIL_KB=$(df -k "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
        log_error "Insufficient disk space on $BACKUP_DIR (need at least $((MIN_FREE_KB / 1024 / 1024))G free; have $((AVAIL_KB / 1024 / 1024))G). Free space or set BACKUP_MIN_FREE_KB (bytes) / use a different BACKUP_DIR."
        exit 1
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    TOP="backup-$TIMESTAMP"
    META_DIR="/tmp/$TOP"
    mkdir -p "$META_DIR"
    trap "rm -rf '$META_DIR'" EXIT

    cat > "$META_DIR/system-info.txt" << EOF
VPS Backup Information
======================
Date: $(date)
Hostname: $(hostname)
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
Kernel: $(uname -r)
Architecture: $(uname -m)
CPU: $(nproc) cores
Memory: $(free -h | grep Mem | awk '{print $2}')
Disk: $(df -h / | tail -1 | awk '{print $2}')
Uptime: $(uptime -p)

Kubernetes Status:
$(kubectl version --short 2>/dev/null || echo "Kubernetes not available")

WireGuard Status:
$(wg show 2>/dev/null || echo "WireGuard not available")

SSH Status:
$(systemctl is-active ssh 2>/dev/null || echo "SSH not available")
EOF

    # Build list of existing paths (no leading slash) for streaming into archive
    PATHS=()
    for path in "${CRITICAL_PATHS[@]}"; do
        if [ -e "$path" ]; then
            log_info "Will include: $path"
            PATHS+=("${path#/}")
        else
            log_warning "✗ Path does not exist: $path"
        fi
    done
    log_info "Streaming ${#PATHS[@]} paths directly into archive (no staging copy)..."

    ARCHIVE_NAME=""
    ARCHIVE_PATH="$BACKUP_DIR/${TIMESTAMP}.tar.zst"
    if command -v zstd &>/dev/null; then
        ARCHIVE_NAME="${TIMESTAMP}.tar.zst"
        if tar -C / -I 'zstd -3 -T0' -cf "$ARCHIVE_PATH" --transform "s,^,$TOP/," -C /tmp "$TOP" -C / "${PATHS[@]}"; then
            log_success "✓ Archive created (zstd): $ARCHIVE_NAME"
        else
            ARCHIVE_NAME=""
            rm -f "$ARCHIVE_PATH"
        fi
    fi
    if [ -z "$ARCHIVE_NAME" ]; then
        ARCHIVE_PATH="$BACKUP_DIR/${TIMESTAMP}.tar.gz"
        ARCHIVE_NAME="${TIMESTAMP}.tar.gz"
        if tar -C / -czf "$ARCHIVE_PATH" --transform "s,^,$TOP/," -C /tmp "$TOP" -C / "${PATHS[@]}"; then
            log_success "✓ Archive created (gzip): $ARCHIVE_NAME"
        else
            log_error "✗ Failed to create archive"
            rm -f "$ARCHIVE_PATH"
            exit 1
        fi
    fi

    if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
        chown "${SUDO_UID}:${SUDO_GID}" "$ARCHIVE_PATH" 2>/dev/null || true
    fi

    COMPRESSED_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)
    log_info "Compressed backup size: $COMPRESSED_SIZE"
    log_success "VPS backup completed: $BACKUP_DIR/$ARCHIVE_NAME"
    log_info "Backup finished at: $(date)"
}

restore_vps() {
    log_info "Starting VPS restore..."
    
    # Find latest backup (.tar.zst or .tar.gz)
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.zst "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        log_error "No backup files found in $BACKUP_DIR"
        exit 1
    fi
    
    log_info "Restoring from: $LATEST_BACKUP"
    
    TEMP_DIR="/tmp/vps-restore-$$"
    mkdir -p "$TEMP_DIR"
    case "$LATEST_BACKUP" in
        *.tar.zst) tar -I zstd -xf "$LATEST_BACKUP" -C "$TEMP_DIR" ;;
        *)         tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" ;;
    esac
    
    # Find the extracted directory
    EXTRACTED_DIR=$(ls "$TEMP_DIR" | head -1)
    RESTORE_PATH="$TEMP_DIR/$EXTRACTED_DIR"
    
    # Restore critical paths
    for path in "${CRITICAL_PATHS[@]}"; do
        BACKUP_PATH="$RESTORE_PATH$path"
        if [ -e "$BACKUP_PATH" ]; then
            log_info "Restoring: $path"
            # Create destination directory if needed
            mkdir -p "$(dirname "$path")"
            # Copy with preserve attributes
            cp -a "$BACKUP_PATH" "$(dirname "$path")/"
        fi
    done
    
    # Restart services
    log_info "Restarting services..."
    systemctl daemon-reload
    systemctl restart ssh
    systemctl restart k3s 2>/dev/null || true
    systemctl restart wireguard 2>/dev/null || true
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    log_success "VPS restore completed successfully!"
}

list_backups() {
    log_info "Available backups:"
    if [ -d "$BACKUP_DIR" ]; then
        ls -lh "$BACKUP_DIR"/*.tar.zst "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backup files found"
    else
        echo "Backup directory does not exist"
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping last 5)..."
    if [ -d "$BACKUP_DIR" ]; then
        ls -t "$BACKUP_DIR"/*.tar.zst "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
        log_success "Cleanup completed"
    else
        log_warning "Backup directory does not exist"
    fi
}

# Main script
case "$1" in
    "backup")
        check_root
        backup_vps
        ;;
    "restore")
        check_root
        restore_vps
        ;;
    "list")
        list_backups
        ;;
    "cleanup")
        check_root
        cleanup_old_backups
        ;;
    *)
        echo "Simple VPS Backup and Restore Script"
        echo "Usage: $0 {backup|restore|list|cleanup}"
        echo ""
        echo "Commands:"
        echo "  backup   - Create a complete backup of critical VPS configs"
        echo "  restore  - Restore the VPS from the latest backup"
        echo "  list     - List available backups"
        echo "  cleanup  - Clean up old backups (keep last 5)"
        echo ""
        echo "Examples:"
        echo "  $0 backup    # Create backup"
        echo "  $0 restore   # Restore from backup"
        echo "  $0 list      # Show available backups"
        exit 1
        ;;
esac 