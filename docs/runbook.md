# Bootstrap Runbook

Step-by-step rebuild guide. Follow in order. After completing this runbook,
all infrastructure is managed via Terraform and all services are running.

Normal deploys after bootstrap are manual: SSH to the deploy VM and run
`./scripts/deploy.sh`.

---

## Prerequisites

Tools required on the operator laptop:

```bash
# Terraform >= 1.10 (required for S3 lockfile support)
terraform -version

# Ansible
ansible --version

# Bitwarden CLI (for Vaultwarden account creation)
bw --version

# SSH key pair (used for VM access)
ls ~/.ssh/id_ed25519.pub
```

Install if missing:
```bash
brew install terraform ansible bitwarden-cli
ssh-keygen -t ed25519  # if no key exists
```

---

## Phase 1 — Physical setup (one-time, manual)

### 1. Form the Proxmox cluster

On Diglett (primary node):
1. Log into the Proxmox web UI at `https://192.168.0.6:8006`
2. Datacenter → Cluster → Create Cluster → name it `homelab`
3. Copy the join information

On Machamp:
1. Log into the Proxmox web UI at `https://192.168.0.5:8006`
2. Datacenter → Cluster → Join Cluster → paste join information

Verify: both nodes appear under Datacenter in either UI.

**Quorum recovery** (if a node is offline and cluster is stuck):
```bash
# Run on the surviving node
pvecm expected 1
```

### 2. Create Proxmox API tokens

Repeat on **both** Machamp (`192.168.0.5:8006`) and Diglett (`192.168.0.6:8006`):

1. Datacenter → Permissions → Users → Add: `terraform@pam`
2. Datacenter → Permissions → Add → User Permission: path `/`, user `terraform@pam`, role `Administrator`
3. Datacenter → Permissions → API Tokens → Add:
   - User: `terraform@pam`
   - Token ID: `terraform`
   - **Uncheck** Privilege Separation
4. Copy the token secret — it is only shown once. Format: `terraform@pam!terraform=<uuid>`

### 3. Create NFS datasets and shares on Alakazam

Log into TrueNAS at `https://192.168.0.4`:

1. Storage → Create pools (if not already done):
   - `pool` — HDD storage (bulk data)
   - `apps` — SSD storage (512 GB, for latency-sensitive data)
2. Datasets → Add Dataset for each:
   - `apps/terraform` — Terraform state files (SSD)
   - `apps/docker` — persistent service data / Docker volumes (SSD)
   - `pool/backups`
   - `pool/media`
   - `pool/photos`
   - `pool/lightroom`
3. Sharing → NFS → Add a share for **each** dataset below.
   For every share set **Maproot User: `root`** — this allows the deploy VM's
   `ubuntu` user to create directories and set permissions via `sudo`.
   Without this, NFS root-squash maps `sudo` to `nobody` and writes fail.

   | Dataset path          | Allowed networks  |
   |-----------------------|-------------------|
   | `/mnt/apps/terraform` | `192.168.0.0/24`  |
   | `/mnt/apps/docker`    | `192.168.0.0/24`  |

4. Services → NFS → Start, set to start automatically.
5. After adding or changing any share (e.g. adding an IP), reload exports from
   the TrueNAS shell (System → Shell):
   ```bash
   exportfs -ra
   ```
   Changes to allowed hosts in the TrueNAS UI do **not** take effect until
   exports are reloaded.

### 3a. Enable Snippets storage on each Proxmox node

The bpg/proxmox Terraform provider uploads cloud-init user-data as snippet files.
The `local` datastore must have the Snippets content type enabled or Terraform will
fail when creating VMs.

Repeat on **both** Machamp and Diglett:
1. Datacenter → Storage → `local` → Edit
2. Under **Content**, check **Snippets**
3. Click OK

### 3b. Configure Eero port forward for Headscale

Headscale listens on port 443 and must be reachable from the internet for remote device enrollment.
Configure a port forward on the Eero **before** running Terraform (Headscale will attempt ACME cert
issuance on first start, which requires the port to be reachable):

1. Open the Eero app
2. Settings → Network Settings → Advanced Settings → Port Forwarding
3. Add a rule:
   - Name: `headscale`
   - Protocol: TCP
   - External port: 443
   - Internal IP: `192.168.0.2`
   - Internal port: 443

This is the only port exposed through the router. The Eero stays closed for everything else.

### 4. Configure static IPs on physical nodes

Find the NIC bridged to `vmbr0` on Machamp and Diglett:
```bash
ssh root@192.168.0.5 ip link show   # machamp — look for eno1 or similar
ssh root@192.168.0.6 ip link show   # diglett
```

Update `bridge_port` in `network.yml` if needed, then:
```bash
ansible-playbook ansible/network.yml
```

For Alakazam and Ditto: Network → Interfaces in TrueNAS UI → set static IPs
(`192.168.0.4` and `192.168.0.8`).

---

## Phase 2 — Bootstrap the deploy VM (operator laptop)

### 5. Write terraform.tfvars

```bash
cp terraform/diglett/terraform.tfvars.example terraform/diglett/terraform.tfvars
cp terraform/machamp/terraform.tfvars.example terraform/machamp/terraform.tfvars
```

Fill in:
```hcl
# Proxmox — Diglett
proxmox_endpoint  = "https://192.168.0.6:8006"
proxmox_api_token = "terraform@pam!terraform=<uuid-from-step-2>"

# Proxmox — Machamp (used by terraform/machamp/)
# proxmox_endpoint  = "https://192.168.0.5:8006"
# proxmox_api_token = "terraform@pam!terraform=<uuid-from-step-2>"

# Shared
ssh_public_key   = "<contents of ~/.ssh/id_ed25519.pub>"

# Cloudflare (for Headscale tunnel + DNS)
cloudflare_api_token = "<cloudflare-api-token>"

# headscale_preauth_key = ""  # filled automatically by bootstrap-headscale.yml
```

### 6. Create the deploy VM in TrueNAS

`alakazam-deploy` is an Ubuntu 24.04 KVM VM managed by TrueNAS SCALE — not Terraform.
Create it manually:

1. Log into TrueNAS at `https://192.168.0.4`
2. Virtualization → Add → Linux VM:
   - Name: `alakazam-deploy`
   - CPU: 1 core, Memory: 1 GiB, Disk: 20 GiB
   - ISO: Ubuntu Server 24.04 minimal
   - Network: bridge to the LAN interface
3. Complete the Ubuntu installer. Set:
   - Username: `ubuntu`
   - Static IP: `192.168.0.20/24`, gateway `192.168.0.1`, DNS `8.8.8.8`
   - Install OpenSSH server, import your SSH public key
4. After first boot, verify SSH access: `ssh ubuntu@192.168.0.20`

### 7. Bootstrap the deploy VM

From the operator laptop:

```bash
ssh ubuntu@192.168.0.20 \
  TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
  bash -s < scripts/bootstrap-alakazam-deploy.sh
```

This installs Ansible, clones the repo, configures passwordless sudo, then runs
`ansible-playbook deploy-vm.yml --connection=local` to apply base hardening and
deploy tooling (Terraform, Infisical CLI, Tailscale). You will be prompted for
the `ubuntu` sudo password once at the start.

If the Ansible step fails and you need to re-run it manually:

```bash
ssh ubuntu@alakazam-deploy
cd ~/homelab/ansible
ansible-playbook deploy-vm.yml --limit alakazam-deploy --connection=local --ask-become-pass
```

Then copy `terraform.tfvars` to the deploy VM:

```bash
scp terraform/diglett/terraform.tfvars ubuntu@192.168.0.20:~/homelab/terraform/diglett/
scp terraform/machamp/terraform.tfvars ubuntu@192.168.0.20:~/homelab/terraform/machamp/
```

### 7a. Mount the Terraform state NFS share on the deploy VM

SSH to the deploy VM and run:

```bash
# Install NFS client (not present on Ubuntu minimal by default)
sudo apt-get install -y nfs-common

# Create mount point
sudo mkdir -p /mnt/terraform-state

# Mount (verify alakazam is reachable first)
sudo mount -t nfs alakazam.local:/mnt/apps/terraform /mnt/terraform-state

# Create per-node state directories and set ownership
sudo mkdir -p /mnt/terraform-state/machamp /mnt/terraform-state/diglett
sudo chown ubuntu:ubuntu /mnt/terraform-state/machamp /mnt/terraform-state/diglett
```

Persist the mount across reboots by adding to `/etc/fstab`:
```
alakazam.local:/mnt/apps/terraform /mnt/terraform-state nfs soft,timeo=30,nfsvers=4 0 0
```

To avoid needing to re-run `ssh-agent` every session, add to `~/.bashrc`:
```bash
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval $(ssh-agent -s)
  ssh-add ~/.ssh/id_ed25519
fi
```

All remaining steps run from the deploy VM.

### 7b. Authorize the deploy VM SSH key on both Proxmox nodes and install the CA cert

The bpg/proxmox Terraform provider uses SSH (in addition to the API) to upload
cloud-init snippets. The deploy VM's key must be in root's `authorized_keys` on
both nodes, and the Proxmox CA cert must be installed so Terraform can verify TLS.

```bash
# Authorize SSH key on both Proxmox nodes
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@machamp.local
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@diglett.local

# Fetch and install the Proxmox cluster CA cert (both nodes share the same CA)
bash ~/homelab/scripts/install-proxmox-ca.sh machamp.local
```

Verify TLS works before running Terraform:
```bash
curl https://192.168.0.5:8006  # should connect without certificate errors
```

---

## Phase 3 — Full deployment (from the deploy VM)

SSH to the deploy VM:
```bash
ssh ubuntu@192.168.0.20
cd ~/homelab
```

### 8. Provision the DNS VM

Ensure the Eero port forward (step 3b) is in place before this step — Headscale will attempt
Let's Encrypt cert issuance on first start and needs port 443 reachable from the internet.

```bash
cd terraform/diglett
terraform apply -target=module.dns
```

Terraform creates the Cloudflare DNS A record and writes `/etc/headscale.env` (Cloudflare API
token + DDNS config) to the DNS VM via cloud-init. AdGuard, Headscale, and cloudflare-ddns
all start on first boot. Headscale obtains a Let's Encrypt cert via DNS-01 on first start
(no port 80 required).

Verify:
```bash
ssh ubuntu@192.168.0.2 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
# Should show adguardhome, headscale, cloudflare-ddns all Up

# Confirm TLS cert issued and Headscale is reachable
curl https://headscale.<your-domain>/health
```

### 9. Generate Headscale pre-auth key

```bash
ansible-playbook ansible/bootstrap-headscale.yml
```

This waits for Headscale to be healthy, generates a reusable pre-auth key, and writes
it to `terraform.tfvars` automatically.

### 10. Deploy all remaining VMs

```bash
./scripts/deploy.sh
# Or node by node:
./scripts/deploy.sh diglett
./scripts/deploy.sh machamp
```

VMs provision, cloud-init handles Docker install and NFS mounts. Tailscale auth runs
at first boot using the pre-auth key. Wait ~2-3 minutes for cloud-init to complete,
then verify:

```bash
ansible-playbook ansible/base.yml   # should complete with no failures
```

### 11. Bootstrap Infisical

```bash
ansible-playbook ansible/bootstrap-infisical.yml
```

This:
- Waits for the Infisical VM to be healthy
- Runs `infisical bootstrap` to create admin user, org, workspace
- Creates a scoped machine identity for each VM that needs secrets
- Writes `/etc/infisical.env` (root-owned, mode 0600) on each VM

### 12. Bring up all services

```bash
ansible-playbook ansible/site.yml
```

Each service role:
1. Generates the service's API keys/passwords
2. Seeds them to Infisical (`infisical secrets set ...`)
3. Writes pre-seeded config files
4. Starts the container
5. Runs any headless init (Jellyfin wizard, Servarr linking, etc.)
6. Stores the admin password in Vaultwarden

Vaultwarden account creation is attempted automatically via `bw register`. If the
Bitwarden CLI doesn't support registration against Vaultwarden, the playbook will
pause with instructions for the one manual browser step.

---

## Phase 4 — Post-bootstrap

### 13. TLS — trust the step-ca root CA

step-ca is initialized by the `site.yml` Ansible role. Copy the root CA cert to your
operator laptop and trust it:

```bash
scp ubuntu@192.168.0.31:/tmp/homelab-root-ca.crt ~/homelab-root-ca.crt

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/homelab-root-ca.crt

# Linux (Ubuntu)
sudo cp ~/homelab-root-ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates
```

Repeat on every personal device that will use `*.wsh` services.

### 14. Verify DNS resolution

From a device on the LAN:
```bash
dig jellyfin.home @192.168.0.2   # should return 192.168.0.31
```

From a device on Tailscale:
```bash
dig jellyfin.wsh                  # should return services VM Tailscale IP
curl -k https://jellyfin.wsh      # should reach Jellyfin
```

Check AdGuard DNS rewrites are active at `http://dns.home` → Filters → DNS rewrites:
- `*.wsh` → CNAME `machamp-services.ts.home`
- `*.home` → A `192.168.0.31`

### 15. Add external API keys to Infisical

Log into Infisical at `http://infisical.home` and add secrets that cannot be generated
locally:

```
ANTHROPIC_API_KEY
OPENAI_API_KEY
GITHUB_TOKEN
# any other external keys used in terminal workflows
```

To use them on the operator laptop:
```bash
infisical run -- claude
infisical run -- env   # inspect all injected vars
```

### 16. Back up terraform.tfvars

Store `terraform.tfvars` as an encrypted file attachment in Vaultwarden. This is the
break-glass credential set — without it you cannot reprovision from scratch.

---

## Done

At this point:
- All VMs are provisioned and on the Headscale tailnet
- All services are running with secrets from Infisical
- Admin passwords are in Vaultwarden
- `terraform.tfvars` is backed up in Vaultwarden
- All future infrastructure changes are applied manually from the deploy VM

---

## Day-2 operations

**Deploy a change:**
```bash
ssh ubuntu@192.168.0.20
cd ~/homelab && git pull
./scripts/deploy.sh           # terraform + ansible for all nodes
./scripts/deploy-services.sh  # docker compose only, no terraform
```

**Add a new VM:**
1. Add a `module "<name>"` block in `terraform/<node>/main.tf`
2. Add IP and VM ID to `network.yml` under `nodes.<node>.vms` (inventory updates automatically)
3. From deploy VM: `./scripts/deploy.sh <node>`

**Rebuild a VM from scratch:**
```bash
ssh ubuntu@192.168.0.20
cd ~/homelab/terraform/<node>
terraform destroy -target=module.<vm-name>
cd ~/homelab && ./scripts/deploy.sh <node>
```

**Add a new physical device:**
1. Add to `network.yml` under `physical` with the correct `type` (inventory updates automatically)
2. Bootstrap the device (one SSH session):
```bash
ssh root@<device-ip> \
  TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
  bash -s < scripts/bootstrap-physical.sh
```
3. From deploy VM: `ansible-playbook ansible/physical.yml --limit <hostname>`

**Update secrets:**
Update in Infisical UI, then on the affected VM:
```bash
ssh ubuntu@<vm-ip> "sudo systemctl restart infisical-export && docker compose up -d"
```

**Rotate Headscale pre-auth key:**
```bash
ssh ubuntu@192.168.0.2 \
  "docker exec headscale headscale preauthkeys create --reusable --expiration 365d"
# Update headscale_preauth_key in terraform.tfvars on the deploy VM
```

**Run Ansible only (no Terraform):**
```bash
ssh ubuntu@192.168.0.20
cd ~/homelab && ansible-playbook ansible/base.yml
```
