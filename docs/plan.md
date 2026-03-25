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
8. **`terraform apply`** - provisions all VMs; cloud-init handles Tailscale auth,
   Docker install, and service startup on each VM

### Post-apply (manual, one-time)

9. **Seed Infisical** - open Infisical UI, create admin account, enter all
   service secrets; services that depend on secrets will start once seeded

After step 8, all further infrastructure changes are managed via Terraform.
Infisical seeding (step 9) only needs to be repeated if the `docker/infisical`
NFS dataset is lost - the data persists across VM recreation.

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
| Tailscale exit node | VPN exit node for remote access |

**Home Assistant VM**:

| Service | Notes |
|---------|-------|
| Home Assistant OS | Home automation (full HAOS installation) |

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
| OpenClaw | Personal AI assistant gateway |
| n8n | Automation workflows |
| Monitoring (Prometheus + Grafana + Loki) | Loki, Grafana, Tempo, Mimir |

Migration from Anton is designed to be trivial: all persistent data lives on
Storinator NAS, so services can be repointed by redeploying Terraform with
the new node target.


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

## Secret Storage

**Terraform secrets**: `terraform.tfvars` (gitignored, stored on operator laptop)

- Contains Proxmox API token and Tailscale API key only
- Backed up in Vaultwarden
- Never committed to Git

**Service runtime secrets**: Infisical (self-hosted, NUC Infisical VM)

- Docker services pull secrets via Infisical env injection at container startup
- Infisical data persists on Storinator NFS (`docker/infisical`)
- VM recreation does not lose secrets
- Seeded manually once on first deploy; see bootstrap phase

**Personal password manager**: Vaultwarden (NUC Infisical VM, always-on)

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

# 6. Open Issues for Review

## Terraform code doesn't match the plan

The plan dropped MinIO (state is now NFS-local) and split the NUC into three VMs
(dns, infisical, haos), but the scaffolded Terraform code still has `nuc-infra` and
`minio_vm`. The Docker Compose files were also written for the old single-VM
architecture. Everything needs to be reconciled before any `terraform apply`.

>

---

## HAOS can't be provisioned with cloud-init

Home Assistant OS is a purpose-built distro distributed as a `.qcow2` image with no
cloud-init support. The shared `proxmox-vm` Terraform module (clone Ubuntu template +
cloud-init) won't work for it. Options:

- A separate Terraform resource that imports the HAOS disk image directly
- Provision manually and import into Terraform state after the fact

>

---

## No reverse proxy on NUC

Infisical, Vaultwarden, and Obsidian LiveSync all need TLS. Traefik was dropped from
NUC when the architecture split into separate VMs. Currently no reverse proxy exists
for NUC-hosted services. Options:

- Add Traefik as a container inside the Infisical VM
- Add a dedicated NUC reverse proxy VM (uses more RAM)
- Expose services on raw ports with no TLS (not recommended)

>

---

## Vaultwarden + Infisical databases on NFS with soft mounts

Vaultwarden (SQLite) and Infisical (MongoDB) data is stored on Storinator via
`soft,timeo=30` NFS mounts. SQLite and MongoDB are not designed to handle
mid-write NFS interruptions gracefully — a brief Storinator outage during a write
can corrupt the database. This is especially bad for a password manager and secret
store. Options:

- Store databases on local VM disk; back up to NFS (or Proxmox vzdump handles it)
- Accept the risk; rely on daily Proxmox VM backups for recovery

>

---

## Bootstrap sequence gap — services start before Infisical is seeded

`terraform apply` (step 8) provisions VMs and cloud-init starts Docker Compose.
Infisical seeding (step 9) happens after. On first boot, any service that pulls
secrets from Infisical at startup will fail because Infisical has no secrets yet.
Options:

- Add startup retry / health-check loops to Docker Compose so services wait for
  Infisical to be seeded
- Start services manually after seeding (don't auto-start on first boot)
- Pre-seed Infisical via the API as part of `terraform apply` using a Terraform
  resource (removes the manual step entirely)

>

---

## NUC RAM is basically full

DNS VM (2GB) + HAOS VM (4GB) + Infisical VM (6GB) + Proxmox host (2GB) = 14GB of
16GB used. Two gigabytes of headroom on the machine running DNS, secret store, and
home automation. HAOS can spike above its baseline. One OOM event takes down DNS
or the password manager. Options:

- Accept the constraint; monitor closely
- Trim Infisical VM to 4GB (MongoDB is the heavy component; tune it)
- Move Vaultwarden off the Infisical VM onto another node

>

---

## Tailscale exit node and DNS on the same VM

The DNS VM runs both AdGuard and the Tailscale exit node. A reboot for a Tailscale
update or kernel patch takes down DNS at the same time as the exit node. These are
independent concerns. Options:

- Accept the coupling for now; revisit when NUC RAM allows
- Move Tailscale exit node to its own VM (requires more NUC RAM)
- Run Tailscale exit node on Anton instead (always-on is less guaranteed)

>

---

## Ansible directory doesn't exist

The plan references `ansible/tailscale.yml` and `ansible/maintenance.yml` in the
bootstrap steps, but neither file exists. Step 5 of the bootstrap is not currently
executable.

>

---

## Minor inconsistencies to clean up

- Services node notes still list "Loki, Grafana, Tempo, Mimir" — Mimir/Tempo were
  dropped in favour of Prometheus + Grafana + Loki
- OpenClaw is listed as permanent on Anton but also appears in the services node
  migration list

>

