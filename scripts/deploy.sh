#!/usr/bin/env bash
# deploy.sh — provision VMs with Terraform and apply Ansible base config.
#
# Usage:
#   ./scripts/deploy.sh           # deploy both nodes
#   ./scripts/deploy.sh diglett  # deploy Diglett only
#   ./scripts/deploy.sh machamp     # deploy Machamp only
#
# Prerequisites:
#   - Snorlax NFS mounted at /mnt/terraform-state
#   - terraform.tfvars present in terraform/diglett/ and terraform/machamp/
#   - ansible dependencies installed (pip install ansible)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="${1:-both}"

# Validate argument
if [[ "$NODE" != "diglett" && "$NODE" != "machamp" && "$NODE" != "both" ]]; then
  echo "Usage: $0 [diglett|machamp|both]"
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

if [[ "$NODE" == "diglett" || "$NODE" == "both" ]]; then
  terraform_apply diglett
fi

if [[ "$NODE" == "machamp" || "$NODE" == "both" ]]; then
  terraform_apply machamp
fi

# ── Wait for VMs ─────────────────────────────────────────────────────────────

# Map node argument to Ansible inventory group
ansible_limit() {
  case "$1" in
    diglett) echo "diglett_vms" ;;
    machamp) echo "machamp_vms" ;;
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
