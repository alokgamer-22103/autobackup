#!/usr/bin/env bash
# PteroBackup-Lite Backup Script
# Creates and uploads backups of Pterodactyl Panel and/or Wings

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
CONFIG_FILE="/root/.pterobackup.conf"
LOG_FILE="/var/log/pterobackup.log"
TEMP_DIR="/tmp/pterobackup_$$"
BACKUP_NAME=""
BACKUP_FILE=""
STORAGE=""
BACKUP_TYPE=""
BACKUP_MODE=""
CRON=""
REMOTE=""

# Helper functions
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ Error: $1${NC}" >&2
    log_message "ERROR" "$1"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log_message "INFO" "$1"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
    log_message "INFO" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log_message "WARNING" "$1"
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

progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percent=$((current * 100 / total))
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%" "$percent"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

load_configuration() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found. Please run install.sh first"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    if [[ -z "$STORAGE" || -z "$TYPE" || -z "$MODE" || -z "$REMOTE" ]]; then
        print_error "Invalid configuration file"
        exit 1
    fi
    
    BACKUP_TYPE="$TYPE"
    BACKUP_MODE="$MODE"
    
    print_info "Loaded configuration from $CONFIG_FILE"
}

check_dependencies() {
    local missing_deps=()
    
    for cmd in tar gzip mysql mysqldump; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ "$STORAGE" != "local" ]] && ! command -v rclone &> /dev/null; then
        missing_deps+=("rclone")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Run: apt-get install -y ${missing_deps[*]}"
        exit 1
    fi
}

create_backup_name() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    BACKUP_NAME="pterobackup_${BACKUP_TYPE}_${timestamp}"
    BACKUP_FILE="${TEMP_DIR}/${BACKUP_NAME}.tar.gz"
}

backup_panel() {
    print_info "Backing up Panel..."
    
    local panel_paths=(
        "/var/www/pterodactyl"
    )
    
    # Check if Panel is installed
    if [[ ! -d "/var/www/pterodactyl" ]]; then
        print_error "Panel directory not found. Is Pterodactyl Panel installed?"
        return 1
    fi
    
    # Create temporary backup directory
    mkdir -p "${TEMP_DIR}/panel"
    
    # Copy panel files
    for path in "${panel_paths[@]}"; do
        if [[ -e "$path" ]]; then
            cp -r "$path" "${TEMP_DIR}/panel/" 2>/dev/null || true
        fi
    done
    
    # Export MySQL database
    if [[ -f "/var/www/pterodactyl/.env" ]]; then
        local db_host=$(grep "^DB_HOST=" /var/www/pterodactyl/.env | cut -d'=' -f2)
        local db_port=$(grep "^DB_PORT=" /var/www/pterodactyl/.env | cut -d'=' -f2)
        local db_database=$(grep "^DB_DATABASE=" /var/www/pterodactyl/.env | cut -d'=' -f2)
        local db_username=$(grep "^DB_USERNAME=" /var/www/pterodactyl/.env | cut -d'=' -f2)
        local db_password=$(grep "^DB_PASSWORD=" /var/www/pterodactyl/.env | cut -d'=' -f2)
        
        print_info "Exporting MySQL database..."
        mysqldump -h "${db_host:-localhost}" -P "${db_port:-3306}" -u "$db_username" -p"$db_password" "$db_database" > "${TEMP_DIR}/panel/database.sql" 2>/dev/null
        
        if [[ -f "${TEMP_DIR}/panel/database.sql" ]]; then
            print_success "Database exported successfully"
        else
            print_warning "Failed to export database"
        fi
    else
        print_warning ".env file not found, skipping database export"
    fi
    
    print_success "Panel backup completed"
    return 0
}

backup_wings() {
    print_info "Backing up Wings..."
    
    local wings_paths=(
        "/etc/pterodactyl"
        "/var/lib/pterodactyl"
    )
    
    # Check if Wings is installed
    if [[ ! -d "/etc/pterodactyl" ]]; then
        print_error "Wings configuration directory not found. Is Wings installed?"
        return 1
    fi
    
    # Create temporary backup directory
    mkdir -p "${TEMP_DIR}/wings"
    
    # Copy wings files
    for path in "${wings_paths[@]}"; do
        if [[ -e "$path" ]]; then
            cp -r "$path" "${TEMP_DIR}/wings/" 2>/dev/null || true
        fi
    done
    
    print_success "Wings backup completed"
    return 0
}

create_backup() {
    print_info "Creating backup archive..."
    
    mkdir -p "$TEMP_DIR"
    create_backup_name
    
    local backup_success=true
    
    case "$BACKUP_TYPE" in
        panel)
            if ! backup_panel; then
                backup_success=false
            fi
            ;;
        wings)
            if ! backup_wings; then
                backup_success=false
            fi
            ;;
        both)
            if ! backup_panel || ! backup_wings; then
                backup_success=false
            fi
            ;;
        *)
            print_error "Invalid backup type: $BACKUP_TYPE"
            return 1
            ;;
    esac
    
    if [[ "$backup_success" == "false" ]]; then
        print_error "Backup creation failed"
        return 1
    fi
    
    # Create tar archive
    print_info "Compressing backup..."
    tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" . 2>/dev/null &
    local tar_pid=$!
    spinner $tar_pid
    
    if [[ -f "$BACKUP_FILE" ]]; then
        local size=$(du -h "$BACKUP_FILE" | cut -f1)
        print_success "Backup created: $BACKUP_NAME ($size)"
        return 0
    else
        print_error "Failed to create backup archive"
        return 1
    fi
}

upload_backup() {
    print_info "Uploading backup to storage..."
    
    local upload_file="$BACKUP_FILE"
    local remote_path="$REMOTE"
    
    if [[ "$STORAGE" == "local" ]]; then
        remote_path="$REMOTE/$BACKUP_NAME.tar.gz"
        print_info "Copying to local storage: $remote_path"
        
        mkdir -p "$(dirname "$remote_path")"
        cp "$upload_file" "$remote_path" 2>/dev/null
        
        if [[ -f "$remote_path" ]]; then
            print_success "Backup copied to local storage"
            return 0
        else
            print_error "Failed to copy backup to local storage"
            return 1
        fi
    else
        # Handle rclone upload with progress
        remote_path="$REMOTE$BACKUP_NAME.tar.gz"
        print_info "Uploading to $STORAGE..."
        
        rclone copy "$upload_file" "$remote_path" --progress 2>/dev/null &
        local rclone_pid=$!
        spinner $rclone_pid
        
        if rclone ls "$remote_path" > /dev/null 2>&1; then
            print_success "Backup uploaded successfully"
            return 0
        else
            print_error "Failed to upload backup"
            return 1
        fi
    fi
}

manage_backups() {
    if [[ "$BACKUP_MODE" == "replace" ]]; then
        print_info "Replacing previous backup..."
        
        if [[ "$STORAGE" == "local" ]]; then
            # List and delete previous backups
            find "$REMOTE" -name "pterobackup_*.tar.gz" -type f -not -name "$BACKUP_NAME.tar.gz" -delete 2>/dev/null || true
            print_success "Previous backups removed"
        else
            # List and delete previous backups using rclone
            local backup_pattern="pterobackup_${BACKUP_TYPE}_*.tar.gz"
            rclone ls "$REMOTE" | grep "pterobackup_${BACKUP_TYPE}_" | awk '{print $2}' | while read -r file; do
                if [[ "$file" != "$BACKUP_NAME.tar.gz" ]]; then
                    rclone delete "$REMOTE$file" 2>/dev/null
                    print_info "Deleted previous backup: $file"
                fi
            done
            print_success "Previous backups removed"
        fi
    else
        print_info "Keeping all backups (Keep Mode)"
    fi
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    if [[ -f "$BACKUP_FILE" && "$STORAGE" != "local" ]]; then
        rm -f "$BACKUP_FILE" 2>/dev/null || true
    fi
}

show_summary() {
    echo
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${GREEN}           Backup Completed Successfully!          ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo
    print_info "Backup Name: $BACKUP_NAME"
    print_info "Backup Type: $BACKUP_TYPE"
    print_info "Storage: $STORAGE"
    print_info "Mode: $BACKUP_MODE"
    print_info "Log: $LOG_FILE"
    echo
}

main() {
    check_root
    
    print_info "Starting PteroBackup-Lite..."
    
    load_configuration
    check_dependencies
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Create backup
    if ! create_backup; then
        cleanup
        exit 1
    fi
    
    # Upload backup
    if ! upload_backup; then
        cleanup
        exit 1
    fi
    
    # Manage backups
    manage_backups
    
    # Cleanup
    cleanup
    
    # Show summary
    show_summary
    
    print_success "Backup completed successfully"
    exit 0
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main
main "$@"
