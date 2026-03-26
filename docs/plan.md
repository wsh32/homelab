# Homelab Plan

## 1. Purpose

This document defines the target architecture and rebuild plan for my homelab.

Goals:

- Rebuild infrastructure around **Proxmox + Terraform**
- Ensure all compute infrastructure is **reproducible from Git**
- Minimize manual configuration and UI-based changes
- Separate **compute**, **storage**, and **infrastructure services**
- Maintain **TrueNAS systems as stable data planes**
- Support safe iteration and easy disaster recovery

---

# 2. Guiding Principles

Infrastructure philosophy:

1. **Infrastructure as Code**
   - All VMs defined in Terraform
   - No permanent UI configuration

2. **Immutable / Rebuildable Services**
   - VMs can be destroyed and recreated
   - Services defined via Docker / config management

3. **Separation of Planes**
   - Compute
   - Infrastructure services
   - Storage

4. **Stateful vs Stateless**
   - Stateful services live on NAS
   - Compute nodes remain disposable

5. **Git as Source of Truth**

Repo will contain:

- Terraform
- VM templates
- Service definitions
- Documentation


---

# 3. Network Design

## Local Network

Router:

192.168.0.1 (Eero)

DHCP:

192.168.0.100 - 192.168.0.254 (Eero managed)

Reserved IPs:

Physical nodes get DHCP reservations in the Eero app. VMs get static IPs configured via cloud-init (outside the DHCP range).

| Device | Hostname | IP | Notes |
|------|------|------|------|
| nuc-dns VM | dns | 192.168.0.2 | Static (Terraform) - primary DNS (AdGuard) |
| (future) | dns2 | 192.168.0.3 | Reserved for backup DNS VM |
| Storinator | storinator | 192.168.0.4 | Eero DHCP reservation |
| Anton | anton | 192.168.0.5 | Eero DHCP reservation |
| NUC | nuc | 192.168.0.6 | Eero DHCP reservation |
| Orange Pi | orangepi | 192.168.0.7 | Eero DHCP reservation |
| anton-ollama VM | anton-ollama | 192.168.0.10 | Static (Terraform) |
| anton-services VM | anton-services | 192.168.0.11 | Static (Terraform) |
| anton-openclaw VM | anton-openclaw | 192.168.0.12 | Static (Terraform) |
| anton-ubuntu VM | anton-ubuntu | 192.168.0.13 | Static (Terraform) |
| nuc-infisical VM | nuc-infisical | 192.168.0.21 | Static (Terraform) - Infisical secrets manager |
| nuc-haos VM | nuc-haos | 192.168.0.22 | Static (Terraform) - Home Assistant OS |

Note: Gringotts is offsite and not on the local network.


---

## Remote Access

Access will be provided via:

- Tailscale

Nodes joining Tailscale:

- All physical nodes (Anton, NUC, Storinator, Gringotts, Orange Pi)
- All VMs (provisioned automatically via Terraform cloud-init)

ACL strategy:

All nodes and VMs can communicate freely with each other. No segmentation for now.


---

# 4. Storage Architecture

Primary NAS: **Storinator**

Storinator is NAS-only. The only additional software installed is Tailscale. No apps, no Docker, no services beyond TrueNAS itself.


Key datasets:

| Dataset | Purpose |
|-------|-------|
| backups | VM backups |
| media | media storage |
| docker | persistent volumes |
| terraform-state | terraform state |
| photos | photo archive |
| lightroom | photo raws, lightroom library backup |

Replication:

Storinator -> Gringotts

Frequency (per-dataset):

| Dataset | Frequency | Rationale |
|---------|-----------|-----------|
| docker | Daily | Service secrets, Vaultwarden, app state |
| terraform-state | Daily | Infrastructure state |
| backups | Daily | VM backups (HAOS especially) |
| media | Weekly | Large, less critical |
| photos | Weekly | Large, less critical |
| lightroom | Weekly | Large, less critical |


---

# 5. Proxmox Architecture

## Cluster Layout

| Node | Role | Status |
|-----|-----|-----|
| Anton | Compute (GPU workloads, permanent Ollama host) | Active |
| NUC | Always-on infrastructure | Active |
| Services node (tbd) | Services host (takes over from Anton when built) | Planned |

Cluster decision:

[ ] Single node per host
[x] Full Proxmox cluster

Notes:

Clustering is for single-pane management only. No HA or live migration.


---

## Bootstrap Phase

### One-time manual steps (Proxmox UI)

1. **Proxmox cluster** - join Anton and NUC into a single Proxmox cluster
2. **Proxmox API token** - create a Terraform service account and API token on
   each Proxmox node

### One-time manual steps (Storinator TrueNAS UI)

3. **NFS datasets** - create the following datasets and enable NFS exports:
   - `terraform-state` - Terraform state file
   - `docker` - persistent Docker volumes for all services

### One-time manual steps (external services)

4. **Tailscale API key** - generate in the Tailscale dashboard

### Ansible (automated)

5. **Tailscale on physical nodes** - run `ansible-playbook ansible/tailscale.yml`
   to install and auth Tailscale on Anton, NUC, Storinator, Gringotts, Orange Pi

### Terraform (automated)

6. **Write `terraform.tfvars`** - populate with Proxmox API token and Tailscale
   API key; back up in Vaultwarden
7. **Mount Storinator NFS** - mount `terraform-state` dataset on the machine
   running Terraform (laptop or workstation)
8. **`terraform apply` (pass 1)** - provisions all VMs; cloud-init handles
   Tailscale auth, Docker install, and Docker Compose startup on each VM.
   Infisical provider is not yet configured — this pass only provisions compute.
9. **Bootstrap Infisical** - run `scripts/infisical-bootstrap.sh` against the
   newly provisioned Infisical VM. This script runs `infisical bootstrap` to
   create the admin user, organization, workspace, and a machine identity.
   The script outputs `workspace_id`, `client_id`, and `client_secret`.
10. **Update `terraform.tfvars`** - add the Infisical credentials from step 9.
11. **`terraform apply` (pass 2)** - with Infisical provider now configured,
    seeds all service runtime secrets into Infisical. Services restart and
    pull secrets via Infisical env injection.

After step 11, all further infrastructure changes are managed via Terraform.

---

## VM Resource Budget

### NUC (16GB RAM total, i3-8109U 4c/4t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 2GB (reserved) | - | OS overhead |
| DNS VM | 2GB | 2 | AdGuard + Tailscale exit node |
| Home Assistant VM | 4GB | 2 | HAOS |
| Infisical VM | 6GB | 2 | Secrets manager + Vaultwarden; data on Storinator NFS |
| Headroom | 2GB | - | Buffer / future |

### Anton (128GB RAM, i5-12600kf 10c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB (reserved) | - | OS overhead |
| Ollama VM | 32GB | 4 | GPU passthrough (RTX 3060) |
| OpenClaw VM | 8GB | 2 | AI assistant gateway |
| Personal Ubuntu VM | 16GB | 6 | Development workstation |
| Services VM (Docker) | 32GB | 4 | All temporary services |
| Headroom | 36GB | - | Future VMs / workloads |

### Services node (planned - 48GB RAM, Ryzen 7 3700x 8c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB (reserved) | - | OS overhead |
| Services VM (Docker) | 32GB | 8 | All migrated services from Anton |
| Headroom | 12GB | - | Future VMs |


---

## VM Strategy

VMs created via:

- Terraform
- Cloud-init templates

Base OS:

- Ubuntu Server

NFS mount options:

All VM NFS mounts use `soft,timeo=30` to prevent indefinite hangs during
Storinator maintenance or ZFS scrubs. This converts NFS hangs into errors
that services can recover from on retry.

VM backups:

Proxmox vzdump backs up VMs to Storinator `backups` dataset via NFS.

| VM | Frequency | Rationale |
|----|-----------|-----------|
| HAOS | Daily | Stateful; not reproducible from code |
| All other VMs | Weekly | Stateless; reproducible via Terraform + cloud-init |


---

## VM Layout

### NUC (always-on infrastructure)

**DNS VM**:

| Service | Notes |
|---------|-------|
| AdGuard Home | DNS + ad blocking; secondary DNS 8.8.8.8 configured as fallback |
| Tailscale exit node (primary) | VPN exit node; coupled with DNS VM, acceptable since exit node is not used consistently |

**Home Assistant VM**:

| Service | Notes |
|---------|-------|
| Home Assistant OS | Home automation; full HAOS qcow2 image (separate Terraform resource, not cloud-init) |

HAOS provisioning: Terraform downloads the official HAOS `.qcow2` image and creates
the VM using `proxmox_virtual_environment_download_file` + a dedicated VM resource.
HAOS config/state is backed up daily via Proxmox vzdump to Storinator. On rebuild,
restore from the latest vzdump backup via the HAOS UI or `ha` CLI.

**Infisical VM**:

| Service | Notes |
|---------|-------|
| Infisical | Secrets manager for service runtime secrets; data on Storinator NFS |
| Vaultwarden | Personal password manager (Bitwarden-compatible); data on Storinator NFS |

### Anton (compute - GPU workloads)

**Permanent:**

**Ollama VM**:
| Service | Notes |
|---------|-------|
| Ollama | GPU inference via RTX 3060 |
| Tailscale exit node (backup) | Secondary exit node; Anton is always-on compute |

**OpenClaw VM**:
| Service | Notes |
|---------|-------|
| OpenClaw | Personal AI assistant gateway |

**Personal Ubuntu VM**:
| Service | Notes |
|---------|-------|
| Ubuntu Desktop/Server | Development workstation |

**Services VM** (temporary - migrate to services node when built):
| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy; colocated with services it fronts |
| n8n | Automation workflows |
| Jellyfin | Media server; GPU transcoding |
| Servarr stack | Radarr, Sonarr, Prowlarr, etc. |
| PhotoPrism | Photo archive and browsing |
| Calibre | Ebook server |
| Obsidian LiveSync | CouchDB sync; data on Storinator NFS |
| Quartz | Read-only web publishing of Obsidian vault; reads vault from Storinator NFS, served via Traefik |
| Homepage | Service dashboard |
| Monitoring (Prometheus + Grafana + Loki) | Metrics, logs, dashboards |

### Services node (planned - tbd nickname)

Takes over all non-permanent services from Anton when built.

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy |
| Jellyfin | GPU transcoding via P2000 (if installed) |
| Servarr stack | Radarr, Sonarr, Prowlarr, etc. |
| PhotoPrism | Photo archive and browsing |
| Calibre | Ebook server |
| n8n | Automation workflows |
| Obsidian LiveSync | CouchDB sync |
| Quartz | Read-only web publishing of Obsidian vault |
| Monitoring (Prometheus + Grafana + Loki) | Metrics, logs, dashboards |

Migration from Anton is designed to be trivial: all persistent data lives on
Storinator NAS, so services can be repointed by redeploying Terraform with
the new node target.


---

## Headless Service Configuration

All services are configured without the web UI. This section documents the
strategy for each service that would otherwise require a first-boot setup wizard.

### AdGuard Home

Pre-seeded `AdGuardHome.yaml` mounted into the container bypasses the setup
wizard entirely. AdGuard checks for a valid config on startup and skips the
wizard if one exists.

- Config file: `services/dns/adguard/AdGuardHome.yaml` (committed to repo)
- Admin password stored as bcrypt hash in the config file; plaintext in Infisical
- Upstream DNS: `8.8.8.8` and `8.8.4.4` as fallback

### Infisical

Bootstrapped via the `infisical bootstrap` CLI command (part of the Infisical
CLI, version ≥ 0.28) after the container starts for the first time.

- Script: `scripts/infisical-bootstrap.sh`
- Creates: admin user, organization, workspace, machine identity
- Outputs: `workspace_id`, `client_id`, `client_secret` → add to `terraform.tfvars`
- Idempotent: `--ignore-if-bootstrapped` flag prevents re-running from causing issues
- See bootstrap phase step 9 above

### Jellyfin

No env var exists to skip the first-boot wizard. The wizard is driven headlessly
via the `/Startup/*` API endpoints immediately after the container starts.

- Script: `scripts/jellyfin-init.sh`
- Steps: set locale → create admin account → skip remote access config → complete wizard
- Library paths configured via `POST /Library/VirtualFolders` after wizard completes
- Admin credentials from Infisical; script is idempotent (checks if wizard already done)

### Radarr / Sonarr / Prowlarr

Pre-seeded `config.xml` placed in each app's `/config` directory before first
container start. The API key is chosen in advance and stored in Infisical,
making cross-app linking deterministic.

- Config files: `services/anton/config/radarr.xml`, `sonarr.xml`, `prowlarr.xml`
- API keys set to predetermined values from Infisical (not randomly generated)
- Prowlarr → Radarr and Prowlarr → Sonarr application links configured via
  `scripts/servarr-init.sh` using `POST /api/v1/applications` after all three start
- Auth: `AuthenticationRequired=DisabledForLocalAddresses` (LAN-only, behind Traefik)

### Calibre-Web

Admin password set via the `cps.py -s admin:password` CLI after first start.
Library path pre-configured by mounting the NAS path at `/books` (the default).

- Script: `scripts/calibre-init.sh` — runs `docker exec calibre-web python3 /app/calibre-web/cps.py -p /config/app.db -s admin:$CALIBRE_ADMIN_PASSWORD`
- Admin password from Infisical
- Calibre library must already exist at `/mnt/nas/media/books` on the NAS

### n8n

Owner account created via `POST /api/v1/owner/setup` immediately after first
start. This unauthenticated endpoint is only available on a fresh instance.

- Script: `scripts/n8n-init.sh`
- Creates owner account with credentials from Infisical
- Idempotent: endpoint returns an error if owner already exists (ignore on re-run)

### CouchDB (Obsidian LiveSync)

Admin credentials set via env vars. Single-node initialization and CORS
configuration done via curl API calls in an init container.

- Init container: `couchdb-init` using `curlimages/curl`
- Init script: `services/anton/couchdb-init.sh` (committed to repo)
- Steps: wait for healthy → `/_cluster_setup` → create `obsidian` database → set CORS headers
- CORS origins: `app://obsidian.md,capacitor://localhost,http://localhost`
- Idempotent: `PUT /obsidian` returns `409 Conflict` if DB exists (ignored)

---

## Terraform State Backend

Backend type:

Local file on Storinator NFS (`terraform-state` dataset)

Notes:

- State file lives at `/mnt/storinator/terraform-state/homelab.tfstate`
- Storinator NFS share must be mounted on the machine running Terraform
- No locking concerns - single operator, no concurrent applies
- State is replicated to Gringotts daily via Storinator replication
- Storinator ZFS snapshots provide state version history


---

## Reverse Proxy

Single Traefik instance on Anton serves all services across all nodes. NUC-hosted
services (Infisical, Vaultwarden, Obsidian LiveSync) are configured as external
backends pointing at their local IPs (e.g. `192.168.0.21`). All nodes are on the
same LAN so Traefik on Anton can reach them directly.

This avoids running a second Traefik instance on NUC and keeps TLS termination
centralised.

---

## Secret Storage

**Terraform secrets**: `terraform.tfvars` (gitignored, stored on operator laptop)

- Contains Proxmox API token and Tailscale API key only
- Backed up in Vaultwarden
- Never committed to Git

**Service runtime secrets**: Infisical (self-hosted, NUC Infisical VM)

- Seeded automatically via Terraform using the Infisical provider during `terraform apply`
- Secrets are defined in `terraform.tfvars` and written to Infisical as part of provisioning
- Docker services pull secrets via Infisical env injection at container startup
- No manual seeding step required; services start cleanly after first apply

**Personal password manager**: Vaultwarden (NUC Infisical VM, always-on)

## Database Backup Strategy

Vaultwarden and Infisical databases are stored on **local VM disk** (not NFS) to
avoid corruption from soft-mount interruptions. Backups go to Storinator NFS.

| Service | DB | Backup method | Frequency |
|---------|----|---------------|-----------|
| Vaultwarden | SQLite | [Litestream](https://litestream.io) — continuous WAL streaming to NFS | Continuous (near real-time) |
| Infisical | MongoDB | `mongodump` cron job → NFS | Every 6 hours |

Proxmox vzdump of the Infisical VM provides full disaster recovery (daily).
Litestream gives Vaultwarden point-in-time recovery down to seconds.

---

## Ansible

Responsibility split:

```
cloud-init (runs once at VM creation):
  - OS base config: hostname, timezone, locale, SSH keys
  - Tailscale install + auth (using key from Terraform)
  - Docker install
  - NFS mount entries in /etc/fstab (with soft,timeo=30)
  - First boot: pull and start Docker Compose services

Ansible (runs on demand for day-2 operations):
  - Physical node Tailscale install (bootstrap)
  - Tailscale key rotation across all nodes/VMs
  - Docker engine upgrades
  - NFS mount option changes
  - Package updates / security patches
  - Cloud-init config drift remediation
  - Ad-hoc debugging / config fixes across fleet
```

Rule of thumb: cloud-init for "birth", Ansible for "life". If a VM can be
destroyed and recreated instead of patched, prefer that. Ansible is the
escape hatch for when recreation is disruptive.

```
ansible/
  inventory/
    hosts.yml       # all physical nodes + all VMs
  tailscale.yml     # installs and auths Tailscale on physical nodes
  maintenance.yml   # day-2 operations: updates, key rotation, drift fixes
```

Auth keys for physical nodes are generated by Terraform
(`tailscale_tailnet_key` resource) and passed to the playbook as variables.

---

## UPS / NUT Integration

UPS covers: Anton, Storinator, Orange Pi Zero 3

NUT server runs on: Orange Pi Zero 3 (must be on UPS circuit to send shutdown signals before power loss)

NUT clients: Anton, NUC, Storinator (shut down gracefully on power loss)


---

# 6. Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Terraform code drift | Acknowledged — code update deferred, plan is source of truth |
| HAOS provisioning | Terraform provisions VM via qcow2 image download; config restored from Proxmox vzdump backup |
| Reverse proxy for NUC services | Single Traefik on Anton; NUC services configured as external backends by local IP |
| Vaultwarden/Infisical DB on NFS | Databases on local VM disk; Vaultwarden backed up via Litestream (continuous), Infisical via mongodump every 6h |
| Bootstrap Infisical seeding | Two-pass terraform apply: pass 1 provisions VMs, `scripts/infisical-bootstrap.sh` bootstraps Infisical, pass 2 seeds secrets |
| NUC RAM headroom | Accept the risk; monitor closely |
| Tailscale exit node coupling | Accept DNS+exit node coupling on NUC; add Anton as backup exit node |
| Ansible code missing | Acknowledged — code update deferred |
| Mimir/Tempo in services node | Removed; stack is Prometheus + Grafana + Loki only |
| OpenClaw migration | OpenClaw is permanent on Anton; removed from services node migration list |
| AdGuard headless config | Pre-seeded AdGuardHome.yaml mounted at container start; bypasses setup wizard |
| Jellyfin headless setup | /Startup/* API endpoints scripted in jellyfin-init.sh; no GUI required |
| Servarr headless setup | Pre-seeded config.xml with predetermined API keys; cross-app linking via servarr-init.sh |
| Calibre-Web headless setup | Post-start CLI password reset via cps.py -s flag; library path via /books mount |
| n8n headless setup | POST /api/v1/owner/setup API call scripted in n8n-init.sh |
| CouchDB headless setup | Init container runs /_cluster_setup + CORS config; no GUI required |

