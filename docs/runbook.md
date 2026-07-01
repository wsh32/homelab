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

## Phase 1 -- Physical setup (one-time, manual)

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

> **Geodude** is an offsite node and does not join the cluster. It is managed
> independently via its own Terraform workspace and reached via Tailscale.

### 2. Create Proxmox API tokens

Repeat on **Machamp** (`192.168.0.5:8006`), **Diglett** (`192.168.0.6:8006`),
and **Geodude** (reached via the Tailscale admin console URL or `https://geodude.corgi-census.ts.net:8006`
once enrolled in Tailscale):

1. Datacenter → Permissions → Users → Add: `terraform@pam`
2. Datacenter → Permissions → Add → User Permission: path `/`, user `terraform@pam`, role `Administrator`
3. Datacenter → Permissions → API Tokens → Add:
   - User: `terraform@pam`
   - Token ID: `terraform`
   - **Uncheck** Privilege Separation
4. Copy the token secret -- it is only shown once. Format: `terraform@pam!terraform=<uuid>`

### 3. Create NFS datasets and shares on Alakazam

Log into TrueNAS at `https://192.168.0.4`:

1. Storage → Create pools (if not already done):
   - `pool` -- HDD storage (bulk data)
   - `apps` -- SSD storage (512 GB, for latency-sensitive data)
2. Datasets → Add Dataset for each:
   - `apps/terraform` -- Terraform state files (SSD)
   - `apps/docker` -- persistent service data / Docker volumes (SSD)
   - `pool/backups`
   - `pool/media`
   - `pool/photos`
   - `pool/lightroom`
3. Sharing → NFS → Add a share for **each** dataset below.
   For every share set **Maproot User: `root`** -- this allows the deploy VM's
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

### 3a. Set up VM storage on Machamp (NVMe)

Machamp has 6 NVMe drives -- 2 on the motherboard (`nvme4n1`, `nvme5n1`) and 4 on a
PCIe expansion card. Use one motherboard NVMe (`nvme4n1`) as dedicated VM storage.

SSH to machamp as root (`ssh root@192.168.0.5`):

```bash
# Identify which drives are on the motherboard vs expansion card
lspci | grep -i nvme
ls -l /sys/block/nvme*/device/device
# Motherboard drives are on lower PCI bus addresses (e.g. 21:xx, 22:xx)

# Create LVM volume group on the chosen drive
pvcreate /dev/nvme4n1
vgcreate vmdata /dev/nvme4n1

# Create a thin pool using all available space
lvcreate -l 100%FREE -T vmdata/data

# Register as a Proxmox storage (datacenter-level, restricted to machamp)
pvesh create /storage \
  --storage vmdata \
  --type lvmthin \
  --vgname vmdata \
  --thinpool data \
  --content rootdir,images \
  --nodes machamp
```

Verify it appears in the Proxmox UI under Datacenter → Storage as `vmdata`.

### 3b. Enable Snippets storage on each Proxmox node

The bpg/proxmox Terraform provider uploads cloud-init user-data as snippet files.
The `local` datastore must have the Snippets content type enabled or Terraform will
fail when creating VMs.

Repeat on **Machamp**, **Diglett**, and **Geodude**:
1. Datacenter → Storage → `local` → Edit
2. Under **Content**, check **Snippets**
3. Click OK

### 3c. Configure Eero port forward for Headscale

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

### 4. Configure static IPs and VM bridges on physical nodes

Find the NIC bridged to `vmbr0` on Machamp and Diglett:
```bash
ssh root@192.168.0.5 ip link show   # machamp -- look for eno1 or similar
ssh root@192.168.0.6 ip link show   # diglett
```

Update `bridge_port` in `network.yml` if needed, then:
```bash
ansible-playbook ansible/proxmox-bridge.yml
```

This also creates the internal `vmbr1` bridge on each node (the VM bridge used for
Tailscale subnet routing). Verify it came up:
```bash
ssh root@192.168.0.6 ip addr show vmbr1   # diglett -- should show 10.0.1.1/24
ssh root@192.168.0.5 ip addr show vmbr1   # machamp -- should show 10.0.2.1/24
```

For Alakazam: Network → Interfaces in TrueNAS UI → set static IP (`192.168.0.4`).

### 4a. Physical setup for Geodude (offsite node)

Geodude is at an offsite location and is not on the local LAN. After initial OS install:

1. Set a static LAN IP on geodude (update `ip` under `nodes.geodude` in `network.yml` to match).
2. Set the hostname to `geodude`:
   ```bash
   hostnamectl set-hostname geodude
   ```
3. Manually join geodude to the Tailscale hosted tailnet so it becomes reachable
   via MagicDNS before any Ansible runs:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   tailscale up --hostname=geodude --ssh
   # Approve the node in the Tailscale admin console
   ```
4. After Tailscale is running, verify the deploy VM can reach geodude:
   ```bash
   # From alakazam-deploy (after tailscale2 is set up in step 7):
   ssh root@geodude
   ```
5. Create the Proxmox API token on geodude (step 2 above).
6. Run the network playbook for geodude:
   ```bash
   ansible-playbook ansible/proxmox-bridge.yml --limit geodude
   # geodude is reached via SSH ProxyCommand through tailscale2 automatically
   ```
   This creates `vmbr1` on geodude (10.0.3.1/24).

---

## Phase 2 -- Bootstrap the deploy VM (operator laptop)

### 5. Write terraform.tfvars

```bash
cp terraform/diglett/terraform.tfvars.example terraform/diglett/terraform.tfvars
cp terraform/machamp/terraform.tfvars.example terraform/machamp/terraform.tfvars
cp terraform/geodude/terraform.tfvars.example terraform/geodude/terraform.tfvars
```

Fill in:
```hcl
# Proxmox -- Diglett
proxmox_endpoint  = "https://192.168.0.6:8006"
proxmox_api_token = "terraform@pam!terraform=<uuid-from-step-2>"

# Proxmox -- Machamp (used by terraform/machamp/)
# proxmox_endpoint  = "https://192.168.0.5:8006"
# proxmox_api_token = "terraform@pam!terraform=<uuid-from-step-2>"

# Proxmox -- Geodude (used by terraform/geodude/)
# proxmox_endpoint  = "https://geodude:8006"
# proxmox_api_token = "terraform@pam!terraform=<uuid-from-step-2>"

# Shared
ssh_public_key   = "<contents of ~/.ssh/id_ed25519.pub>"

# Cloudflare (for Headscale tunnel + DNS)
cloudflare_api_token = "<cloudflare-api-token>"

# headscale_preauth_key = ""  # filled automatically by bootstrap-headscale.yml
```

### 6. Create the deploy VM in TrueNAS

`alakazam-deploy` is an Ubuntu 24.04 KVM VM managed by TrueNAS SCALE -- not Terraform.
Create it manually:

1. Log into TrueNAS at `https://192.168.0.4`
2. Virtualization → Add → Linux VM:
   - Name: `alakazam-deploy`
   - CPU: 1 core, Memory: 1 GiB, Disk: 20 GiB
   - ISO: Ubuntu Server 24.04 minimal
   - Network: bridge to the LAN interface
3. Complete the Ubuntu installer. Set:
   - Username: `ubuntu`
   - Static IP: `192.168.0.7/24`, gateway `192.168.0.1`, DNS `8.8.8.8`
   - Install OpenSSH server, import your SSH public key
4. After first boot, verify SSH access: `ssh ubuntu@192.168.0.7`

### 7. Bootstrap the deploy VM

SSH into the deploy VM (`ssh ubuntu@192.168.0.7`) and run the following:

```bash
# Allow passwordless sudo so Ansible become tasks run non-interactively
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd
sudo chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

# Install prerequisites
sudo apt-get update -q
sudo apt-get install -y git python3 python3-pip pipx

# Install Ansible
pipx install --include-deps ansible
export PATH="$HOME/.local/bin:$PATH"

# Clone the repo
git clone https://github.com/wsh32/homelab.git ~/homelab

# Self-configure via Ansible (base hardening + deploy tooling)
cd ~/homelab/ansible
ansible-playbook deploy-vm.yml --limit alakazam-deploy --connection=local
```

The deploy role installs Terraform, Infisical, Ansible, Bitwarden CLI, and sets up
two Tailscale connections:

- **tailscaled** (system service): primary Headscale tailnet for reaching VMs
- **tailscale2** (second instance, userspace): hosted Tailscale tailnet for reaching
  physical nodes (diglett, machamp, geodude)

Enroll in Headscale (the hosted tailnet enrollment is handled automatically by the deploy role):

```bash
# Join Headscale (primary tailnet -- VMs and personal devices)
sudo tailscale up \
  --authkey=<headscale-preauth-key> \
  --hostname=alakazam-deploy \
  --accept-routes=false
```

The Headscale pre-auth key comes from step 11 below (or from an existing headscale instance).

The deploy role automatically enrolls `tailscale2` (the hosted tailnet instance) via the
Tailscale API using `tailscale_api_token` from `ansible/secrets.yml`.

After the deploy role runs, the deploy VM can SSH to physical nodes via:
```bash
ssh root@geodude    # resolved via SSH config ProxyCommand → tailscale2 HTTP CONNECT proxy
ssh root@diglett    # same
```

Then copy `terraform.tfvars` to the deploy VM:

```bash
scp terraform/diglett/terraform.tfvars ubuntu@192.168.0.7:~/homelab/terraform/diglett/
scp terraform/machamp/terraform.tfvars ubuntu@192.168.0.7:~/homelab/terraform/machamp/
scp terraform/geodude/terraform.tfvars ubuntu@192.168.0.7:~/homelab/terraform/geodude/
```

### 7a. Mount the Terraform state NFS share on the deploy VM

SSH to the deploy VM and run:

```bash
# Install NFS client (not present on Ubuntu minimal by default)
sudo apt-get install -y nfs-common

# Create mount point
sudo mkdir -p /mnt/terraform-state

# Mount (verify alakazam is reachable first)
sudo mount -t nfs 192.168.0.4:/mnt/apps/terraform /mnt/terraform-state

# Create per-node state directories and set ownership
sudo mkdir -p /mnt/terraform-state/machamp \
              /mnt/terraform-state/diglett \
              /mnt/terraform-state/geodude
sudo chown ubuntu:ubuntu /mnt/terraform-state/machamp \
                         /mnt/terraform-state/diglett \
                         /mnt/terraform-state/geodude
```

Persist the mount across reboots by adding to `/etc/fstab`:
```
192.168.0.4:/mnt/apps/terraform /mnt/terraform-state nfs soft,timeo=30,nfsvers=4 0 0
```

### 7b. Authorize the deploy VM SSH key on both Proxmox nodes and install the CA cert

The bpg/proxmox Terraform provider uses SSH (in addition to the API) to upload
cloud-init snippets. The deploy VM's key must be in root's `authorized_keys` on
both nodes, and the Proxmox CA cert must be installed so Terraform can verify TLS.

```bash
# Authorize SSH key on LAN-reachable Proxmox nodes
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@machamp.local
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@diglett.local

# Fetch and install the Proxmox cluster CA cert (both nodes share the same CA)
bash ~/homelab/scripts/install-proxmox-ca.sh machamp.local
```

For geodude (reached via Tailscale):
```bash
# SSH key is already authorized if geodude was enrolled with --ssh in step 4a
# Install the geodude CA cert
bash ~/homelab/scripts/install-proxmox-ca.sh geodude
```

Verify TLS works before running Terraform:
```bash
curl https://192.168.0.5:8006    # machamp -- should connect without cert errors
curl https://192.168.0.6:8006    # diglett
HTTPS_PROXY=http://localhost:1055 curl https://geodude:8006  # geodude via tailscale2
```

---

## Phase 3 -- Configure physical nodes (from the deploy VM)

### 8. Configure Proxmox nodes

```bash
ansible-playbook ansible/proxmox.yml
```

This configures Machamp and Diglett: CPU governor, power tuning, and PCI hardware mappings
(e.g. `quadro-p2200` on machamp). PCI mappings are defined under `pci_mappings` in
`network.yml` and created idempotently -- safe to re-run.

The Terraform token is also granted `PVEMappingUser` permission on each mapping so
`terraform apply` can attach PCI devices without requiring root.

### 9. Enroll physical nodes in the hosted Tailscale tailnet

```bash
# Create ansible/secrets.yml from the example and fill in:
#   tailscale_tailnet: <your tailnet name, e.g. "corgi-census.ts.net">
#   tailscale_api_token: <API access token from Tailscale admin → Settings → Keys>
cp ansible/secrets.yml.example ansible/secrets.yml
$EDITOR ansible/secrets.yml

ansible-playbook ansible/proxmox.yml
```

This:
1. Pushes `services/tailscale/acl.hujson` to the Tailscale API
2. Installs tailscale on each node in the `tailscale_hosted` inventory group
3. Enrolls new nodes with a short-lived auth key (tag:infra, subnet routes auto-approved)
4. Applies settings idempotently on already-enrolled nodes

For geodude specifically, it was manually joined in step 4a -- this playbook will
update its settings (advertise routes, apply tags) without re-enrolling.

Subnet routes are auto-approved via the ACL `autoApprovers` block -- no manual
approval needed in the Tailscale admin console.

---

## Phase 4 -- Full deployment (from the deploy VM)

SSH to the deploy VM:
```bash
ssh ubuntu@192.168.0.7
cd ~/homelab
```

### 10. Provision the DNS VM

Ensure the Eero port forward (step 3c) is in place before this step -- Headscale will attempt
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

### 11. Generate Headscale pre-auth key

```bash
ansible-playbook ansible/bootstrap-headscale.yml
```

This waits for Headscale to be healthy, generates a reusable pre-auth key, and writes
it to `terraform.tfvars` automatically.

### 12. Deploy all remaining VMs

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

### 12a. Deploy geodude VMs

Geodude Terraform is run through the tailscale2 HTTP CONNECT proxy:

```bash
cd ~/homelab/terraform/geodude
HTTPS_PROXY=http://localhost:1055 terraform init
HTTPS_PROXY=http://localhost:1055 terraform plan
HTTPS_PROXY=http://localhost:1055 terraform apply
```

SSH to geodude VMs is also proxied automatically via `~/.ssh/config` (configured by
the deploy role). Once the VMs are up:

```bash
ansible-playbook ansible/base.yml --limit geodude_vms
```

### 13. Bootstrap Infisical

```bash
ansible-playbook ansible/bootstrap-infisical.yml
```

This:
- Waits for the Infisical VM to be healthy
- Runs `infisical bootstrap` to create admin user, org, workspace
- Creates a scoped machine identity for each VM that needs secrets
- Writes `/etc/infisical.env` (root-owned, mode 0600) on each VM

### 14. Bring up all services

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

## Phase 5 -- Post-bootstrap

### 15. TLS -- trust the step-ca root CA

step-ca is initialized by the `site.yml` Ansible role. Copy the root CA cert to your
operator laptop and trust it:

```bash
scp ubuntu@192.168.0.32:/tmp/homelab-root-ca.crt ~/homelab-root-ca.crt

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/homelab-root-ca.crt

# Linux (Ubuntu)
sudo cp ~/homelab-root-ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates
```

Repeat on every personal device that will use `*.wsh` services.

### 16. Verify DNS resolution

From a device on the LAN:
```bash
dig jellyfin.home @192.168.0.2   # should return 192.168.0.32
```

From a device on Tailscale:
```bash
dig jellyfin.wsh                  # should return infra VM Tailscale IP
curl -k https://jellyfin.wsh      # should reach Jellyfin
```

Check AdGuard DNS rewrites are active at `http://diglett-dns.home` → Filters → DNS rewrites:
- `*.wsh` → CNAME `machamp-infra.ts.home`
- `*.home` → A `192.168.0.32`

### 17. Add external API keys to Infisical

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

### 18. Back up terraform.tfvars

Store all `terraform.tfvars` files as encrypted file attachments in Vaultwarden. This is the
break-glass credential set -- without it you cannot reprovision from scratch.

---

## Done

At this point:
- All VMs are provisioned and on the Headscale tailnet
- Physical nodes (diglett, machamp, geodude) are on the hosted Tailscale tailnet,
  advertising their VM bridge subnets
- All services are running with secrets from Infisical
- Admin passwords are in Vaultwarden
- `terraform.tfvars` is backed up in Vaultwarden
- All future infrastructure changes are applied manually from the deploy VM

---

## GPU passthrough (Quadro P2200 → machamp-media)

The Proxmox PCI mapping (`quadro-p2200`) is created automatically by `ansible/proxmox.yml`
(Phase 3). After `terraform apply` provisions machamp-media with the GPU attached:

### Install NVIDIA drivers

```bash
ansible-playbook ansible/gpu.yml
```

The role installs `nvidia-driver-550-server`, adds the NVIDIA container toolkit, merges
the nvidia runtime into Docker's `daemon.json`, and reboots the VM if the driver was
newly installed.

### Verify

```bash
ssh ubuntu@192.168.0.30 nvidia-smi
# Expected: Quadro P2200 listed, driver version ~550.x
```

Jellyfin's `encoding.xml` is already bind-mounted with NVENC enabled. Check
Jellyfin → Dashboard → Playback -- hardware acceleration should show NVENC/NVDEC.

---

## Day-2 operations

**Deploy a change:**
```bash
ssh ubuntu@192.168.0.7
cd ~/homelab && git pull
./scripts/deploy.sh           # terraform + ansible for all nodes
./scripts/deploy-services.sh  # docker compose only, no terraform
```

**Deploy a change to geodude:**
```bash
ssh ubuntu@192.168.0.7
cd ~/homelab && git pull
cd terraform/geodude
HTTPS_PROXY=http://localhost:1055 terraform apply
cd ~/homelab
ansible-playbook ansible/base.yml --limit geodude_vms
```

**Add a new VM:**
1. Add a `module "<name>"` block in `terraform/<node>/main.tf`
2. Add IP and VM ID to `network.yml` under `nodes.<node>.vms` (inventory updates automatically)
3. From deploy VM: `./scripts/deploy.sh <node>`
   For geodude VMs: `HTTPS_PROXY=http://localhost:1055 terraform apply` then `ansible-playbook ansible/base.yml --limit geodude_vms`

**Rebuild a VM from scratch:**
```bash
ssh ubuntu@192.168.0.7
cd ~/homelab/terraform/<node>
terraform destroy -target=module.<vm-name>
cd ~/homelab && ./scripts/deploy.sh <node>
```

**Add a new physical device:**
1. Add to `network.yml` under the appropriate location's `nodes` with the correct `type`
2. Bootstrap the device (one SSH session):
```bash
ssh root@<device-ip> \
  TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
  bash -s < scripts/bootstrap-physical.sh
```
3. From deploy VM: `ansible-playbook ansible/proxmox.yml --limit <hostname>`

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

**Check tailscale2 status (hosted tailnet on deploy VM):**
```bash
tailscale --socket=/var/run/tailscale2.sock status
tailscale --socket=/var/run/tailscale2.sock ping geodude
```

**Run Ansible only (no Terraform):**
```bash
ssh ubuntu@192.168.0.7
cd ~/homelab && ansible-playbook ansible/base.yml
```
