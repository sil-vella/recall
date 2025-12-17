#!/bin/bash

# SSH Key Setup Script for VPS
# This script generates or replaces SSH keys for connecting to the VPS

set -e  # Exit on error, but we'll handle some errors gracefully

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VM_NAME="rop01"
SSH_DIR="$HOME/.ssh"
PRIVATE_KEY="$SSH_DIR/${VM_NAME}_key"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
VPS_IP="65.181.125.135"
VPS_USER="root"

echo -e "${BLUE}=== SSH Key Setup for ${VM_NAME} VPS ===${NC}\n"

# Check if SSH directory exists
if [ ! -d "$SSH_DIR" ]; then
    echo -e "${YELLOW}Creating SSH directory...${NC}"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# Check if key already exists
if [ -f "$PRIVATE_KEY" ]; then
    echo -e "${YELLOW}SSH key already exists: ${PRIVATE_KEY}${NC}"
    echo ""
    echo "What would you like to do?"
    echo "  1) Keep existing key (display public key)"
    echo "  2) Backup and generate new key"
    echo "  3) Remove and generate new key"
    echo "  4) Exit"
    echo ""
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1)
            echo -e "\n${GREEN}Keeping existing key${NC}"
            if [ -f "$PUBLIC_KEY" ]; then
                echo -e "\n${BLUE}Your public key:${NC}"
                echo "----------------------------------------"
                cat "$PUBLIC_KEY"
                echo "----------------------------------------"
                
                # Backup existing keys
                SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                BACKUP_DIR="${SCRIPT_DIR}/backup/ssh_keys"
                BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                
                if [ ! -d "$BACKUP_DIR" ]; then
                    mkdir -p "$BACKUP_DIR"
                    chmod 700 "$BACKUP_DIR"
                fi
                
                if [ -f "$PRIVATE_KEY" ]; then
                    BACKUP_PRIVATE="${BACKUP_DIR}/${VM_NAME}_key_${BACKUP_TIMESTAMP}"
                    cp "$PRIVATE_KEY" "$BACKUP_PRIVATE"
                    chmod 600 "$BACKUP_PRIVATE"
                    echo -e "${GREEN}✓ Backed up private key to: ${BACKUP_PRIVATE}${NC}"
                fi
                
                if [ -f "$PUBLIC_KEY" ]; then
                    BACKUP_PUBLIC="${BACKUP_DIR}/${VM_NAME}_key_${BACKUP_TIMESTAMP}.pub"
                    cp "$PUBLIC_KEY" "$BACKUP_PUBLIC"
                    chmod 644 "$BACKUP_PUBLIC"
                    echo -e "${GREEN}✓ Backed up public key to: ${BACKUP_PUBLIC}${NC}"
                fi
                
                # Ask if user wants to automatically add key to VPS
                echo ""
                read -p "Do you want to automatically add this key to the VPS? (y/n): " auto_add
                if [[ "$auto_add" =~ ^[Yy]$ ]]; then
                    echo ""
                    echo -e "${YELLOW}You will be prompted for the VPS password...${NC}"
                    
                    # Check if sshpass is available
                    if command -v sshpass &> /dev/null; then
                        read -sp "Enter VPS password for ${VPS_USER}@${VPS_IP}: " vps_password
                        echo ""
                        
                        if [ -z "$vps_password" ]; then
                            echo -e "${RED}Password cannot be empty. Skipping automatic key addition.${NC}"
                        else
                            echo -e "\n${BLUE}Copying SSH key to VPS...${NC}"
                            set +e  # Don't exit on error for SSH operations
                            sshpass -p "$vps_password" ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=accept-new "${VPS_USER}@${VPS_IP}" 2>/dev/null
                            COPY_RESULT=$?
                            set -e  # Re-enable exit on error
                            
                            if [ $COPY_RESULT -eq 0 ]; then
                                echo -e "${GREEN}✓ SSH key successfully added to VPS!${NC}"
                                
                                # Test the connection
                                echo -e "\n${BLUE}Testing SSH connection...${NC}"
                                set +e
                                sshpass -p "$vps_password" ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS_USER}@${VPS_IP}" "echo 'SSH key authentication successful!'" 2>/dev/null
                                TEST_RESULT=$?
                                set -e
                                
                                if [ $TEST_RESULT -eq 0 ]; then
                                    echo -e "${GREEN}✓ SSH connection test successful!${NC}"
                                else
                                    echo -e "${YELLOW}⚠ Connection test failed, but key may have been added.${NC}"
                                    echo -e "${YELLOW}You may need to wait a moment for SSH to update, or test manually.${NC}"
                                fi
                            else
                                echo -e "${RED}✗ Failed to add SSH key to VPS.${NC}"
                                echo -e "${YELLOW}Please check the password and try again, or add the key manually.${NC}"
                            fi
                            unset vps_password
                        fi
                    else
                        echo -e "${YELLOW}sshpass not found. Using interactive method...${NC}"
                        set +e
                        ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=accept-new "${VPS_USER}@${VPS_IP}"
                        COPY_RESULT=$?
                        set -e
                        
                        if [ $COPY_RESULT -eq 0 ]; then
                            echo -e "${GREEN}✓ SSH key successfully added to VPS!${NC}"
                            
                            # Test the connection
                            echo -e "\n${BLUE}Testing SSH connection...${NC}"
                            set +e
                            ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS_USER}@${VPS_IP}" "echo 'SSH key authentication successful!'" 2>/dev/null
                            TEST_RESULT=$?
                            set -e
                            
                            if [ $TEST_RESULT -eq 0 ]; then
                                echo -e "${GREEN}✓ SSH connection test successful!${NC}"
                            else
                                echo -e "${YELLOW}⚠ Connection test failed, but key may have been added.${NC}"
                                echo -e "${YELLOW}You may need to wait a moment for SSH to update, or test manually.${NC}"
                            fi
                        else
                            echo -e "${RED}✗ Failed to add SSH key to VPS.${NC}"
                            echo -e "${YELLOW}Please try again or add the key manually.${NC}"
                        fi
                    fi
                else
                    echo -e "\n${YELLOW}Add this key to the VPS by running on the server:${NC}"
                    echo "  mkdir -p ~/.ssh"
                    echo "  echo '$(cat "$PUBLIC_KEY")' >> ~/.ssh/authorized_keys"
                    echo "  chmod 700 ~/.ssh"
                    echo "  chmod 600 ~/.ssh/authorized_keys"
                fi
                
                echo -e "\n${GREEN}=== Setup Complete ===${NC}"
                echo -e "Private key: ${PRIVATE_KEY}"
                echo -e "Public key:  ${PUBLIC_KEY}"
                echo -e "Backup location: ${BACKUP_DIR}"
            else
                echo -e "${RED}Error: Public key not found!${NC}"
                exit 1
            fi
            exit 0
            ;;
        2)
            BACKUP_KEY="${PRIVATE_KEY}.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${YELLOW}Backing up existing key to: ${BACKUP_KEY}${NC}"
            cp "$PRIVATE_KEY" "$BACKUP_KEY"
            if [ -f "$PUBLIC_KEY" ]; then
                cp "$PUBLIC_KEY" "${BACKUP_KEY}.pub"
            fi
            rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"
            ;;
        3)
            echo -e "${YELLOW}Removing existing key...${NC}"
            rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting...${NC}"
            exit 1
            ;;
    esac
fi

# Generate new SSH key pair
echo -e "\n${GREEN}Generating new SSH key pair...${NC}"
echo -e "${BLUE}Key type: ED25519 (recommended)${NC}"
echo -e "${BLUE}Key location: ${PRIVATE_KEY}${NC}"
echo ""

# Generate ED25519 key (more secure and faster than RSA)
ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -C "${VM_NAME}_vps_$(date +%Y%m%d)" -N ""

# Set proper permissions
chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

echo -e "\n${GREEN}✓ SSH key pair generated successfully!${NC}\n"

# Display public key
echo -e "${BLUE}=== Your Public Key ===${NC}"
echo "----------------------------------------"
cat "$PUBLIC_KEY"
echo "----------------------------------------"

# Ask if user wants to automatically add key to VPS
echo ""
read -p "Do you want to automatically add this key to the VPS? (y/n): " auto_add
if [[ "$auto_add" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}You will be prompted for the VPS password...${NC}"
    
    # Check if sshpass is available
    if command -v sshpass &> /dev/null; then
        # Use sshpass for non-interactive password entry
        read -sp "Enter VPS password for ${VPS_USER}@${VPS_IP}: " vps_password
        echo ""
        
        if [ -z "$vps_password" ]; then
            echo -e "${RED}Password cannot be empty. Skipping automatic key addition.${NC}"
        else
            echo -e "\n${BLUE}Copying SSH key to VPS...${NC}"
            set +e
            sshpass -p "$vps_password" ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=accept-new "${VPS_USER}@${VPS_IP}" 2>/dev/null
            COPY_RESULT=$?
            set -e
            
            if [ $COPY_RESULT -eq 0 ]; then
                echo -e "${GREEN}✓ SSH key successfully added to VPS!${NC}"
                
                # Test the connection
                echo -e "\n${BLUE}Testing SSH connection...${NC}"
                set +e
                sshpass -p "$vps_password" ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS_USER}@${VPS_IP}" "echo 'SSH key authentication successful!'" 2>/dev/null
                TEST_RESULT=$?
                set -e
                
                if [ $TEST_RESULT -eq 0 ]; then
                    echo -e "${GREEN}✓ SSH connection test successful!${NC}"
                else
                    echo -e "${YELLOW}⚠ Connection test failed, but key may have been added.${NC}"
                    echo -e "${YELLOW}You may need to wait a moment for SSH to update, or test manually.${NC}"
                fi
            else
                echo -e "${RED}✗ Failed to add SSH key to VPS.${NC}"
                echo -e "${YELLOW}Please check the password and try again, or add the key manually.${NC}"
            fi
            # Clear password from memory
            unset vps_password
        fi
    else
        # Fallback to interactive ssh-copy-id
        echo -e "${YELLOW}sshpass not found. Using interactive method...${NC}"
        echo -e "${BLUE}You will be prompted for the VPS password:${NC}"
        set +e
        ssh-copy-id -i "$PUBLIC_KEY" -o StrictHostKeyChecking=accept-new "${VPS_USER}@${VPS_IP}"
        COPY_RESULT=$?
        set -e
        
        if [ $COPY_RESULT -eq 0 ]; then
            echo -e "${GREEN}✓ SSH key successfully added to VPS!${NC}"
            
            # Test the connection
            echo -e "\n${BLUE}Testing SSH connection...${NC}"
            set +e
            ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS_USER}@${VPS_IP}" "echo 'SSH key authentication successful!'" 2>/dev/null
            TEST_RESULT=$?
            set -e
            
            if [ $TEST_RESULT -eq 0 ]; then
                echo -e "${GREEN}✓ SSH connection test successful!${NC}"
            else
                echo -e "${YELLOW}⚠ Connection test failed, but key may have been added.${NC}"
                echo -e "${YELLOW}You may need to wait a moment for SSH to update, or test manually.${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to add SSH key to VPS.${NC}"
            echo -e "${YELLOW}Please try again or add the key manually.${NC}"
        fi
    fi
else
    # Instructions for manual addition
    echo -e "\n${YELLOW}=== Manual Key Addition ===${NC}"
    echo ""
    echo "Add the key to the VPS by running:"
    echo "  ssh-copy-id -i ${PUBLIC_KEY} ${VPS_USER}@${VPS_IP}"
    echo ""
    echo "Or manually:"
    echo "  ssh ${VPS_USER}@${VPS_IP}"
    echo "  mkdir -p ~/.ssh"
    echo "  echo '$(cat "$PUBLIC_KEY")' >> ~/.ssh/authorized_keys"
    echo "  chmod 700 ~/.ssh"
    echo "  chmod 600 ~/.ssh/authorized_keys"
    echo ""
fi

# Optional: Add to SSH config
read -p "Add to SSH config for easier access? (y/n): " add_to_config
if [[ "$add_to_config" =~ ^[Yy]$ ]]; then
    SSH_CONFIG="$SSH_DIR/config"
    HOST_ALIAS="${VM_NAME}_vps"
    
    # Create config if it doesn't exist
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    
    # Check if entry already exists
    if grep -q "Host ${HOST_ALIAS}" "$SSH_CONFIG" 2>/dev/null; then
        echo -e "${YELLOW}Entry already exists in SSH config${NC}"
    else
        echo "" >> "$SSH_CONFIG"
        echo "# ${VM_NAME} VPS" >> "$SSH_CONFIG"
        echo "Host ${HOST_ALIAS}" >> "$SSH_CONFIG"
        echo "    HostName ${VPS_IP}" >> "$SSH_CONFIG"
        echo "    User ${VPS_USER}" >> "$SSH_CONFIG"
        echo "    IdentityFile ${PRIVATE_KEY}" >> "$SSH_CONFIG"
        echo "    IdentitiesOnly yes" >> "$SSH_CONFIG"
        echo "" >> "$SSH_CONFIG"
        
        echo -e "${GREEN}✓ Added to SSH config${NC}"
        echo -e "You can now connect using: ${BLUE}ssh ${HOST_ALIAS}${NC}"
    fi
fi

# Backup SSH keys to backup directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup/ssh_keys"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "\n${BLUE}Backing up SSH keys...${NC}"

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    echo -e "${YELLOW}Created backup directory: ${BACKUP_DIR}${NC}"
fi

# Copy keys to backup directory with timestamp
if [ -f "$PRIVATE_KEY" ]; then
    BACKUP_PRIVATE="${BACKUP_DIR}/${VM_NAME}_key_${BACKUP_TIMESTAMP}"
    cp "$PRIVATE_KEY" "$BACKUP_PRIVATE"
    chmod 600 "$BACKUP_PRIVATE"
    echo -e "${GREEN}✓ Backed up private key to: ${BACKUP_PRIVATE}${NC}"
fi

if [ -f "$PUBLIC_KEY" ]; then
    BACKUP_PUBLIC="${BACKUP_DIR}/${VM_NAME}_key_${BACKUP_TIMESTAMP}.pub"
    cp "$PUBLIC_KEY" "$BACKUP_PUBLIC"
    chmod 644 "$BACKUP_PUBLIC"
    echo -e "${GREEN}✓ Backed up public key to: ${BACKUP_PUBLIC}${NC}"
fi


echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "Private key: ${PRIVATE_KEY}"
echo -e "Public key:  ${PUBLIC_KEY}"
echo -e "Backup location: ${BACKUP_DIR}"
