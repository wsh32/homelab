#!/usr/bin/env bash
# Bootstrap the alakazam-deploy VM (TrueNAS SCALE KVM, Ubuntu 24.04).
# Run once from the operator laptop after creating the VM in TrueNAS UI.
#
# Installs Ansible, then uses it to configure the VM (base + deploy roles).
# All tool installs (Terraform, Infisical, etc.) happen inside the playbook.
#
# Usage:
#   ssh ubuntu@192.168.0.7 \
#     TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
#     bash -s < scripts/bootstrap-alakazam-deploy.sh
#
# After this:
#   1. Copy terraform.tfvars to ~/homelab/terraform/diglett/ and ~/homelab/terraform/machamp/
#   2. Mount Terraform state NFS share (see runbook step 7a)
#   3. Authorize SSH key on Proxmox nodes and install CA cert (runbook step 7b):
#        ssh-copy-id -i ~/.ssh/id_ed25519.pub root@machamp.local
#        ssh-copy-id -i ~/.ssh/id_ed25519.pub root@diglett.local
#        bash ~/homelab/scripts/install-proxmox-ca.sh
#   4. If restoring: copy /etc/infisical.env (root:root, 0600)
#   5. Verify Tailscale: tailscale status

set -euo pipefail

if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
  echo "Error: TAILSCALE_AUTH_KEY is required"
  exit 1
fi

REPO_URL="https://github.com/wsh32/homelab.git"
REPO_DIR="$HOME/homelab"

# ── Minimal prerequisites for Ansible ────────────────────────────────────────

echo "==> Installing prerequisites..."
sudo apt-get update -q
sudo apt-get install -y -q git python3 python3-pip pipx

# Allow passwordless sudo so Ansible can run become tasks non-interactively.
# Matches what cloud-init configures on Terraform-provisioned VMs.
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd > /dev/null
sudo chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

echo "==> Installing Ansible..."
pipx install --include-deps ansible
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

# ── Repo ─────────────────────────────────────────────────────────────────────

echo "==> Cloning homelab repo..."
if [[ -d "$REPO_DIR" ]]; then
  echo "    Repo already exists -- pulling latest."
  git -C "$REPO_DIR" pull
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

# ── Ansible self-configuration ────────────────────────────────────────────────
# Configures this VM (base hardening + deploy tooling) without SSHing to itself.

echo "==> Configuring VM via Ansible..."
cd "$REPO_DIR/ansible"
ansible-playbook deploy-vm.yml --limit alakazam-deploy --connection=local

# ── Tailscale join ────────────────────────────────────────────────────────────
# Tailscale is installed by the base role above; join the network here.

echo "==> Joining Tailscale network..."
sudo tailscale up \
  --authkey="${TAILSCALE_AUTH_KEY}" \
  --hostname="alakazam-deploy" \
  --accept-routes

echo ""
echo "==> Bootstrap complete."
echo ""
echo "Remaining manual steps:"
echo "  1. Copy terraform.tfvars to $REPO_DIR/terraform/diglett/"
echo "     and $REPO_DIR/terraform/machamp/"
echo "  2. Mount Terraform state NFS share (see runbook step 7a)"
echo "  3. Authorize SSH key on Proxmox nodes and install CA cert:"
echo "       ssh-copy-id -i ~/.ssh/id_ed25519.pub root@machamp.local"
echo "       ssh-copy-id -i ~/.ssh/id_ed25519.pub root@diglett.local"
echo "       bash $REPO_DIR/scripts/install-proxmox-ca.sh"
echo "  4. If restoring: copy /etc/infisical.env (root:root, 0600)"
echo "  5. Verify Tailscale: tailscale status"
