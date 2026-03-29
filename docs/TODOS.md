# TODOs

## NFS Export Strategy

**What:** Define which Storinator datasets get NFS-exported, to what
clients, and with what permissions.

**Why:** All VMs mount Storinator over NFS for persistent data. Without a
consistent strategy, NFS config will be improvised per-service and become
a mess.

**Context:** Storinator datasets: `backups`, `media`, `docker`,
`terraform-state`, `photos`, `lightroom`. Each needs a defined NFS export
policy (which VMs, read-only vs read-write). All mounts use
`soft,timeo=30` options.

**Depends on:** Terraform module structure - NFS mounts will be defined
in VM cloud-init.

---

## Terraform Module Structure

**What:** Define the directory layout for Terraform code before writing any `.tf` files.

**Why:** The plan says "all VMs defined in Terraform" but doesn't specify structure. Deciding upfront prevents inconsistency as the repo grows.

**Pros:** Consistent, navigable codebase from day one.

**Cons:** Requires upfront design time before any VMs exist.

**Context:** Options to consider:
- `terraform/nodes/nuc/`, `terraform/nodes/anton/` — one directory per Proxmox node
- `terraform/services/jellyfin/`, `terraform/services/adguard/` — one directory per service
- `terraform/modules/vm/` shared module, called from per-node root modules

Recommended: shared `modules/vm` module + per-node root modules. Avoids duplication across nodes.

**Depends on:** Nothing — should be decided before any `.tf` files are written.

---

## Bootstrap Runbook

**What:** Write a step-by-step runbook with exact commands for the manual
bootstrap phase.

**Why:** The plan defines a multi-phase bootstrap. A runbook with exact
commands makes it possible to rebuild the homelab from scratch in an hour
rather than piecing it together from memory.

**Context:** Bootstrap steps per plan:
1. Form Proxmox cluster (Anton + NUC) via UI
2. Create Proxmox API token via UI
3. Create Storinator NFS datasets + exports via TrueNAS UI
4. Generate Tailscale API key via dashboard
5. Run Ansible to install Tailscale on physical nodes
6. Write `terraform.tfvars`, mount Storinator NFS on laptop
7. `terraform apply`
8. Seed Infisical via UI

Should also document: `pvecm expected 1` for quorum recovery.

**Depends on:** NFS export strategy, Terraform module structure.

---

## Proxmox GPU Passthrough for Ollama

**What:** Document and implement IOMMU/VFIO configuration for passing the RTX 3060 through to the Ollama VM on Anton.

**Why:** GPU passthrough in Proxmox requires specific kernel parameters (`intel_iommu=on`, VFIO module loading) on the host, and correct PCIe device binding. Easy to misconfigure; results in either a broken VM or the GPU not being recognized by Ollama.

**Pros:** Ollama gets full GPU performance. RTX 3060 fully utilized for inference.

**Cons:** VFIO config ties the GPU exclusively to one VM — the GPU can't be shared with other VMs or the host.

**Context:** Anton has an i5-12600kf (supports VT-d) and RTX 3060. The Ollama VM needs the GPU passed through exclusively. After passthrough, the Proxmox host will have no display output from that GPU. Plan for this: Anton likely has no monitor attached anyway.

**Depends on:** Terraform module structure (GPU passthrough config goes in the Ollama VM definition).

---

## Backup DNS VM

**What:** Deploy a secondary AdGuard Home instance on the Orange Pi.

**Why:** The primary DNS VM on the NUC is a single point of failure.
Currently mitigated by 8.8.8.8 as fallback, but that bypasses ad-blocking
and breaks `.home` domain resolution.

**Depends on:** Nothing - can be done anytime after initial deployment.

---

## Tailscale ACL Segmentation

**What:** Add role-based ACL policy via the `tailscale_acl` Terraform
resource.

**Why:** All nodes currently communicate freely over Tailscale with no
segmentation. A compromised container has lateral movement to every node
including Gringotts (offsite backup) and Proxmox management interfaces.

**Minimum policy:**
- Tag nodes by role (infra, compute, storage, backup)
- Restrict Gringotts to replication traffic from Storinator only
- Restrict Proxmox API ports to operator machine

**Depends on:** Terraform module structure.

---

## External Uptime Monitor

**What:** Deploy Uptime Kuma on the Orange Pi or use a cloud ping service
to monitor Storinator and critical services externally.

**Why:** When Storinator NFS hangs, the monitoring stack (Prometheus +
Grafana on Anton) also goes down because it depends on Storinator NFS.
An external monitor outside the NFS blast radius can detect and alert on
this.

**Depends on:** Nothing - can be done anytime.

---

## Break-glass Procedure

**What:** Document and maintain an offline copy of critical credentials
outside the homelab.

**Contents:**
- `terraform.tfvars` (Proxmox API token, Tailscale API key)
- Infisical secrets export (all service runtime secrets)
- Proxmox root credentials
- `pvecm expected 1` quorum recovery command

**Why:** If the NUC dies, running containers on Anton survive but new
deploys are blocked until Infisical returns. An offline export allows
recovery without waiting for NUC hardware replacement.

**Storage:** encrypted file in a password manager on phone, or USB drive.

**Depends on:** Initial deployment (secrets must exist before they can
be exported).

---

## Headless Bootstrap Scripts

**What:** Write the init scripts and config files needed for headless service
configuration, as documented in `docs/plan.md` under "Headless Service Configuration".

**Why:** The plan documents headless configuration strategies for every service.
Without the actual scripts and config files, the plan is correct but not
executable — first-time setup would still require manual GUI intervention.

**Files to create:**

- `scripts/infisical-bootstrap.sh` — runs `infisical bootstrap` CLI against a
  running Infisical instance, creates workspace and machine identity, outputs
  credentials to add to `terraform.tfvars`
- `scripts/jellyfin-init.sh` — drives Jellyfin `/Startup/*` API to create admin
  account and configure media libraries headlessly
- `scripts/servarr-init.sh` — links Prowlarr to Radarr and Sonarr via
  `POST /api/v1/applications`; expects predetermined API keys already set in config.xml
- `scripts/calibre-init.sh` — sets Calibre-Web admin password via `cps.py -s` CLI
- `scripts/n8n-init.sh` — creates n8n owner account via `POST /api/v1/owner/setup`
- `services/dns/adguard/AdGuardHome.yaml` — pre-seeded AdGuard config with bcrypt
  admin password, upstream DNS, and default blocklists
- `services/anton/config/radarr.xml`, `sonarr.xml`, `prowlarr.xml` — pre-seeded
  config.xml files with predetermined API keys (sourced from Infisical at boot)
- `services/anton/couchdb-init.sh` — CouchDB single-node setup + CORS config for
  Obsidian LiveSync
- `scripts/infisical-export.sh` — runs `infisical export --format dotenv` at VM boot
  to write ephemeral `.env` files for each service group; invoked from cloud-init

**Context:** Research confirmed all these services have fully headless setup paths.
See "Headless Service Configuration" section in `docs/plan.md` for the strategy
behind each script. API keys and inter-service tokens come from Infisical; web UI
admin passwords are set manually and stored in Vaultwarden.

**Depends on:** Infisical setup (scripts pull secrets from Infisical), Terraform
module structure (scripts reference service URLs and API keys).
