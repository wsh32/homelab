#!/usr/bin/env bash
# Triggered by adnanh/webhook on the deploy VM (nuc-deploy).
# Detects which paths changed and runs the appropriate deploy commands.
# Holds a lock so concurrent webhook firings are dropped.
#
# Called by the webhook daemon with: webhook-deploy.sh <ref>

set -euo pipefail

LOCK_FILE="/var/lock/homelab-deploy.lock"
REPO_ROOT="/home/debian/homelab"
LOG_FILE="/var/log/homelab-deploy.log"

exec >> "$LOG_FILE" 2>&1
echo ""
echo "==> Deploy triggered at $(date) — ref: ${1:-unknown}"

# Drop if a deploy is already running.
if ! flock -n "$LOCK_FILE" true; then
  echo "==> Deploy already in progress — skipping."
  exit 0
fi

exec {LOCK_FD}>"$LOCK_FILE"
flock "$LOCK_FD"

# Pull latest code.
cd "$REPO_ROOT"
git fetch origin main
git reset --hard origin/main

# Detect changed paths since last deploy.
PREV=$(git rev-parse HEAD~1 2>/dev/null || echo "")
CHANGED=$(git diff --name-only "${PREV}" HEAD 2>/dev/null || git diff --name-only HEAD)

echo "==> Changed files:"
echo "$CHANGED"

# terraform/vps/ cannot self-apply — notify and exit.
if echo "$CHANGED" | grep -q "^terraform/vps/"; then
  echo "==> ERROR: terraform/vps/ changed — run manually from operator laptop."
  exit 1
fi

# Terraform apply if NUC or Anton definitions changed.
if echo "$CHANGED" | grep -qE "^terraform/(nuc|anton|modules)/"; then
  echo "==> Running Terraform + Ansible deploy..."
  bash "$REPO_ROOT/scripts/deploy.sh"
fi

# Ansible — run all affected playbooks if ansible/ changed and Terraform didn't trigger already.
if echo "$CHANGED" | grep -q "^ansible/" && ! echo "$CHANGED" | grep -qE "^terraform/(nuc|anton|modules)/"; then
  cd "$REPO_ROOT/ansible"
  echo "==> Running Ansible: VMs (base.yml)..."
  ansible-playbook base.yml
  echo "==> Running Ansible: physical devices (physical.yml)..."
  ansible-playbook physical.yml
  echo "==> Running Ansible: VPS (vps.yml)..."
  ansible-playbook vps.yml
fi

# Docker Compose redeploy if services changed.
if echo "$CHANGED" | grep -q "^services/"; then
  echo "==> Redeploying services..."
  bash "$REPO_ROOT/scripts/deploy-services.sh" "$CHANGED"
fi

echo "==> Deploy complete at $(date)."
