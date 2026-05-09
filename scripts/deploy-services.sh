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
  ssh -o StrictHostKeyChecking=no "ubuntu@${vm}.ts.home" \
    "cd /home/ubuntu/homelab/${service_dir} && docker compose pull && docker compose up -d"
}

if echo "$CHANGED" | grep -q "^services/dns/"; then
  deploy_service "diglett-dns" "services/dns"
fi

if echo "$CHANGED" | grep -q "^services/diglett-infra/"; then
  deploy_service "diglett-infisical" "services/diglett-infra"
fi

if echo "$CHANGED" | grep -q "^services/diglett-deploy/"; then
  deploy_service "diglett-deploy" "services/diglett-deploy"
fi

if echo "$CHANGED" | grep -q "^services/machamp/"; then
  deploy_service "machamp-services" "services/machamp"
fi

if echo "$CHANGED" | grep -q "^services/vps/"; then
  echo "  ==> VPS services deploy via ansible-pull — no action needed."
fi
