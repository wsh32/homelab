#!/usr/bin/env bash
# Install the Proxmox cluster CA certificate on the deploy VM.
# Run after authorizing the deploy VM's SSH key on Proxmox nodes (step 7b).
# Required for Terraform to verify TLS when connecting to the Proxmox API.
#
# Both Machamp and Diglett share the same CA (same cluster), so one fetch suffices.

set -euo pipefail

NODE="${1:-machamp.local}"

echo "==> Fetching Proxmox CA certificate from ${NODE}..."
scp "root@${NODE}:/etc/pve/pve-root-ca.pem" /tmp/proxmox-ca.pem

echo "==> Installing certificate..."
sudo cp /tmp/proxmox-ca.pem /usr/local/share/ca-certificates/proxmox.crt
sudo update-ca-certificates
rm /tmp/proxmox-ca.pem

echo "==> Done. Terraform will now verify TLS connections to the Proxmox API."
