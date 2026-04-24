#!/usr/bin/env bash
# Redeploy Docker Compose services on the appropriate VMs.
# Called by webhook-deploy.sh when services/ paths change.
#
# Usage:
#   ./scripts/deploy-services.sh <changed_files_list>
#
# SSH access to VMs is via Tailscale SSH (key-based, no password).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGED="${1:-}"

deploy_service() {
  local vm="$1" service_dir="$2"
  echo "  ==> Deploying ${service_dir} on ${vm}..."
  ssh -o StrictHostKeyChecking=no "debian@${vm}.ts.home" \
    "cd /home/debian/homelab/${service_dir} && docker compose pull && docker compose up -d"
}

if echo "$CHANGED" | grep -q "^services/dns/"; then
  deploy_service "nuc-dns" "services/dns"
fi

if echo "$CHANGED" | grep -q "^services/nuc-infra/"; then
  deploy_service "nuc-infisical" "services/nuc-infra"
fi

if echo "$CHANGED" | grep -q "^services/nuc-deploy/"; then
  deploy_service "nuc-deploy" "services/nuc-deploy"
fi

if echo "$CHANGED" | grep -q "^services/anton/"; then
  deploy_service "anton-services" "services/anton"
fi

if echo "$CHANGED" | grep -q "^services/vps/"; then
  echo "  ==> VPS services deploy via ansible-pull — no action needed."
fi
