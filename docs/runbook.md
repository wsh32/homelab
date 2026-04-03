# Bootstrap Runbook

Step-by-step rebuild guide. Follow in order. After completing this runbook,
all infrastructure is managed via Terraform and all services are running.

---

## Prerequisites

Tools required on the operator laptop:

```bash
# Terraform >= 1.9
terraform -version

# Ansible
ansible --version

# Infisical CLI >= 0.28
infisical --version

# SSH key pair (used for VM access)
ls ~/.ssh/id_ed25519.pub
```

Install if missing:
```bash
brew install terraform ansible infisical/tap/infisical
ssh-keygen -t ed25519  # if no key exists
```

---

## Phase 1 — Manual (one-time, UI-based)

### 1. Form the Proxmox cluster

On the NUC (primary node):
1. Log into the Proxmox web UI at `https://192.168.0.6:8006`
2. Datacenter → Cluster → Create Cluster → name it `homelab`
3. Copy the join information

On Anton:
1. Log into the Proxmox web UI at `https://192.168.0.5:8006`
2. Datacenter → Cluster → Join Cluster → paste join information

Verify: both nodes appear under Datacenter in either UI.

**Quorum recovery** (if a node is offline and cluster is stuck):
```bash
# Run on the surviving node
pvecm expected 1
```

### 2. Create Proxmox API tokens

Repeat on **both** Anton (`192.168.0.5:8006`) and NUC (`192.168.0.6:8006`):

1. Datacenter → Permissions → Users → Add: `terraform@pam`
2. Datacenter → Permissions → Add → User Permission: path `/`, user `terraform@pam`, role `Administrator`
3. Datacenter → Permissions → API Tokens → Add:
   - User: `terraform@pam`
   - Token ID: `terraform`
   - **Uncheck** Privilege Separation
4. Copy the token secret — it is only shown once. Format: `terraform@pam!terraform=<uuid>`

### 3. Create NFS datasets on Storinator

Log into TrueNAS at `https://192.168.0.4`:

1. Storage → Create Pool (if not already done): name `pool`
2. Datasets → Add Dataset for each:
   - `pool/terraform-state`
   - `pool/docker`
   - `pool/backups`
   - `pool/media`
   - `pool/photos`
   - `pool/lightroom`
3. Sharing → NFS → Add for each dataset that VMs mount:
   - Path: `/mnt/pool/terraform-state`, Networks: `192.168.0.0/24`, `Maproot User: root`
   - Path: `/mnt/pool/docker`, Networks: `192.168.0.0/24`, `Maproot User: root`
4. Services → NFS → Start, set to start automatically

### 4. Generate a Tailscale auth key

1. Go to `https://login.tailscale.com/admin/settings/keys`
2. Generate auth key:
   - Reusable: **yes**
   - Ephemeral: **no**
   - Tags: `tag:homelab` (create the tag first under Access Controls if needed)
3. Copy the key (`tskey-auth-...`) — you'll use it in steps 5 and 6

---

## Phase 2 — Ansible (physical nodes)

### 5. Configure static IPs on physical nodes

**Anton and NUC** (Proxmox — Ansible-managed):

First, find the physical NIC name on each machine (the one bridged to `vmbr0`):
```bash
ssh root@192.168.0.5 ip link show   # anton
ssh root@192.168.0.6 ip link show   # nuc
```

Look for the interface that is not `lo` or `vmbr0` — typically `eno1`, `enp2s0`, or similar.
Update `bridge_port` for each host in `network.yml` (repo root), then run:

```bash
ansible-playbook ansible/network.yml
```

**Storinator and Gringotts** (TrueNAS — manual):
1. Log into TrueNAS UI → Network → Interfaces
2. Edit the primary interface → set Static IP, disable DHCP
3. Set IP to `192.168.0.4` (Storinator) / `192.168.0.8` (Gringotts), gateway `192.168.0.1`

**Orange Pi** — defer until OS is chosen.

### 6. Install Tailscale on physical nodes

```bash
cd /path/to/homelab

# Install Ansible dependencies
pip install ansible

# Run the Tailscale playbook against all physical nodes
# (Anton, NUC, Storinator, Orange Pi)
TAILSCALE_AUTH_KEY=tskey-auth-REPLACE_ME \
  ansible-playbook ansible/tailscale.yml --ask-become-pass
```

Verify all four nodes appear in the Tailscale admin console.

---

## Phase 3 — Terraform (first apply)

### 7. Mount Storinator NFS on the operator laptop

```bash
sudo mkdir -p /mnt/terraform-state
sudo mount -t nfs storinator:/mnt/pool/terraform-state /mnt/terraform-state

# Verify
ls /mnt/terraform-state   # should be empty or show existing state dirs
```

To make the mount persist across reboots, add to `/etc/fstab`:
```
storinator:/mnt/pool/terraform-state  /mnt/terraform-state  nfs  soft,timeo=30  0  0
```

### 8. Write terraform.tfvars for both nodes

```bash
# NUC
cp terraform/nuc/terraform.tfvars.example terraform/nuc/terraform.tfvars
```

Edit `terraform/nuc/terraform.tfvars`:
```hcl
proxmox_endpoint   = "https://192.168.0.6:8006"
proxmox_api_token  = "terraform@pam!terraform=<uuid-from-step-2>"
ssh_public_key     = "<contents of ~/.ssh/id_ed25519.pub>"
tailscale_auth_key = "tskey-auth-<key-from-step-4>"
```

```bash
# Anton
cp terraform/anton/terraform.tfvars.example terraform/anton/terraform.tfvars
```

Edit `terraform/anton/terraform.tfvars`:
```hcl
proxmox_endpoint   = "https://192.168.0.5:8006"
proxmox_api_token  = "terraform@pam!terraform=<uuid-from-step-2>"
ssh_public_key     = "<contents of ~/.ssh/id_ed25519.pub>"
tailscale_auth_key = "tskey-auth-<key-from-step-4>"
```

### 9. Deploy VMs and apply base Ansible config

```bash
cd /path/to/homelab

# Deploy both nodes: runs terraform apply then ansible base.yml
./scripts/deploy.sh

# Or deploy one node at a time:
./scripts/deploy.sh nuc
./scripts/deploy.sh anton
```

The script runs `terraform apply`, waits for VMs to be SSH-reachable
(cloud-init takes ~2-3 minutes), then runs `ansible-playbook base.yml`
automatically. VMs should appear in the Tailscale admin console after apply.

To preview Terraform changes before deploying:
```bash
cd terraform/nuc && terraform plan
cd terraform/anton && terraform plan
```

---

## Phase 4 — Infisical bootstrap

### 10. Bootstrap Infisical

Wait for the nuc-infisical VM to be healthy and Docker Compose running:
```bash
ssh debian@192.168.0.21 "docker ps"
# Should show infisical and vaultwarden containers
```

Run the bootstrap script:
```bash
./scripts/infisical-bootstrap.sh
```

The script outputs:
```
workspace_id  = "..."
client_id     = "..."
client_secret = "..."
```

Save these — you add them to `terraform.tfvars` next.

### 11. Add Infisical credentials to terraform.tfvars

Add to **both** `terraform/nuc/terraform.tfvars` and `terraform/anton/terraform.tfvars`:

```hcl
infisical_workspace_id  = "<workspace_id from step 9>"
infisical_client_id     = "<client_id from step 9>"
infisical_client_secret = "<client_secret from step 9>"
```

Re-apply Terraform to pick up the updated variables:
```bash
cd terraform/nuc && terraform apply
cd ../anton && terraform apply
```

---

## Phase 5 — Vaultwarden account

### 12. Create your Vaultwarden account

1. Open `https://vault.home` in a browser (requires `.home` DNS from AdGuard — see note below)
2. Create Account with your email and a strong master password
3. Vaultwarden locks signups automatically after the first account

> **DNS note:** If AdGuard DNS isn't set up yet, access Vaultwarden directly:
> `https://192.168.0.21:8443` (or whichever port is configured in docker-compose)

Store the master password somewhere safe immediately — this is your break-glass credential.

---

## Phase 6 — Seed Infisical

### 13. Add secrets to Infisical

Log into Infisical at `https://infisical.home` (or `https://192.168.0.21:<port>`).

Add all machine-consumed secrets to the `prod` environment:

**Service API keys and inter-service tokens** (add as you set up each service):
- `RADARR_API_KEY` — will be set when Radarr first starts; add after init
- `SONARR_API_KEY` — same
- `PROWLARR_API_KEY` — same
- Any other service-to-service tokens

**Developer API keys** (add now):
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN`
- Any other keys you use in terminal workflows

To use developer keys on the operator laptop:
```bash
infisical run -- claude   # example
infisical run -- env      # inspect all injected vars
```

---

## Phase 7 — Start services

### 14. Reboot VMs to fetch secrets and start services

```bash
# Trigger a reboot so cloud-init / startup scripts fetch from Infisical
ssh debian@192.168.0.21 "sudo reboot"
ssh debian@192.168.0.13 "sudo reboot"
# ... repeat for each VM
```

After reboot, verify services are up:
```bash
ssh debian@192.168.0.21 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
ssh debian@192.168.0.13 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

All containers should show `Up`. Check logs for any startup failures:
```bash
ssh debian@192.168.0.21 "docker compose logs --tail=50"
```

---

## Phase 8 — Post-bootstrap

### 15. Run headless service init scripts

After services are up and running, initialize services that need first-boot setup:

```bash
# Jellyfin — creates admin account, configures libraries
./scripts/jellyfin-init.sh

# Servarr — links Prowlarr to Radarr and Sonarr
./scripts/servarr-init.sh

# Calibre-Web — sets admin password
./scripts/calibre-init.sh

# n8n — creates owner account
./scripts/n8n-init.sh
```

Each script is idempotent — safe to re-run.

After running each init script, add the service's admin password to Vaultwarden manually.

### 16. Back up terraform.tfvars

Store `terraform.tfvars` as an encrypted note or file attachment in Vaultwarden.
It contains the Proxmox API token, Tailscale key, and Infisical credentials —
losing it requires regenerating all of these.

---

## Done

At this point:
- All VMs are provisioned and on Tailscale
- All services are running with secrets from Infisical
- Admin passwords are in Vaultwarden
- `terraform.tfvars` is backed up in Vaultwarden
- All future infrastructure changes go through `terraform apply`

---

## Day-2 operations

**Add a new VM:**
```bash
# Edit terraform/<node>/main.tf, then:
./scripts/deploy.sh <node>
```

**Rebuild a VM from scratch:**
```bash
cd terraform/<node>
terraform destroy -target=module.<vm-name>
cd /path/to/homelab
./scripts/deploy.sh <node>
```

**Update secrets:**
Update in Infisical UI, then reboot the affected VM to pick up changes.

**Rotate Tailscale auth key:**
```bash
# Generate new key at https://login.tailscale.com/admin/settings/keys
# Update terraform.tfvars on both nodes
TAILSCALE_AUTH_KEY=tskey-auth-NEW_KEY \
  ansible-playbook ansible/tailscale.yml --ask-become-pass
```

**Apply day-2 config (security patches, Docker updates):**
```bash
ansible-playbook ansible/base.yml
```
