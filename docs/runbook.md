# Bootstrap Runbook

Step-by-step rebuild guide. Follow in order. After completing this runbook,
all infrastructure is managed via Terraform and all services are running.

Normal deploys after bootstrap are fully automated: push to `main` and the VPS
webhook handles Terraform, Ansible, and Docker Compose updates automatically.

---

## Prerequisites

Tools required on the operator laptop:

```bash
# Terraform >= 1.10 (required for S3 lockfile support)
terraform -version

# Ansible
ansible --version

# Infisical CLI >= 0.28
infisical --version

# SSH key pair (used for VM access)
ls ~/.ssh/id_ed25519.pub

# Hetzner CLI (for VPS provisioning)
hcloud version
```

Install if missing:
```bash
brew install terraform ansible infisical/tap/infisical hcloud
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

### 3. Create NFS datasets and enable MinIO on Storinator

Log into TrueNAS at `https://192.168.0.4`:

1. Storage → Create Pool (if not already done): name `pool`
2. Datasets → Add Dataset for each:
   - `pool/docker`
   - `pool/backups`
   - `pool/media`
   - `pool/photos`
   - `pool/lightroom`
3. Sharing → NFS → Add for the docker dataset:
   - Path: `/mnt/pool/docker`, Networks: `192.168.0.0/24`, `Maproot User: root`
4. Services → NFS → Start, set to start automatically
5. Apps → MinIO (or System → S3 Service depending on TrueNAS version) → Enable S3 service:
   - Create bucket: `terraform-state`
   - Create access key and secret key — save these for `terraform.tfvars`
   - Note the endpoint (typically `http://storinator:9000` over Tailscale)

MinIO replaces the old `terraform-state` NFS export. Both the VPS and operator laptop
access state via S3 over Tailscale — no NFS mount needed.

---

## Phase 2 — VPS bootstrap

### 4. Provision the VPS

From the operator laptop:

```bash
cd terraform/vps
cp terraform.tfvars.example terraform.tfvars
# Fill in: hetzner_api_token, ssh_public_key
terraform init
terraform apply
```

Note the VPS public IP from the output. State for this workspace is a local file
(`terraform/vps/terraform.tfstate`) — back it up in Vaultwarden after this step.

### 5. Bootstrap Headscale on the VPS

```bash
ansible-playbook ansible/vps.yml
```

This installs Docker, deploys Headscale via Docker Compose, and hardens the node.
Verify Headscale is running:

```bash
ssh debian@<vps-public-ip> "docker ps"
# Should show headscale container
```

### 6. Generate a Headscale pre-auth key

```bash
ssh debian@<vps-public-ip> \
  "docker exec headscale headscale preauthkeys create --reusable --expiration 90d"
```

Copy the key (`<long-hex-string>`) — you'll use it in steps 8 and 10.

---

## Phase 3 — Ansible (physical nodes)

### 7. Configure static IPs on physical nodes

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

### 8. Install Tailscale on physical nodes

```bash
cd /path/to/homelab

# Run the Tailscale playbook against all physical nodes
# (Anton, NUC, Storinator, Orange Pi)
TAILSCALE_AUTH_KEY=<headscale-preauth-key-from-step-6> \
  ansible-playbook ansible/tailscale.yml --ask-become-pass
```

This points all physical nodes at the Headscale server (`--login-server` is set in
the playbook). Verify all nodes appear in Headscale:

```bash
ssh debian@<vps-public-ip> "docker exec headscale headscale nodes list"
```

---

## Phase 4 — Terraform (first apply, from VPS)

### 9. Set up the repo on the VPS

```bash
ssh debian@<vps-public-ip>
git clone git@github.com:wsh32/homelab.git
cd homelab
```

### 10. Write terraform.tfvars on the VPS

```bash
# NUC
cp terraform/nuc/terraform.tfvars.example terraform/nuc/terraform.tfvars
```

Edit `terraform/nuc/terraform.tfvars`:
```hcl
proxmox_endpoint      = "https://192.168.0.6:8006"
proxmox_api_token     = "terraform@pam!terraform=<uuid-from-step-2>"
ssh_public_key        = "<contents of ~/.ssh/id_ed25519.pub>"
tailscale_auth_key    = "<headscale-preauth-key-from-step-6>"
headscale_server      = "https://<vps-public-ip>"
minio_access_key      = "<access-key-from-step-3>"
minio_secret_key      = "<secret-key-from-step-3>"
```

```bash
# Anton
cp terraform/anton/terraform.tfvars.example terraform/anton/terraform.tfvars
```

Edit `terraform/anton/terraform.tfvars` with the same values, changing
`proxmox_endpoint` to `https://192.168.0.5:8006`.

### 11. Deploy VMs and apply base Ansible config

Run from the VPS:

```bash
cd ~/homelab

# Deploy both nodes: runs terraform apply then ansible base.yml
./scripts/deploy.sh

# Or deploy one node at a time:
./scripts/deploy.sh nuc
./scripts/deploy.sh anton
```

The script runs `terraform apply` (state goes to MinIO on Storinator over Tailscale),
waits for VMs to be SSH-reachable (cloud-init takes ~2-3 minutes), then runs
`ansible-playbook base.yml`. VMs join the Headscale tailnet after first boot.

To preview before deploying:
```bash
cd terraform/nuc && terraform plan
cd terraform/anton && terraform plan
```

---

## Phase 5 — Infisical bootstrap

### 12. Bootstrap Infisical

Wait for the nuc-infisical VM to be healthy and Docker Compose running:
```bash
ssh debian@192.168.0.21 "docker ps"
# Should show infisical and vaultwarden containers
```

Run the bootstrap script from the VPS:
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

### 13. Add Infisical credentials to terraform.tfvars

Add to **both** `terraform/nuc/terraform.tfvars` and `terraform/anton/terraform.tfvars`:

```hcl
infisical_workspace_id  = "<workspace_id from step 12>"
infisical_client_id     = "<client_id from step 12>"
infisical_client_secret = "<client_secret from step 12>"
```

Re-apply Terraform from the VPS to pick up the updated variables:
```bash
./scripts/deploy.sh
```

---

## Phase 6 — Vaultwarden account

### 14. Create your Vaultwarden account

1. Open `https://vault.home` in a browser (requires `.home` DNS from AdGuard — see note below)
2. Create Account with your email and a strong master password
3. Vaultwarden locks signups automatically after the first account

> **DNS note:** If AdGuard DNS isn't set up yet, access Vaultwarden directly:
> `https://192.168.0.21:8443` (or whichever port is configured in docker-compose)

Store the master password somewhere safe immediately — this is your break-glass credential.

---

## Phase 7 — Seed Infisical

### 15. Add secrets to Infisical

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

**Infrastructure secrets** (add now):
- `HOMELAB_DEPLOY_KEY` — private half of the GitHub deploy key (read-only repo access).
  Used by physical devices and the VPS for `ansible-pull`.
- `WEBHOOK_SECRET` — random string used to authenticate GitHub webhooks on the VPS.

To use developer keys on the operator laptop:
```bash
infisical run -- claude   # example
infisical run -- env      # inspect all injected vars
```

---

## Phase 8 — Start services

### 16. Reboot VMs to fetch secrets and start services

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

## Phase 9 — Webhook setup

### 17. Configure GitHub webhook

1. In the repo on GitHub: Settings → Webhooks → Add webhook
   - Payload URL: `https://<vps-domain>/hooks/deploy`
   - Content type: `application/json`
   - Secret: value of `WEBHOOK_SECRET` from Infisical
   - Events: **Just the push event**
   - Active: yes

2. On the VPS, configure the `webhook` service (part of `ansible/roles/headscale`
   or a dedicated `webhook` role). It reads `WEBHOOK_SECRET` from Infisical at startup.

3. Test by pushing a non-breaking change to `main` and watching the deploy log:
   ```bash
   ssh debian@<vps> "journalctl -u webhook -f"
   ```

---

## Phase 10 — Post-bootstrap

### 18. Run headless service init scripts

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

### 19. Back up critical files

Store the following as encrypted notes or file attachments in Vaultwarden:
- `terraform/nuc/terraform.tfvars` and `terraform/anton/terraform.tfvars` — Proxmox
  API tokens, Headscale key, MinIO credentials, Infisical credentials
- `terraform/vps/terraform.tfstate` — the only state file not in MinIO
- `terraform/vps/terraform.tfvars` — Hetzner API token

---

## Done

At this point:
- All VMs are provisioned and on the Headscale tailnet
- All services are running with secrets from Infisical
- Admin passwords are in Vaultwarden
- `terraform.tfvars` and VPS state are backed up in Vaultwarden
- All future infrastructure changes are triggered by `git push` to `main`

---

## Day-2 operations

**Deploy any change:**
```bash
git push origin main
# Webhook on VPS detects what changed and runs the right commands automatically.
```

**Add a new VM:**
```bash
# Edit terraform/<node>/main.tf and network.yml, commit, push to main.
# Webhook handles the rest.
```

**Rebuild a VM from scratch:**
```bash
# SSH to VPS:
cd ~/homelab
cd terraform/<node> && terraform destroy -target=module.<vm-name>
cd ~/homelab && ./scripts/deploy.sh <node>
```

**Add a new physical device:**
```bash
# 1. Add to network.yml and ansible/inventory/hosts.yml, commit, push.
# 2. Bootstrap the device (one-time, run from operator laptop):
ssh root@<device-ip> \
  TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
  REPO_DEPLOY_KEY="$(infisical run -- printenv HOMELAB_DEPLOY_KEY)" \
  bash -s < scripts/bootstrap-physical.sh
# Device joins Headscale and starts self-updating via ansible-pull every 30 min.
```

**Update secrets:**
Update in Infisical UI, then reboot the affected VM to pick up changes.

**Rotate Headscale pre-auth key:**
```bash
# SSH to VPS:
docker exec headscale headscale preauthkeys create --reusable --expiration 90d
# Update TAILSCALE_AUTH_KEY in terraform.tfvars on the VPS, commit, push.
```

**VPS infrastructure change** (the one manual exception):
```bash
# From operator laptop:
cd terraform/vps && terraform apply
```

**Apply day-2 config manually (bypass webhook):**
```bash
# SSH to VPS:
cd ~/homelab && ansible-playbook ansible/base.yml
```
