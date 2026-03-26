# Homelab Plan

## 1. Purpose

This document defines the target architecture and rebuild plan for my homelab.

Goals:

- Rebuild infrastructure around **Proxmox + Terraform**
- Ensure all compute infrastructure is **reproducible from Git**
- No permanent GUI configuration — everything managed via code
- Separate **compute**, **storage**, and **infrastructure services**
- Maintain **TrueNAS as a stable, NAS-only data plane**
- Support safe iteration and easy disaster recovery

---

# 2. Guiding Principles

1. **Infrastructure as Code** — all VMs defined in Terraform, no permanent UI config
2. **Immutable / Rebuildable** — VMs can be destroyed and recreated; services defined via Docker Compose
3. **Separation of Planes** — compute, infrastructure services, and storage are distinct
4. **Stateful vs Stateless** — stateful data lives on NAS; compute nodes are disposable
5. **Git as Source of Truth** — Terraform, cloud-init templates, service definitions, and docs all live here

---

# 3. Network Design

## Local Network

Router: `192.168.0.1` (Eero)

DHCP: `192.168.0.100 – 192.168.0.254` (Eero managed)

Physical nodes get DHCP reservations in the Eero app. VMs get static IPs configured via cloud-init, outside the DHCP range.

| Device | Hostname | IP | Notes |
|--------|----------|----|-------|
| nuc-dns VM | dns | 192.168.0.2 | Static (Terraform) — AdGuard Home |
| (future) | dns2 | 192.168.0.3 | Reserved for backup DNS VM |
| Storinator | storinator | 192.168.0.4 | Eero DHCP reservation |
| Anton | anton | 192.168.0.5 | Eero DHCP reservation |
| NUC | nuc | 192.168.0.6 | Eero DHCP reservation |
| Orange Pi | orangepi | 192.168.0.7 | Eero DHCP reservation |
| anton-ollama VM | anton-ollama | 192.168.0.10 | Static (Terraform) |
| anton-services VM | anton-services | 192.168.0.11 | Static (Terraform) |
| anton-openclaw VM | anton-openclaw | 192.168.0.12 | Static (Terraform) |
| anton-ubuntu VM | anton-ubuntu | 192.168.0.13 | Static (Terraform) |
| nuc-infisical VM | nuc-infisical | 192.168.0.21 | Static (Terraform) — Infisical + Vaultwarden |
| nuc-haos VM | nuc-haos | 192.168.0.22 | Static (Terraform) — Home Assistant OS |

Note: Gringotts is offsite and not on the local network.

---

## Remote Access

All physical nodes and VMs join Tailscale. VM auth keys are provisioned automatically via Terraform cloud-init. All nodes communicate freely — no ACL segmentation for now.

---

# 4. Storage Architecture

**Storinator** is NAS-only. The only additional software installed is Tailscale. No apps, no Docker, no services beyond TrueNAS.

| Dataset | Purpose |
|---------|---------|
| backups | VM backups |
| media | Media storage |
| docker | Persistent Docker volumes |
| terraform-state | Terraform state file |
| photos | Photo archive |
| lightroom | Photo raws, Lightroom library backup |

**Replication:** Storinator → Gringotts

| Dataset | Frequency |
|---------|-----------|
| docker | Daily |
| terraform-state | Daily |
| backups | Daily |
| media | Weekly |
| photos | Weekly |
| lightroom | Weekly |

---

# 5. Proxmox Architecture

## Cluster Layout

| Node | Role | Status |
|------|------|--------|
| Anton | Compute — GPU workloads, permanent Ollama host | Active |
| NUC | Always-on infrastructure | Active |
| Services node (tbd) | Services host — takes over from Anton when built | Planned |

Full Proxmox cluster for single-pane management only. No HA or live migration.

---

## Bootstrap Phase

### One-time manual steps (Proxmox UI)

1. **Proxmox cluster** — join Anton and NUC into a single Proxmox cluster
2. **Proxmox API token** — create a Terraform service account and API token on each node

### One-time manual steps (Storinator TrueNAS UI)

3. **NFS datasets** — create and export:
   - `terraform-state` — Terraform state file
   - `docker` — persistent Docker volumes for all services

### One-time manual steps (external services)

4. **Tailscale API key** — generate in the Tailscale dashboard

### Ansible (automated)

5. **Tailscale on physical nodes** — `ansible-playbook ansible/tailscale.yml`
   installs and auths Tailscale on Anton, NUC, Storinator, Gringotts, Orange Pi

### Terraform (automated)

6. **Write `terraform.tfvars`** — populate with Proxmox API token and Tailscale API key
7. **Mount Storinator NFS** — mount `terraform-state` dataset on the machine running Terraform
8. **`terraform apply` (pass 1)** — provisions all VMs; cloud-init handles Tailscale auth,
   Docker install, and Docker Compose startup. Infisical provider not yet configured.
9. **Bootstrap Infisical** — run `scripts/infisical-bootstrap.sh` against the newly provisioned
   Infisical VM. Creates admin user, organization, workspace, and machine identity.
   Outputs `workspace_id`, `client_id`, `client_secret`.
10. **Create Vaultwarden account** — open `https://vault.home` in a browser and register.
    Vaultwarden starts with `SIGNUPS_ALLOWED=true`; after the first account is created
    it locks automatically. One-time manual step; account persists on Storinator NFS
    across all future VM rebuilds.
11. **Update `terraform.tfvars`** — add Infisical credentials from step 9 and
    Vaultwarden master password and client secret for the Bitwarden Terraform provider.
12. **`terraform apply` (pass 2)** — generates all service passwords via `random_password`,
    writes `.env` files to each VM, and populates Vaultwarden automatically via the
    `maxlaverse/bitwarden` Terraform provider.
13. **Seed Infisical via UI** — add developer API keys (Claude, Codex, GitHub, etc.).
    One-time manual step; these are not managed by Terraform.

After step 12, all further infrastructure changes are managed via Terraform.
Service passwords are never manually copied — Terraform generates and stores them.

---

## VM Resource Budget

### NUC (16GB RAM, i3-8109U 4c/4t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 2GB | — | OS overhead |
| DNS VM | 2GB | 2 | AdGuard + Tailscale exit node |
| Home Assistant VM | 4GB | 2 | HAOS |
| Infisical VM | 6GB | 2 | Infisical + Vaultwarden |
| Headroom | 2GB | — | Buffer / future |

### Anton (128GB RAM, i5-12600kf 10c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB | — | OS overhead |
| Ollama VM | 32GB | 4 | GPU passthrough (RTX 3060) |
| OpenClaw VM | 8GB | 2 | AI assistant gateway |
| Personal Ubuntu VM | 16GB | 6 | Development workstation |
| Services VM | 32GB | 4 | All temporary services |
| Headroom | 36GB | — | Future VMs / workloads |

### Services node (planned — 48GB RAM, Ryzen 7 3700x 8c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB | — | OS overhead |
| Services VM | 32GB | 8 | All migrated services from Anton |
| Headroom | 12GB | — | Future VMs |

---

## VM Strategy

- **Provisioning:** Terraform + cloud-init templates
- **Base OS:** Ubuntu Server
- **NFS mounts:** All use `soft,timeo=30` to prevent indefinite hangs during Storinator maintenance or ZFS scrubs. Hangs become errors that services can retry.
- **Backups:** Proxmox vzdump to Storinator `backups` dataset

| VM | Frequency | Rationale |
|----|-----------|-----------|
| HAOS | Daily | Stateful; not reproducible from code |
| All other VMs | Weekly | Stateless; reproducible via Terraform + cloud-init |

---

## VM Layout

### NUC (always-on infrastructure)

**DNS VM** (`192.168.0.2`):

| Service | Notes |
|---------|-------|
| AdGuard Home | DNS + ad blocking; 8.8.8.8 as fallback upstream |
| Tailscale exit node (primary) | Coupled with DNS VM; acceptable since exit node is used infrequently |

**Home Assistant VM** (`192.168.0.22`):

| Service | Notes |
|---------|-------|
| Home Assistant OS | Full HAOS qcow2 image; separate Terraform resource, not cloud-init |

Terraform downloads the official HAOS `.qcow2` image via `proxmox_virtual_environment_download_file`
and creates a dedicated VM resource. HAOS config is backed up daily via Proxmox vzdump.
On rebuild, restore from the latest vzdump backup via the HAOS UI or `ha` CLI.

**Infisical VM** (`192.168.0.21`):

| Service | Notes |
|---------|-------|
| Infisical | Secrets manager for service runtime secrets AND developer API keys |
| Vaultwarden | Personal password manager (Bitwarden-compatible) |

Infisical stores only developer API keys accessed via `infisical run -- <command>` on the
operator laptop (Claude, Codex, GitHub tokens, etc.). Replaces hardcoding keys in `.zshrc`.
Service passwords are not in Infisical — they are injected via cloud-init `.env` files and
stored in Vaultwarden for human access.

### Anton (compute — GPU workloads)

**Ollama VM** (`192.168.0.10`):

| Service | Notes |
|---------|-------|
| Ollama | GPU inference via RTX 3060 passthrough |
| Tailscale exit node (backup) | Secondary exit node |

**OpenClaw VM** (`192.168.0.12`):

| Service | Notes |
|---------|-------|
| OpenClaw | Personal AI assistant gateway; permanent on Anton |

**Personal Ubuntu VM** (`192.168.0.13`):

| Service | Notes |
|---------|-------|
| Ubuntu Desktop/Server | Development workstation |

**Services VM** (`192.168.0.11`) — temporary, migrates to services node when built:

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy |
| Jellyfin | Media server; GPU transcoding |
| Servarr stack | Radarr, Sonarr, Prowlarr |
| PhotoPrism | Photo archive and browsing |
| Calibre-Web | Ebook server |
| n8n | Automation workflows |
| Obsidian LiveSync | CouchDB sync; data on Storinator NFS |
| Quartz | Read-only Obsidian vault web publishing; reads vault from Storinator NFS |
| Homepage | Service dashboard |
| Prometheus + Grafana + Loki | Metrics, logs, dashboards |

### Services node (planned)

Takes over all non-permanent services from Anton when built. Migration is trivial — all
persistent data lives on Storinator NFS, so services redeploy by retargeting Terraform.

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy |
| Jellyfin | GPU transcoding via P2000 (if installed) |
| Servarr stack | Radarr, Sonarr, Prowlarr |
| PhotoPrism | Photo archive and browsing |
| Calibre-Web | Ebook server |
| n8n | Automation workflows |
| Obsidian LiveSync | CouchDB sync |
| Quartz | Read-only Obsidian vault web publishing |
| Prometheus + Grafana + Loki | Metrics, logs, dashboards |

---

## Headless Service Configuration

All services are configured without the web UI. No first-boot wizards require manual interaction.

### AdGuard Home

Pre-seeded `AdGuardHome.yaml` mounted into the container before first start. AdGuard detects
a valid config on startup and skips the wizard entirely.

- Config file: `services/dns/adguard/AdGuardHome.yaml` (committed to repo)
- Admin password stored as bcrypt hash in the config file; plaintext in Infisical
- Upstream DNS: `8.8.8.8`, `8.8.4.4`

### Infisical

Bootstrapped via `infisical bootstrap` CLI (requires Infisical CLI ≥ 0.28) after first start.

- Script: `scripts/infisical-bootstrap.sh`
- Creates: admin user, organization, workspace, machine identity
- Outputs: `workspace_id`, `client_id`, `client_secret` → add to `terraform.tfvars`
- Idempotent via `--ignore-if-bootstrapped` flag

### Jellyfin

No env var skips the setup wizard. The wizard is driven headlessly via the `/Startup/*` API.

- Script: `scripts/jellyfin-init.sh`
- Sequence: set locale → create admin → configure remote access → complete wizard
- Libraries added via `POST /Library/VirtualFolders` after wizard completion
- Idempotent: checks wizard status before running

### Radarr / Sonarr / Prowlarr

Pre-seeded `config.xml` placed in each app's `/config` directory before first container start.
API keys are chosen in advance and stored in Infisical — not randomly generated — making
cross-app linking deterministic.

- Config files: `services/anton/config/radarr.xml`, `sonarr.xml`, `prowlarr.xml`
- `AuthenticationRequired=DisabledForLocalAddresses` — LAN-only, behind Traefik
- Prowlarr → Radarr/Sonarr linked via `scripts/servarr-init.sh` (`POST /api/v1/applications`)

### Calibre-Web

Admin password set via the `cps.py -s` CLI after first start. Library path defaults to
`/books`, which is mounted from the NAS.

- Script: `scripts/calibre-init.sh`
- Runs: `docker exec calibre-web python3 /app/calibre-web/cps.py -p /config/app.db -s admin:$CALIBRE_ADMIN_PASSWORD`
- Calibre library must already exist at `/mnt/nas/media/books` on Storinator

### n8n

Owner account created via `POST /api/v1/owner/setup` on first start. This unauthenticated
endpoint is only available on a fresh instance.

- Script: `scripts/n8n-init.sh`
- Idempotent: endpoint errors if owner already exists (ignored on re-run)

### CouchDB (Obsidian LiveSync)

Admin credentials set via env vars. Single-node initialization and CORS configuration
done via an init container.

- Init container: `couchdb-init` (curlimages/curl)
- Script: `services/anton/couchdb-init.sh`
- Sequence: wait for healthy → `/_cluster_setup` → create `obsidian` DB → set CORS headers
- CORS origins: `app://obsidian.md,capacitor://localhost,http://localhost`
- Idempotent: `PUT /obsidian` 409 on existing DB is ignored

---

## Terraform State Backend

Local file on Storinator NFS (`terraform-state` dataset).

- State file: `/mnt/storinator/terraform-state/homelab.tfstate`
- Storinator NFS must be mounted on the machine running Terraform
- Single operator; no locking concerns
- Replicated to Gringotts daily; ZFS snapshots provide version history

---

## Reverse Proxy

Single Traefik instance on Anton serves all services across all nodes. NUC-hosted services
(Infisical, Vaultwarden) are configured as external backends pointing at their local IPs
(e.g. `192.168.0.21`). All nodes are on the same LAN so Traefik on Anton reaches them directly.

---

## Secret Storage

Three separate stores with distinct roles:

**`terraform.tfvars`** — operator laptop, gitignored

The provisioning source of truth. Contains everything Terraform needs to build the lab:
- Proxmox API token + Tailscale API key
- Infisical `workspace_id`, `client_id`, `client_secret` (added after bootstrap step 9)
- All service passwords (generated via `random_password` resources or set manually)
- All external API keys

Terraform writes service passwords into `.env` files on each VM via cloud-init at
provisioning time. Services read `.env` at startup — no runtime dependency on any
secrets manager. Backed up in Vaultwarden. Never committed to Git.

**Vaultwarden** — NUC Infisical VM, personal password manager

Stores every password a human needs to log into a service:
- All service admin passwords (Grafana, n8n, Jellyfin, CouchDB, Calibre-Web, PhotoPrism, etc.)
- The `terraform.tfvars` file itself (encrypted note or attachment)
- Infisical admin credentials
- Any other personal account credentials

Populated automatically by the `maxlaverse/bitwarden` Terraform provider during pass 2
apply — no manual copying. Requires a Vaultwarden account to exist first (bootstrap step 10).
Account creation is the one manual bootstrap step; the account persists on Storinator NFS
across all VM rebuilds so it never needs to be repeated.

**Infisical** — NUC Infisical VM, developer API keys only

Stores only secrets accessed programmatically from the operator laptop via
`infisical run -- <command>`:
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN`
- Any other keys used in terminal workflows

Replaces hardcoding these in `.zshrc`. Seeded manually via the Infisical UI after
the bootstrap script runs. Terraform only interacts with Infisical to provision
the workspace and machine identity — it does not write service passwords into Infisical.

---

## Database Backup Strategy

Vaultwarden and Infisical databases are stored on **local VM disk** (not NFS) to avoid
corruption from soft-mount interruptions. Backups go to Storinator NFS.

| Service | DB | Backup method | Frequency |
|---------|----|---------------|-----------|
| Vaultwarden | SQLite | Litestream — continuous WAL streaming to NFS | Continuous |
| Infisical | MongoDB | `mongodump` cron → NFS | Every 6 hours |

Proxmox vzdump of the Infisical VM provides full disaster recovery (daily).

---

## Ansible

```
cloud-init (runs once at VM creation):
  - OS base config: hostname, timezone, locale, SSH keys
  - Tailscale install + auth (key from Terraform)
  - Docker install
  - NFS mount entries in /etc/fstab (soft,timeo=30)
  - First boot: pull and start Docker Compose services

Ansible (runs on demand for day-2 operations):
  - Physical node Tailscale install (bootstrap)
  - Tailscale key rotation across all nodes/VMs
  - Docker engine upgrades
  - NFS mount option changes
  - Package updates / security patches
  - Ad-hoc debugging / config fixes across fleet
```

Rule of thumb: cloud-init for "birth", Ansible for "life". Prefer recreating a VM over
patching it. Ansible is the escape hatch when recreation is disruptive.

```
ansible/
  inventory/
    hosts.yml       # all physical nodes + all VMs
  tailscale.yml     # installs and auths Tailscale on physical nodes
  maintenance.yml   # day-2 operations: updates, key rotation, drift fixes
```

Tailscale auth keys for physical nodes are generated by Terraform (`tailscale_tailnet_key`)
and passed to the playbook as variables.

---

## UPS / NUT Integration

UPS covers: Anton, Storinator, Orange Pi Zero 3

NUT server: Orange Pi Zero 3 (must be on UPS circuit to send shutdown signals before power loss)

NUT clients: Anton, NUC, Storinator (shut down gracefully on power loss)

---

# 6. Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Terraform code drift | Acknowledged — code update deferred, plan is source of truth |
| HAOS provisioning | Terraform provisions VM via qcow2 image download; config restored from Proxmox vzdump backup |
| Reverse proxy for NUC services | Single Traefik on Anton; NUC services as external backends by local IP |
| Vaultwarden/Infisical DB location | Local VM disk; Vaultwarden via Litestream (continuous), Infisical via mongodump every 6h |
| Infisical bootstrap | Two-pass terraform apply; `scripts/infisical-bootstrap.sh` runs between passes |
| Infisical role | Developer API keys only (`infisical run --` on laptop); service passwords go in Vaultwarden for human access and `.env` files for container injection — not in Infisical |
| Vaultwarden account creation | Cannot be headlessly pre-seeded (client-side key derivation); one manual browser registration accepted as bootstrap exception alongside HAOS. Account persists on NFS — never repeated. |
| Vaultwarden population | `maxlaverse/bitwarden` Terraform provider populates all service passwords automatically during pass 2 apply — no manual copying |
| NUC RAM headroom | Accept the risk; monitor closely |
| Tailscale exit node coupling | Accept DNS+exit node coupling on NUC; Anton is backup exit node |
| Ansible code missing | Acknowledged — code update deferred |
| Monitoring stack | Prometheus + Grafana + Loki only; Mimir/Tempo removed |
| OpenClaw placement | Permanent on Anton; not in services node migration list |
| AdGuard headless config | Pre-seeded `AdGuardHome.yaml`; setup wizard bypassed entirely |
| Jellyfin headless setup | `/Startup/*` API scripted in `jellyfin-init.sh` |
| Servarr headless setup | Pre-seeded `config.xml` with predetermined API keys; cross-app linking via `servarr-init.sh` |
| Calibre-Web headless setup | Post-start `cps.py -s` CLI; library at `/books` mount |
| n8n headless setup | `POST /api/v1/owner/setup` scripted in `n8n-init.sh` |
| CouchDB headless setup | Env vars for credentials; init container handles `/_cluster_setup` and CORS |
