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

# 3. Hardware Inventory

## Compute Nodes

### Anton

Role: Main compute node

- Hostname: `anton`
- CPU: i5-12600KF
- GPU: RTX 3060
- RAM: 128GB
- OS: Proxmox

Storage:

- Boot: 500GB SATA SSD
- NVMe: 2x 2TB

Planned usage:

- GPU workloads
- VMs
- AI / ML experiments
- Development environments

Notes:

____________________________


---

### NUC (Infra Node)

Role: Always-on infrastructure host

- Hostname: `________`
- CPU: i3-8109U
- RAM: 16GB
- OS: Proxmox

Storage:

- Boot: 256GB NVMe
- SSD: 1TB SATA

Planned usage:

- DNS
- Reverse proxy
- Automation
- Monitoring

Notes:

____________________________


---

## Storage Systems

### Storinator

Role: Primary NAS

- Hostname: `storinator`
- OS: TrueNAS
- CPU: Ryzen 7 5825U
- RAM: 32GB

Storage:

- Boot: 256GB SSD
- HDD: 4x 8TB
- SSD: 2x 2TB

Responsibilities:

- Primary storage
- Backups
- Terraform state storage
- Media storage
- VM backups

Notes:

____________________________


---

### Gringotts

Role: Offsite backup

- Hostname: `gringotts`
- OS: TrueNAS
- CPU: i7-6700K
- RAM: 32GB

Storage:

- Boot: 256GB NVMe
- HDD: 4x 6TB
- NVMe: 2x 2TB

Responsibilities:

- Replicated backups
- Disaster recovery

Connection:

- Tailscale
- ZFS replication

Notes:

____________________________


---

### Orange Pi Zero 3

Role: UPS monitoring

- Hostname: `________`

Responsibilities:

- NUT server
- UPS monitoring
- Power shutdown coordination

Notes:

____________________________


---

# 4. Network Design

## Local Network

Router:

________________________

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

- __________________________________
- __________________________________

ACL strategy:

____________________________


---

# 5. Storage Architecture

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

________________________


---

# 6. Proxmox Architecture

## Cluster Layout

| Node | Role |
|-----|-----|
| Anton | Compute |
| NUC | Infrastructure |

Cluster decision:

[ ] Single node per host  
[ ] Full Proxmox cluster

Notes:

____________________________


---

## VM Strategy

VMs created via:

- Terraform
- Cloud-init templates

Base OS:

- Ubuntu Server

VM provisioning flow:

