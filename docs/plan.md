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

192.168.4.1 (Eero)

DHCP:

________________________

Reserved IPs:

| Device | Hostname | IP |
|------|------|------|
| Anton | | |
| NUC | | |
| Storinator | | |
| Gringotts | | |


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

Replication:

Storinator → Gringotts

Frequency:

Weekly


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

## Bootstrap Phase (Manual)

Before any Terraform is run, the following must be set up manually. Everything after this is Terraform.

1. **Proxmox cluster** — join Anton and NUC into a single Proxmox cluster via the UI
2. **Ubuntu cloud-init template** — download and configure base VM template on each Proxmox node
3. **MinIO on NUC** — deploy MinIO Docker container manually on NUC (or a small VM); create `terraform-state` bucket and access credentials; data backed by Storinator NFS mount
4. **Infisical on NUC** — deploy Infisical Docker container manually on NUC infra VM; create initial admin account and seed all required secrets
5. **Tailscale on physical nodes** — manually install and auth Tailscale on Anton, NUC, Storinator, Gringotts, Orange Pi
6. **Configure Terraform backend** — write `backend.tf` pointing at MinIO; write `infisical.tf` pointing at Infisical

After bootstrap is complete, all further infrastructure is managed via Terraform.

---

## VM Resource Budget

### NUC (16GB RAM total, i3-8109U 4c/4t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 2GB (reserved) | — | OS overhead |
| Infra VM (Docker) | 8GB | 2 | Runs all Docker services |
| MinIO VM | 4GB | 2 | Object storage |
| Headroom | 2GB | — | Buffer / future |

### Anton (128GB RAM, i5-12600kf 10c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB (reserved) | — | OS overhead |
| Ollama VM | 32GB | 4 | GPU passthrough (RTX 3060) |
| Services VM (Docker) | 32GB | 6 | All temporary services |
| Headroom | 60GB | — | Future VMs / workloads |

### Services node (planned — 48GB RAM, Ryzen 7 3700x 8c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB (reserved) | — | OS overhead |
| Services VM (Docker) | 32GB | 8 | All migrated services from Anton |
| Headroom | 12GB | — | Future VMs |


---

## VM Strategy

VMs created via:

- Terraform
- Cloud-init templates

Base OS:

- Ubuntu Server


---

## VM Layout

### NUC (always-on infrastructure)

RAM budget: 16GB. All services run as Docker containers inside a single **infra VM** to share OS overhead. MinIO runs as a second small VM for object storage.

**Infra VM** (Docker Compose — all lightweight services share one OS):

| Service | Notes |
|---------|-------|
| AdGuard Home | DNS + ad blocking |
| Tailscale exit node | VPN exit node for remote access |
| Reverse proxy (Traefik) | Auto-discovers Docker services via labels |
| Home Assistant | Home automation |
| Infisical | Secret management for Terraform and services |
| Vaultwarden | Personal password manager (Bitwarden-compatible) |
| Obsidian LiveSync | CouchDB-based sync for Obsidian vault (laptop + phone) |
| Homepage / dashboard | Service dashboard |

**MinIO VM** (object storage):

| Service | Notes |
|---------|-------|
| MinIO | S3-compatible object storage; data stored on Storinator via NFS mount |

### Anton (compute — GPU workloads)

**Permanent:**

| Service | Notes |
|---------|-------|
| Ollama | GPU inference via RTX 3060 |

**Temporary (migrate to services node when built):**

| Service | Notes |
|---------|-------|
| OpenClaw | Personal AI assistant gateway |
| n8n | Automation workflows |
| Jellyfin | Media server; GPU transcoding |
| Servarr stack | Radarr, Sonarr, Prowlarr, etc. |
| PhotoPrism | Photo archive and browsing |
| Calibre | Ebook server |
| Monitoring (Prometheus + Grafana + Loki) | Metrics, logs, dashboards |

### Services node (planned — tbd nickname)

Takes over all non-permanent services from Anton when built.

| Service | Notes |
|---------|-------|
| Jellyfin | GPU transcoding via P2000 (if installed) |
| Servarr stack | Radarr, Sonarr, Prowlarr, etc. |
| PhotoPrism | Photo archive and browsing |
| Calibre | Ebook server |
| OpenClaw | Personal AI assistant gateway |
| n8n | Automation workflows |
| Monitoring (Prometheus + Grafana + Loki) | Loki, Grafana, Tempo, Mimir |

Migration from Anton is designed to be trivial: all persistent data lives on Storinator NAS, so services can be repointed by redeploying Terraform with the new node target.


---

## Terraform State Backend

Backend type:

MinIO (S3-compatible, hosted on NUC)

Notes:

- MinIO runs as a VM on NUC (always-on)
- Underlying data stored on Storinator via NFS mount (`terraform-state` dataset)
- Exposes S3 API on port 9000, accessible from any Tailscale node
- Also serves as S3-compatible object storage for other services (Loki, etc.)
- Storinator remains NAS-only; MinIO is the only service accessing its data remotely


---

## Secret Storage

Tool: **Infisical** (self-hosted)

Hosted on: NUC (infra VM, Docker container)

Personal password manager: **Vaultwarden** (Bitwarden-compatible, same infra VM on NUC)

Usage:
- Terraform uses the Infisical provider to inject secrets at plan/apply time
- Docker services pull secrets via Infisical's Docker integration or env injection
- Secrets never committed to Git in plaintext

---

## UPS / NUT Integration

UPS covers: Anton, Storinator, Orange Pi Zero 3

NUT server runs on: Orange Pi Zero 3 (must be on UPS circuit to send shutdown signals before power loss)

NUT clients: Anton, NUC, Storinator (shut down gracefully on power loss)


---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | ISSUES_OPEN (PLAN) | 9 issues, 3 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |

**UNRESOLVED:** 0 unresolved decisions

**VERDICT:** ENG REVIEW ran — 3 critical gaps (NUC SPOF, Storinator NFS dependency, NUT connectivity). All are knowingly accepted homelab tradeoffs, not blockers. No unresolved decisions. Ready to proceed to implementation.
