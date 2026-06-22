#!/bin/bash

set -e

echo "=================================="
echo " Infinity Host Backup Installer"
echo "=================================="

REPO_RAW="https://github.com/alokgamer-22103/autobackup/blob/main/backup.py"

apt-get update -y
apt-get install -y python3 python3-pip curl

pip3 install rich

mkdir -p /opt/infinity-backup

curl -fsSL "$REPO_RAW/backup.py" -o /opt/infinity-backup/backup.py

chmod +x /opt/infinity-backup/backup.py

ln -sf /opt/infinity-backup/backup.py /usr/local/bin/ih-backup

echo ""
echo "Installation completed."
echo "Run command: ih-backup"
