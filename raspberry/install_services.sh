#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-/opt/smarthouse}"
SERVICE_USER="${2:-adrien}"
SERVICE_GROUP="${3:-${SERVICE_USER}}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_RASPBERRY_DIR="${INSTALL_DIR}/raspberry"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo ./install_services.sh [install_dir] [user] [group]"
  exit 1
fi

echo "Installing SmartHouse Raspberry files to ${TARGET_RASPBERRY_DIR}"
mkdir -p "${TARGET_RASPBERRY_DIR}"
cp -r "${SOURCE_DIR}/." "${TARGET_RASPBERRY_DIR}/"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}"

echo "Installing Python serial dependency..."
apt-get update
apt-get install -y python3-serial

echo "Adding ${SERVICE_USER} to dialout group for serial port access..."
usermod -aG dialout "${SERVICE_USER}"

echo "Installing systemd services for user ${SERVICE_USER}:${SERVICE_GROUP}"
for service in smarthouse-linky-reader.service smarthouse-linky-api.service; do
  sed \
    -e "s#WorkingDirectory=/opt/smarthouse/raspberry#WorkingDirectory=${TARGET_RASPBERRY_DIR}#g" \
    -e "s#ExecStart=/usr/bin/python3 /opt/smarthouse/raspberry/#ExecStart=/usr/bin/python3 ${TARGET_RASPBERRY_DIR}/#g" \
    -e "s#User=adrien#User=${SERVICE_USER}#g" \
    -e "s#Group=adrien#Group=${SERVICE_GROUP}#g" \
    "${SOURCE_DIR}/systemd/${service}" > "/etc/systemd/system/${service}"
done

systemctl daemon-reload
systemctl enable smarthouse-linky-reader.service
systemctl enable smarthouse-linky-api.service
systemctl restart smarthouse-linky-reader.service
systemctl restart smarthouse-linky-api.service

echo "Services installed and started."
echo "Check status with:"
echo "  systemctl status smarthouse-linky-reader.service"
echo "  systemctl status smarthouse-linky-api.service"
echo "Watch logs with:"
echo "  journalctl -u smarthouse-linky-reader.service -f"
echo "  journalctl -u smarthouse-linky-api.service -f"
