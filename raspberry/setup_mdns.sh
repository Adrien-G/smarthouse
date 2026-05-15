#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="${1:-raspberrypi}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo ./setup_mdns.sh ${HOSTNAME}"
  exit 1
fi

echo "Setting hostname to: ${HOSTNAME}"
hostnamectl set-hostname "${HOSTNAME}"

if ! command -v avahi-daemon >/dev/null 2>&1 || ! dpkg -s libnss-mdns >/dev/null 2>&1; then
  echo "Installing mDNS packages..."
  apt-get update
  apt-get install -y avahi-daemon libnss-mdns
fi

echo "Updating /etc/hosts..."
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127.0.1.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
else
  printf "127.0.1.1\t%s\n" "${HOSTNAME}" >> /etc/hosts
fi

echo "Enabling avahi-daemon..."
systemctl enable avahi-daemon
systemctl restart avahi-daemon

echo "mDNS is configured."
echo "After a few seconds, test from another device:"
echo "  ping ${HOSTNAME}.local"
echo "  curl http://${HOSTNAME}.local:8080/api/health"
