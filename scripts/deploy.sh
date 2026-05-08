#!/usr/bin/env bash
# deploy.sh — provision VMs with Terraform and apply Ansible base config.
#
# Usage:
#   ./scripts/deploy.sh           # deploy both nodes
#   ./scripts/deploy.sh redstone  # deploy Redstone only
#   ./scripts/deploy.sh anton     # deploy Anton only
#
# Prerequisites:
#   - Storinator NFS mounted at /mnt/terraform-state
#   - terraform.tfvars present in terraform/redstone/ and terraform/anton/
#   - ansible dependencies installed (pip install ansible)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="${1:-both}"

# Validate argument
if [[ "$NODE" != "redstone" && "$NODE" != "anton" && "$NODE" != "both" ]]; then
  echo "Usage: $0 [redstone|anton|both]"
  exit 1
fi

# ── Terraform ────────────────────────────────────────────────────────────────

terraform_apply() {
  local node="$1"
  echo ""
  echo "==> Terraform: applying $node"
  cd "$REPO_ROOT/terraform/$node"
  terraform init -upgrade -input=false
  terraform apply -input=false -auto-approve
  cd "$REPO_ROOT"
}

if [[ "$NODE" == "redstone" || "$NODE" == "both" ]]; then
  terraform_apply redstone
fi

if [[ "$NODE" == "anton" || "$NODE" == "both" ]]; then
  terraform_apply anton
fi

# ── Wait for VMs ─────────────────────────────────────────────────────────────

# Map node argument to Ansible inventory group
ansible_limit() {
  case "$1" in
    redstone) echo "redstone_vms" ;;
    anton) echo "anton_vms" ;;
    both)  echo "vms" ;;
  esac
}

LIMIT="$(ansible_limit "$NODE")"

echo ""
echo "==> Waiting for VMs to be reachable (cloud-init may take a few minutes)..."
cd "$REPO_ROOT/ansible"
ansible "$LIMIT" \
  -m wait_for_connection \
  -a "timeout=300 sleep=10" \
  --timeout=300

# ── Ansible ──────────────────────────────────────────────────────────────────

echo ""
echo "==> Ansible: applying base config to $LIMIT"
ansible-playbook base.yml --limit "$LIMIT"

echo ""
echo "==> Done. VMs provisioned and configured."
