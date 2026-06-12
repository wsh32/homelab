#!/usr/bin/env bash
# Minimal bootstrap for a new physical device.
# Gets Tailscale running so Ansible can reach the device for all further config.
# Run once via SSH from the operator laptop.
#
# Usage:
#   ssh root@<device-ip> \
#     TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
#     bash -s < scripts/bootstrap-physical.sh
#
# After this, run: ansible-playbook ansible/physical.yml --limit <hostname>

set -euo pipefail

if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
  echo "Error: TAILSCALE_AUTH_KEY is required"
  exit 1
fi

echo "==> Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up \
  --authkey="${TAILSCALE_AUTH_KEY}" \
  --hostname="$(hostname)" \
  --accept-routes

echo "==> Bootstrap complete. Run: ansible-playbook ansible/physical.yml --limit $(hostname)"
