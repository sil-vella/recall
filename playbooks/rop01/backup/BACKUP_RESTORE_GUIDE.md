# VPS Backup and Restore Guide (rop01)

## 🎯 **Overview**

This guide covers backup and restore for the **rop01** VPS (Dutch stack). The system uses **local orchestration** (runs from your Mac) and **remote execution** (runs on VPS as `rop01_user` with `sudo`).

**Key Features:**
- ✨ **One-command backup from local machine**
- 📊 **Local log capture** with timestamped files
- ⬇️ **Backup downloaded to your Mac** (then removed from VPS)
- 🔥 **Firewall rules backup** (iptables + UFW)
- 🧹 **Automatic cleanup** and file management
- 🔄 **Cross-server migration support**

## 📦 **What Gets Backed Up**

### **rop01 / Dutch Stack (primary):**
- `/opt/apps/reignofplay/dutch` - App directory, Docker Compose, data
- `/var/www` - Nginx site roots (reignofplay.com, dutch.reignofplay.com)
- `/etc/nginx`, `/var/log/nginx` - Nginx config and logs
- `/etc/letsencrypt`, `/var/lib/letsencrypt` - SSL certificates
- `/var/mail/vhosts`, `/etc/postfix`, `/etc/dovecot` - Mail (if set up)

### **Network & Security:**
- `/etc/iptables` - **IPv4 & IPv6 firewall rules** 🔥
- `/etc/ufw` - **UFW firewall configuration** 🔥
- `/etc/fail2ban` - Security monitoring
- `/etc/ssh` - SSH server configurations

### **User Data & System:**
- `/home` - **User home directories**
- `/root` - **Root user data and configurations**
- `/etc/systemd/system` - Custom system services
- `/etc/passwd`, `/etc/group`, `/etc/shadow` - User accounts
- `/etc/sudoers`, `/etc/sudoers.d` - Sudo permissions
- `/etc/hosts`, `/etc/resolv.conf` - Network configuration
- Cron: `/var/spool/cron`, `/etc/crontab`, `/etc/cron.d`, etc.

### **Optional (other VPS; skipped if missing):**
- `/etc/rancher`, `/var/lib/rancher`, `/var/lib/kubelet`, `/var/lib/cni` - Kubernetes
- `/etc/wireguard` - WireGuard VPN

## 🚀 **Quick Commands (Local Orchestrator)**

### **From your Mac (in `playbooks/rop01/backup/` directory):**

```bash
cd playbooks/rop01/backup

# Create backup and download locally
./local_backup_orchestrator.sh backup

# List all backups and logs
./local_backup_orchestrator.sh list

# Restore VPS from local backup
./local_backup_orchestrator.sh restore

# Clean up old files (keep last 5)
./local_backup_orchestrator.sh cleanup

# Show configuration
./local_backup_orchestrator.sh config
```

## ⚙️ **Configuration**

### **Connection details from inventory**
The orchestrator reads connection details from the Ansible inventory (no hardcoded IP/user/key in the script):

- **Inventory path:** `playbooks/rop01/inventory.ini` (relative to the script), or set **`INVENTORY=/path/to/inventory.ini`** to override.
- It uses **`vm_name`** from `[all:vars]` and the host line under **`[rop01_user]`** (i.e. `[${vm_name}_user]`) to get:
  - **ansible_host** → VPS IP  
  - **ansible_user** → VPS user  
  - **ansible_ssh_private_key_file** → SSH key path  

So keep `inventory.ini` in sync with your playbooks; the backup script will use the same host, user, and key.

**Other (local-only) settings:**
- Local Backup Dir: `./backups` (relative to script)
- Override inventory: `INVENTORY=/path/to/inventory.ini ./local_backup_orchestrator.sh backup`

**Faster download (optional):**
- **`PARALLEL_DOWNLOAD_PARTS=4`** (default) – splits the backup on the server and downloads 4 chunks in parallel, then reassembles locally. Much faster than a single stream for large files (e.g. 4× throughput).
- Set **`PARALLEL_DOWNLOAD_PARTS=1`** to use a single **rsync** stream (resumable if interrupted).
- **Compression:** The backup script uses **zstd** on the server when available (smaller and faster than gzip), producing `.tar.zst`; otherwise `.tar.gz`.

## 📋 **Complete Workflow**

### **1. Prerequisites**
```bash
# Verify VPS connectivity (no VPN required; public IP)
ping 65.181.125.135

# Ensure you can SSH as rop01_user
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 "echo 'Connection OK'"
```

### **2. First-Time Setup**
The orchestrator automatically:
- Tests SSH connectivity
- Deploys `simple_backup_restore.sh` to `/home/rop01_user/simple_backup_restore.sh`
- Runs backup on VPS with **sudo** (so system paths are readable)

### **3. Backup Process**
```bash
./local_backup_orchestrator.sh backup
```

**What happens:**
1. 🔍 **Configuration check** - Verifies SSH, IP, and key
2. 📤 **Script deployment** - Copies latest backup script to VPS (if needed)
3. 🔄 **Remote backup execution** - Runs `sudo simple_backup_restore.sh backup` on VPS
4. 📊 **Local log capture** - Saves all output to a timestamped log in `./backups/`
5. ⬇️ **Download** - Copies the backup from VPS to `./backups/` on your Mac
6. **VPS keeps last backup** - The backup is left on the VPS (max 1; old ones are removed before each new run)

### **4. Backup Results**
- **Backup file**: `./backups/YYYYMMDD_HHMMSS.tar.zst` or `.tar.gz` (on your Mac)
- **Log file**: `./backups/backup_rop01_YYYYMMDD_HHMMSS.log`
- **Location**: `playbooks/rop01/backup/backups/`
- **Tip:** On the VPS, `sudo apt install zstd` ensures backups use zstd (smaller file → faster download). The script falls back to gzip if zstd is not installed.

## 🔄 **Migration to New VPS**

### **Step 1: Backup current VPS**
```bash
./local_backup_orchestrator.sh backup
```

### **Step 2: Update configuration**
Edit `local_backup_orchestrator.sh`:
```bash
VPS_IP="NEW_VPS_IP"   # New VPS address
# Ensure the new VPS has rop01_user (or update VPS_USER) and the same SSH key
```

### **Step 3: Restore on new VPS**
```bash
./local_backup_orchestrator.sh restore
```

The script will:
- Upload the latest local backup to the VPS
- Run restore with sudo on the VPS
- Restart services as defined in the backup script
- Remove the uploaded file from the VPS

## 🔥 **Firewall Backup**

Included in the backup:
- **iptables** rules (`/etc/iptables`)
- **UFW** configuration (`/etc/ufw`)

Restoring ensures firewall rules are reapplied with the rest of the config.

## 📊 **File Management**

### **Automatic cleanup**
```bash
./local_backup_orchestrator.sh cleanup
```
- Keeps the last **5** backup files
- Keeps the last **5** log files
- Removes older files in `./backups/`

### **List backups and logs**
```bash
./local_backup_orchestrator.sh list
```
Shows:
- Local backup files and sizes
- Local log files
- Remote backups on VPS (if any remain)

## 📈 **Monitoring & Logs**

### **Local log files**
- **Location**: `./backups/backup_rop01_YYYYMMDD_HHMMSS.log`
- **Content**: Full output from the remote backup run
- **Includes**: System info, path sizes, success/skip counts

### **Log analysis**
```bash
# View latest backup log
ls -t ./backups/*.log 2>/dev/null | head -1 | xargs cat

# Check for errors
grep -i error ./backups/*.log

# View backup summary
grep "Backup summary" ./backups/*.log
```

## ⚠️ **Important Notes**

### **Requirements**
- **SSH key** at `~/.ssh/rop01_key` (same as Ansible inventory)
- **VPS user** `rop01_user` with **passwordless sudo** (as set by playbooks)
- No WireGuard or VPN required; rop01 uses the public IP

### **Security**
- Backups include `/etc/shadow`, SSH keys, and certificates
- Store backup files securely on your Mac
- The VPS keeps at most one backup (the latest); it is not deleted after download so you always have the last backup on the server too.

### **Remote script**
- The backup script on the VPS runs with **sudo** so it can read `/etc`, `/root`, etc.
- The backup file and directory are chown’d to `rop01_user` so the orchestrator can `scp` it without root.

## 🔧 **Troubleshooting**

### **Connection issues**
```bash
# Test SSH
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 "echo 'Connection OK'"

# Show orchestrator config
./local_backup_orchestrator.sh config
```

### **Backup issues**
```bash
# Disk space on VPS
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 "df -h"

# Local disk space
df -h .

# Recent logs
tail -50 ./backups/backup_rop01_*.log 2>/dev/null | tail -50
```

### **Restore issues**
```bash
# Check backup contents
tar -tzf ./backups/LATEST_BACKUP.tar.gz | head -20

# After restore: check services
ssh -i ~/.ssh/rop01_key rop01_user@65.181.125.135 "systemctl status nginx docker"
```

## 📈 **Automation Options**

### **Scheduled backups**
```bash
# Example: daily backup at 02:00 (run from backup dir)
0 2 * * * cd /path/to/playbooks/rop01/backup && ./local_backup_orchestrator.sh backup

# Weekly cleanup (e.g. Sunday 03:00)
0 3 * * 0 cd /path/to/playbooks/rop01/backup && ./local_backup_orchestrator.sh cleanup
```

## 🎉 **Success Indicators**

### **After a successful backup**
- ✅ Backup `.tar.gz` in `./backups/`
- ✅ Log file in `./backups/backup_rop01_*.log`
- ✅ Last backup kept on VPS (max 1)
- ✅ rop01 paths included (e.g. `/opt/apps/reignofplay/dutch`, `/etc/nginx`)

### **After a successful restore**
- ✅ SSH as `rop01_user` works
- ✅ Nginx and Docker (and app) run as expected
- ✅ Firewall rules present (`iptables -L` / `ufw status`)

## 🔄 **Script Summary**

| Script | Role |
|--------|------|
| **local_backup_orchestrator.sh** | Run on your Mac. SSHs to rop01, runs remote backup with sudo (VPS keeps max 1 backup), downloads to `./backups/`, leaves the last backup on the VPS. |
| **simple_backup_restore.sh** | Deployed to `/home/rop01_user/` on the VPS. Run with sudo; backs up configured paths into `/home/rop01_user/backup/` and creates a timestamped `.tar.gz`. |
| **backup_restore.sh** | Restic-based script for another VPS; not used by the rop01 orchestrator. |

---

**Last Updated**: February 2026  
**Version**: 3.0 (rop01)  
**Target**: rop01 VPS @ 65.181.125.135, user `rop01_user`, Dutch stack (Nginx, Docker, optional mail)
