#!/usr/bin/env bash
# PteroBackup-Lite Installer
# Interactive setup for Pterodactyl backup configuration

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Global variables
CONFIG_FILE="/root/.pterobackup.conf"
LOG_FILE="/var/log/pterobackup.log"
BACKUP_DIR="/root/pterobackup"

# Helper functions
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}         PteroBackup-Lite Installation Wizard            ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_error() {
    echo -e "${RED}✗ Error: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p "$pid" > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

install_dependencies() {
    print_info "Installing required dependencies..."
    apt-get update -qq > /dev/null 2>&1 &
    spinner $!
    apt-get install -y -qq curl wget tar gzip zip unzip mysql-client jq > /dev/null 2>&1 &
    spinner $!
    print_success "Dependencies installed"
}

install_rclone() {
    print_info "Installing rclone..."
    curl -sSL https://rclone.org/install.sh | bash > /dev/null 2>&1 &
    spinner $!
    if command -v rclone &> /dev/null; then
        print_success "rclone installed successfully"
        return 0
    else
        print_error "Failed to install rclone"
        return 1
    fi
}

configure_gdrive() {
    print_info "Configuring Google Drive..."
    if ! command -v rclone &> /dev/null; then
        install_rclone || return 1
    fi
    
    print_info "Please follow the interactive rclone setup for Google Drive"
    print_info "When prompted, select 'n' for new remote, 'drive' for Google Drive"
    print_info "Use your Google Drive credentials"
    
    rclone config
    
    print_info "Testing Google Drive connection..."
    if rclone ls remote: > /dev/null 2>&1; then
        print_success "Google Drive connection verified"
        return 0
    else
        print_error "Failed to verify Google Drive connection"
        return 1
    fi
}

configure_s3() {
    print_info "Configuring Amazon S3..."
    
    read -p "Enter Access Key: " access_key
    read -sp "Enter Secret Key: " secret_key
    echo
    read -p "Enter Region (e.g., us-east-1): " region
    read -p "Enter Bucket Name: " bucket
    
    if [[ -z "$access_key" || -z "$secret_key" || -z "$region" || -z "$bucket" ]]; then
        print_error "All S3 fields are required"
        return 1
    fi
    
    if ! command -v rclone &> /dev/null; then
        install_rclone || return 1
    fi
    
    cat > ~/.config/rclone/rclone.conf << EOF
[s3]
type = s3
provider = AWS
access_key_id = $access_key
secret_access_key = $secret_key
region = $region
endpoint = s3.$region.amazonaws.com
acl = private
storage_class = STANDARD
EOF

    print_info "Testing S3 connection..."
    if rclone ls s3:$bucket > /dev/null 2>&1; then
        print_success "S3 connection verified"
        return 0
    else
        print_error "Failed to verify S3 connection. Check credentials and permissions"
        return 1
    fi
}

configure_mega() {
    print_info "Configuring Mega..."
    
    read -p "Enter Mega Email: " email
    read -sp "Enter Mega Password: " password
    echo
    
    if [[ -z "$email" || -z "$password" ]]; then
        print_error "Email and password are required"
        return 1
    fi
    
    if ! command -v rclone &> /dev/null; then
        install_rclone || return 1
    fi
    
    cat > ~/.config/rclone/rclone.conf << EOF
[mega]
type = mega
user = $email
pass = $password
EOF

    print_info "Testing Mega connection..."
    if rclone ls mega: > /dev/null 2>&1; then
        print_success "Mega connection verified"
        return 0
    else
        print_error "Failed to verify Mega connection. Check credentials"
        return 1
    fi
}

configure_local() {
    print_info "Configuring Local Storage..."
    
    read -p "Enter backup directory path (default: /root/backups): " backup_path
    backup_path=${backup_path:-/root/backups}
    
    mkdir -p "$backup_path"
    if [[ -d "$backup_path" && -w "$backup_path" ]]; then
        print_success "Local storage configured at $backup_path"
        return 0
    else
        print_error "Invalid directory path or no write permissions"
        return 1
    fi
}

select_storage() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           Step 1: Select Storage                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo
    echo "1. Google Drive"
    echo "2. Amazon S3"
    echo "3. Mega"
    echo "4. Local Storage"
    echo
    read -p "Select storage (1-4): " storage_choice
    
    case $storage_choice in
        1)
            STORAGE="gdrive"
            if ! configure_gdrive; then
                print_error "Google Drive configuration failed"
                return 1
            fi
            REMOTE="remote:"
            ;;
        2)
            STORAGE="s3"
            if ! configure_s3; then
                print_error "S3 configuration failed"
                return 1
            fi
            read -p "Enter backup remote path (default: backup): " remote_path
            REMOTE="${remote_path:-backup}:"
            ;;
        3)
            STORAGE="mega"
            if ! configure_mega; then
                print_error "Mega configuration failed"
                return 1
            fi
            REMOTE="mega:"
            ;;
        4)
            STORAGE="local"
            if ! configure_local; then
                print_error "Local storage configuration failed"
                return 1
            fi
            REMOTE="$backup_path"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    return 0
}

select_backup_type() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           Step 2: Select Backup Type              ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo
    echo "1. Panel"
    echo "2. Wings"
    echo "3. Panel + Wings"
    echo
    read -p "Select backup type (1-3): " type_choice
    
    case $type_choice in
        1)
            BACKUP_TYPE="panel"
            ;;
        2)
            BACKUP_TYPE="wings"
            ;;
        3)
            BACKUP_TYPE="both"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    return 0
}

select_backup_mode() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           Step 4: Select Backup Mode              ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo
    echo "1. Keep Every Backup"
    echo "2. Replace Previous Backup"
    echo
    read -p "Select backup mode (1-2): " mode_choice
    
    case $mode_choice in
        1)
            BACKUP_MODE="keep"
            ;;
        2)
            BACKUP_MODE="replace"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    return 0
}

configure_cron() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}         Step 3: Configure Schedule               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo
    echo "Enable automatic backups?"
    echo "1. Yes"
    echo "2. No"
    echo
    read -p "Select option (1-2): " auto_choice
    
    if [[ "$auto_choice" == "2" ]]; then
        CRON=""
        return 0
    fi
    
    echo
    echo "Select backup schedule:"
    echo "1. Every 1 Hour"
    echo "2. Every 6 Hours"
    echo "3. Every 12 Hours"
    echo "4. Every 24 Hours"
    echo "5. Weekly"
    echo "6. Monthly"
    echo "7. Custom Cron Expression"
    echo
    read -p "Select schedule (1-7): " schedule_choice
    
    case $schedule_choice in
        1) CRON="0 */1 * * *" ;;
        2) CRON="0 */6 * * *" ;;
        3) CRON="0 */12 * * *" ;;
        4) CRON="0 0 * * *" ;;
        5) CRON="0 0 * * 0" ;;
        6) CRON="0 0 1 * *" ;;
        7)
            read -p "Enter cron expression (e.g., 0 2 * * *): " CRON
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    print_info "Cron schedule set to: $CRON"
    return 0
}

save_configuration() {
    print_info "Saving configuration..."
    
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    cat > "$CONFIG_FILE" << EOF
STORAGE=$STORAGE
TYPE=$BACKUP_TYPE
MODE=$BACKUP_MODE
CRON=$CRON
REMOTE=$REMOTE
EOF
    
    if [[ -f "$CONFIG_FILE" ]]; then
        print_success "Configuration saved to $CONFIG_FILE"
        return 0
    else
        print_error "Failed to save configuration"
        return 1
    fi
}

setup_cron_job() {
    if [[ -z "$CRON" ]]; then
        print_info "Skipping cron setup"
        return 0
    fi
    
    print_info "Setting up cron job..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
    
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        print_error "backup.sh not found in current directory"
        return 1
    fi
    
    chmod +x "$BACKUP_SCRIPT"
    
    # Remove existing cron job if present
    crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | crontab - 2>/dev/null || true
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT") | crontab -
    
    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
        print_success "Cron job installed: $CRON $BACKUP_SCRIPT"
        return 0
    else
        print_error "Failed to install cron job"
        return 1
    fi
}

main() {
    print_header
    
    check_root
    
    print_info "Checking system compatibility..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]] || [[ ! "$VERSION_ID" =~ ^(22.04|24.04)$ ]]; then
            print_warning "This script is optimized for Ubuntu 22.04/24.04"
        fi
    fi
    
    install_dependencies
    
    print_header
    if ! select_storage; then
        print_error "Storage configuration failed"
        exit 1
    fi
    
    print_header
    if ! select_backup_type; then
        print_error "Backup type selection failed"
        exit 1
    fi
    
    print_header
    if ! configure_cron; then
        print_error "Cron configuration failed"
        exit 1
    fi
    
    print_header
    if ! select_backup_mode; then
        print_error "Backup mode selection failed"
        exit 1
    fi
    
    if ! save_configuration; then
        print_error "Failed to save configuration"
        exit 1
    fi
    
    if ! setup_cron_job; then
        print_warning "Cron setup failed, but installation continues"
    fi
    
    print_header
    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}      Setup Completed Successfully!               ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
    echo
    print_success "Configuration saved to: $CONFIG_FILE"
    print_info "To run a backup manually: bash backup.sh"
    print_info "Backup logs: $LOG_FILE"
    
    if [[ -n "$CRON" ]]; then
        print_info "Scheduled backups: $CRON"
    fi
    
    echo
}

# Run main
main "$@"
