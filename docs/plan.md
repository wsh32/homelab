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

## VM Strategy

VMs created via:

- Terraform
- Cloud-init templates

Base OS:

- Ubuntu Server


---

## VM Layout

### NUC (always-on infrastructure)

| Service | Notes |
|---------|-------|
| AdGuard Home | DNS + ad blocking |
| Tailscale exit node | VPN exit node for remote access |
| Reverse proxy | Traefik or Caddy |
| Home Assistant | Home automation |
| Obsidian LiveSync | CouchDB-based sync for Obsidian vault (laptop + phone) |
| Homepage / dashboard | Service dashboard |

### Anton (compute — GPU workloads)

| Service | Permanent? | Notes |
|---------|-----------|-------|
| Ollama | Yes | GPU inference via RTX 3060; stays on Anton permanently |
| OpenClaw | No — migrate to services node when built | Personal AI assistant gateway |
| n8n | No — migrate to services node when built | Automation workflows |
| Jellyfin | No — migrate to services node when built | Media server; GPU transcoding |
| Servarr stack | No — migrate to services node when built | Radarr, Sonarr, Prowlarr, etc. |
| PhotoPrism | No — migrate to services node when built | Photo archive and browsing |
| Calibre | No — migrate to services node when built | Ebook server |
| LGTM monitoring | No — migrate to services node when built | Loki, Grafana, Tempo, Mimir |

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
| LGTM monitoring | Loki, Grafana, Tempo, Mimir |

Migration from Anton is designed to be trivial: all persistent data lives on Storinator NAS, so services can be repointed by redeploying Terraform with the new node target.


---

## Terraform State Backend

State stored on Storinator in the `terraform-state` dataset.

Backend type:

MinIO (S3-compatible) — hosted as a VM/container, backed by the `terraform-state` dataset on Storinator via NFS

Notes:

Terraform uses the `s3` backend pointed at the MinIO instance. MinIO VM lives on NUC (always-on).


---

## UPS / NUT Integration

UPS covers: Anton, Storinator

NUT server runs on: Orange Pi Zero 3

NUT clients: Anton, NUC, Storinator (shut down gracefully on power loss)


