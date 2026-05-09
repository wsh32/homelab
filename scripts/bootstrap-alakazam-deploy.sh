#!/usr/bin/env bash
# Bootstrap the alakazam-deploy VM (TrueNAS SCALE KVM, Ubuntu 24.04).
# Run once from the operator laptop after creating the VM in TrueNAS UI.
#
# Usage:
#   ssh ubuntu@192.168.0.20 \
#     TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
#     bash -s < scripts/bootstrap-alakazam-deploy.sh
#
# After this:
#   1. Copy terraform.tfvars to ~/homelab/terraform/diglett/ and ~/homelab/terraform/machamp/
#   2. Copy /etc/infisical.env (root-owned, 0600) if restoring an existing machine identity
#   3. Verify: ssh ubuntu@alakazam-deploy (Tailscale MagicDNS)

set -euo pipefail

if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
  echo "Error: TAILSCALE_AUTH_KEY is required"
  exit 1
fi

REPO_URL="https://github.com/wsh32/homelab.git"
REPO_DIR="$HOME/homelab"

echo "==> Updating apt..."
sudo apt-get update -q

echo "==> Installing base packages..."
sudo apt-get install -y -q \
  git curl wget gnupg software-properties-common \
  python3 python3-pip pipx \
  unzip jq

# ── Terraform ────────────────────────────────────────────────────────────────

echo "==> Installing Terraform..."
wget -qO- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
sudo apt-get update -q
sudo apt-get install -y -q terraform

# ── Ansible ──────────────────────────────────────────────────────────────────

echo "==> Installing Ansible..."
pipx install --include-deps ansible
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

# ── Tailscale ────────────────────────────────────────────────────────────────

echo "==> Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up \
  --authkey="${TAILSCALE_AUTH_KEY}" \
  --hostname="alakazam-deploy" \
  --accept-routes

# ── Infisical CLI ─────────────────────────────────────────────────────────────

echo "==> Installing Infisical CLI..."
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' \
  | sudo bash
sudo apt-get install -y -q infisical

# ── Repo ─────────────────────────────────────────────────────────────────────

echo "==> Cloning homelab repo..."
if [[ -d "$REPO_DIR" ]]; then
  echo "    Repo already exists — pulling latest."
  git -C "$REPO_DIR" pull
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "==> Bootstrap complete."
echo ""
echo "Remaining manual steps:"
echo "  1. Copy terraform.tfvars to $REPO_DIR/terraform/diglett/"
echo "     and $REPO_DIR/terraform/machamp/"
echo "  2. If restoring: copy /etc/infisical.env (root:root, 0600)"
echo "  3. Verify Tailscale: tailscale status"
echo "  4. Verify Terraform: cd $REPO_DIR/terraform/diglett && terraform init"
