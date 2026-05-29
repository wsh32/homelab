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

> All static IP assignments are defined in `network.yml` at the repo root.
> That file is the single source of truth — edit IPs there.

Router: `192.168.0.1` (Eero)

DHCP: `192.168.0.100 – 192.168.0.254` (Eero managed)

Physical nodes get DHCP reservations in the Eero app. VMs get static IPs configured via cloud-init, outside the DHCP range.

IP ranges: physical nodes `.4–.19` (`.7` = alakazam-deploy), diglett-dns VM special-cased at `.2`, Diglett VMs `.21–.29`, Machamp VMs `.30–.49`.

| Device | Hostname | IP | Notes |
|--------|----------|----|-------|
| diglett-dns VM | diglett-dns | 192.168.0.2 | Static (Terraform) — AdGuard Home; special-cased outside VM range |
| (future) | dns2 | 192.168.0.3 | Reserved for backup DNS VM |
| Alakazam | alakazam | 192.168.0.4 | Static (TrueNAS UI) |
| Machamp | machamp | 192.168.0.5 | Static (Ansible — `/etc/network/interfaces`) |
| Diglett | diglett | 192.168.0.6 | Static (Ansible — `/etc/network/interfaces`) |
| alakazam-deploy | alakazam-deploy | 192.168.0.7 | Static (TrueNAS UI) — deploy host (TrueNAS KVM) |
| diglett-infra VM | diglett-infra | 192.168.0.21 | Static (Terraform) — Infisical + Vaultwarden |
| diglett-haos VM | diglett-haos | 192.168.0.22 | Static (Terraform) — Home Assistant OS |
| machamp-services VM | machamp-services | 192.168.0.30 | Static (Terraform) |
| machamp-dev VM | machamp-dev | 192.168.0.31 | Static (Terraform) |

---

## Remote Access

All physical nodes and VMs join Tailscale. VM auth keys are provisioned automatically via Terraform cloud-init. All nodes communicate freely — no ACL segmentation for now.

---

## DNS Architecture

Two domains serve different audiences without subnet routing or internet exposure:

| Domain | Path | DNS resolution | Protocol | Audience |
|--------|------|----------------|----------|----------|
| `*.wsh` | Tailscale | AdGuard CNAME → `machamp-services.ts.home` | HTTPS (step-ca TLS) | Personal devices on Tailscale |
| `*.home` | LAN | AdGuard A → `192.168.0.30` | HTTP | Any LAN device (including guests) |

**How resolution works:**

- Headscale pushes AdGuard's Tailscale IP as the authoritative resolver for both `.wsh` and
  `.home` to all tailnet members via `dns_config` → `nameservers`.
- On-tailnet devices query AdGuard over Tailscale. `*.wsh` resolves to
  `machamp-services.ts.home` (Tailscale MagicDNS), which each node resolves locally from its
  peer map to the services VM's Tailscale IP. Traefik answers on port 443 with a valid
  step-ca TLS cert.
- LAN-only devices (guests, IoT) use AdGuard via the LAN IP `192.168.0.2`. `*.home` resolves
  to `192.168.0.30` directly. Traefik answers on port 80, plain HTTP.
- A device on the LAN with Tailscale uses the `*.wsh` path (Tailscale is preferred);
  `*.home` is the fallback for non-Tailscale LAN clients.

**TLS:**

- `*.wsh` — step-ca local CA issues a wildcard cert. Traefik uses ACME against the local
  step-ca endpoint (`step` cert resolver). Personal devices trust the step-ca root CA
  (installed once per device).
- `*.home` — plain HTTP. LAN fallback for guests; no TLS required.
- Let's Encrypt is not used — it does not issue certs for private TLDs like `.wsh` or `.home`.

**Per-service exposure control:**

Each service defaults to being exposed on both domains. To restrict:
- Tailscale-only: include only the `-wsh` Traefik router, omit `-home`.
- LAN-only: include only the `-home` router, omit `-wsh`.
- Both (default): include both routers.

---

# 4. Storage Architecture

**Alakazam** is NAS-only. The only additional software is Tailscale. No Docker, no services beyond TrueNAS.

| Dataset | Purpose |
|---------|---------|
| backups | VM backups |
| media | Media storage |
| docker | Persistent Docker volumes |
| apps/terraform | Terraform state files |
| photos | Photo archive |
| lightroom | Photo raws, Lightroom library backup |

**Replication:** Alakazam → Ditto

| Dataset | Frequency |
|---------|-----------|
| docker | Daily |
| apps/terraform | Daily |
| backups | Daily |
| media | Weekly |
| photos | Weekly |
| lightroom | Weekly |

---

# 5. Proxmox Architecture

## Cluster Layout

| Node | Role | Status |
|------|------|--------|
| Machamp | Compute — GPU workloads, all Docker Compose services | Active |
| Diglett | Always-on infrastructure | Active |

Full Proxmox cluster for single-pane management only. No HA or live migration.

---

## Bootstrap Phase

### One-time manual steps (Proxmox UI)

1. **Proxmox cluster** — join Machamp and Diglett into a single Proxmox cluster
2. **Proxmox API token** — create a Terraform service account and API token on each node

### One-time manual steps (Alakazam TrueNAS UI)

3. **NFS datasets** — create and export:
   - `apps/terraform` — Terraform state files (mounted at `/mnt/terraform-state` on the deploy VM)
   - `docker` — persistent Docker volumes for all services

### One-time manual steps (operator laptop)

4. **Configure static IPs on physical nodes** — `ansible-playbook ansible/network.yml`
   for Machamp and Diglett; set static IP on Alakazam via TrueNAS UI.
5. **Write `terraform.tfvars`** — populate with Proxmox API tokens, SSH public key,
   and Cloudflare API token. This is the only manual credential entry in the bootstrap.
6. **Create `alakazam-deploy` VM in TrueNAS SCALE UI** — create a 1-core/1GB Ubuntu 24.04
   KVM VM, assign static IP `192.168.0.7` inside the VM. All subsequent steps run from
   inside the network.
7. **Bootstrap the deploy VM** — run the bootstrap script from the operator laptop:
   ```
   ssh ubuntu@192.168.0.7 \
     TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
     bash -s < scripts/bootstrap-alakazam-deploy.sh
   ```
   Then copy `terraform.tfvars` to `~/homelab/terraform/diglett/` and
   `~/homelab/terraform/machamp/` on the deploy VM.

### From the alakazam-deploy VM

9. **`terraform apply -target=module.dns`** — provisions the DNS VM. Terraform creates
   the Cloudflare Tunnel via the Cloudflare provider; the tunnel token flows automatically
   into the DNS VM cloud-init. AdGuard, Headscale, and cloudflared all start on first boot.
10. **`ansible-playbook ansible/bootstrap-headscale.yml`** — waits for Headscale to be
    healthy, generates a reusable pre-auth key, writes it to `terraform.tfvars` on the
    deploy VM.
11. **`terraform apply`** — provisions all remaining VMs. Cloud-init handles Docker
    install and NFS mounts. VMs do not yet have Infisical credentials.
12. **`INFISICAL_ADMIN_PASSWORD=<pass> ansible-playbook ansible/infra.yml`** — deploys the
    diglett-infra stack (Infisical, Vaultwarden, MongoDB, Redis, Litestream) and bootstraps
    Infisical on first run (admin user `admin@homelab.local`, org, workspace). Outputs
    `workspace_id`, `client_id`, `client_secret` — add these to `terraform.tfvars`. Idempotent
    on re-run (bootstrap skipped after first successful run).
13. **`ansible-playbook ansible/site.yml`** — brings up all services. Each service role
    generates its own secrets, seeds them to Infisical, writes config, and starts the
    container. Vaultwarden account creation attempted via the Bitwarden CLI (`bw register`);
    falls back to one manual browser registration if the CLI doesn't support it.
14. **Add external API keys to Infisical** — the only remaining manual step. Add secrets
    that cannot be generated locally: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
    `GITHUB_TOKEN`, etc. via the Infisical UI.

After step 13, all services are running. Step 14 can be done at any time and only affects
services that depend on those external keys.

---

## VM Resource Budget

### Diglett (16GB RAM, i3-8109U 4c/4t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 2GB | — | OS overhead |
| diglett-dns | 2GB | 2 | AdGuard + Tailscale exit node + Headscale + cloudflare-ddns |
| diglett-haos | 4GB | 2 | HAOS |
| diglett-infra | 6GB | 2 | Infisical + Vaultwarden |
| Headroom | 2GB | — | Buffer / future |

### Machamp (128GB ECC RAM, Threadripper 3975WX 32c/64t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB | — | OS overhead |
| machamp-services | 32GB | 8 | All Docker Compose services; GPU passthrough (Quadro P2200) for Jellyfin |
| machamp-dev | 16GB | 6 | Development workstation |
| Headroom | 76GB | — | Future VMs / workloads |

### Services node (planned — 128GB RAM, Ryzen 7 3700x 8c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB | — | OS overhead |
| Services VM | 32GB | 8 | All migrated services from Machamp |
| Headroom | 92GB | — | Future VMs / workloads |

---

## VM Strategy

- **Provisioning:** Terraform + cloud-init templates
- **Base OS:** Ubuntu 24.04 (Noble)
- **NFS mounts:** All use `soft,timeo=30` to prevent indefinite hangs during Alakazam maintenance or ZFS scrubs. Hangs become errors that services can retry.
- **Backups:** Proxmox vzdump to Alakazam `backups` dataset

| VM | Frequency | Rationale |
|----|-----------|-----------|
| HAOS | Daily | Stateful; not reproducible from code |
| All other VMs | Weekly | Stateless; reproducible via Terraform + cloud-init |

---

## VM Layout

### Diglett (always-on infrastructure)

**diglett-dns** (`192.168.0.2`):

| Service | Notes |
|---------|-------|
| AdGuard Home | DNS + ad blocking; 8.8.8.8 as fallback upstream |
| Tailscale exit node (primary) | Coupled with DNS VM; acceptable since exit node is used infrequently |
| Headscale | Tailscale coordination server; public HTTPS on port 443 via Eero port forward (TCP 443 → 192.168.0.2). TLS via Let's Encrypt DNS-01 (Cloudflare). |
| cloudflare-ddns | Keeps the `headscale.wesleysoohoo.me` A record pointed at the current home IP |

**diglett-haos** (`192.168.0.22`):

| Service | Notes |
|---------|-------|
| Home Assistant OS | Full HAOS qcow2 image; separate Terraform resource, not cloud-init |

Terraform downloads the official HAOS `.qcow2` image via `proxmox_virtual_environment_download_file`
and creates a dedicated VM resource. HAOS config is backed up daily via Proxmox vzdump.
On rebuild, restore from the latest vzdump backup via the HAOS UI or `ha` CLI.

**diglett-infra** (`192.168.0.21`):

| Service | Notes |
|---------|-------|
| Infisical | Machine-consumed secrets: service API keys, inter-service tokens, developer API keys |
| Vaultwarden | Human-consumed secrets: web UI admin passwords, personal credentials |

Infisical stores all machine-read secrets — both service API keys (fetched at VM boot via
`infisical export`) and developer API keys accessed via `infisical run -- <command>` on the
operator laptop (Claude, Codex, GitHub tokens, etc.).
Vaultwarden stores all passwords a human types into a browser. The two stores never overlap.

### Physical deploy host

**alakazam-deploy** (`192.168.0.7` — TrueNAS SCALE KVM, out-of-band):

| Tool | Notes |
|------|-------|
| Terraform | Manages Diglett and Machamp VMs; `terraform.tfvars` lives here |
| Ansible | Runs `base.yml` after Terraform apply; reaches all VMs over Tailscale SSH |

### Machamp (compute — GPU workloads)

**machamp-services** (`192.168.0.30`):

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy; two entrypoints: `web` (80, `*.home`) and `websecure` (443, `*.wsh`) |
| step-ca | Local CA; issues wildcard `*.wsh` cert; Traefik ACME uses local step-ca endpoint |
| Authentik | OIDC identity provider; SSO for headplane and future services |
| Jellyfin | Media server; GPU transcoding |
| Servarr stack | Radarr, Sonarr, Prowlarr |
| PhotoPrism | Photo archive and browsing |
| Calibre-Web | Ebook server |
| n8n | Automation workflows |
| Obsidian LiveSync | CouchDB sync; data on Alakazam NFS |
| Quartz | Read-only Obsidian vault web publishing; reads vault from Alakazam NFS |
| Homepage | Service dashboard |
| Prometheus + Grafana + Loki | Metrics, logs, dashboards |

**machamp-dev** (`192.168.0.31`):

| Service | Notes |
|---------|-------|
| Ubuntu Server | Development workstation |

### Services node (planned)

Takes over all non-permanent services from Machamp when built. Migration is trivial — all
persistent data lives on Alakazam NFS, so services redeploy by retargeting Terraform.

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy; `web` (80, `*.home`) and `websecure` (443, `*.wsh`) |
| step-ca | Local CA; issues wildcard `*.wsh` cert (migrates with services VM) |
| Jellyfin | GPU transcoding via P2200 (migrates with services VM) |
| Servarr stack | Radarr, Sonarr, Prowlarr |
| PhotoPrism | Photo archive and browsing |
| Calibre-Web | Ebook server |
| n8n | Automation workflows |
| Obsidian LiveSync | CouchDB sync |
| Quartz | Read-only Obsidian vault web publishing |
| Prometheus + Grafana + Loki | Metrics, logs, dashboards |

---

## Headless Service Configuration

All services are configured without the web UI. Two accepted exceptions where scripting
is infeasible: **HAOS** (stateful home automation, restored from backup) and **Vaultwarden**
(client-side key derivation prevents scripted account creation — one browser registration,
persists on NFS forever).

### AdGuard Home

Pre-seeded `AdGuardHome.yaml` mounted into the container before first start. AdGuard detects
a valid config on startup and skips the wizard entirely.

- Config file: `services/dns/adguard/AdGuardHome.yaml` (committed to repo)
- Admin password stored as bcrypt hash in the config file; plaintext in Vaultwarden
- Upstream DNS: `8.8.8.8`, `8.8.4.4`
- DNS rewrites (committed in `AdGuardHome.yaml`):
  - `*.wsh` → CNAME `machamp-services.ts.home` (Tailscale MagicDNS hostname for the services VM)
  - `*.home` → A record `192.168.0.30` (services VM LAN IP)
- Headscale pushes the AdGuard VM's Tailscale IP as the DNS resolver for `.wsh` and `.home`
  to all tailnet members via `dns_config` → `nameservers`

### Infisical

Bootstrapped via `infisical bootstrap` CLI (requires Infisical CLI ≥ 0.28) after first start.

- Playbook: `ansible/infra.yml` (Bootstrap Infisical play)
- Creates: admin user (`admin@homelab.local`), organization, workspace
- Idempotent: skipped after first run via marker at `/var/lib/infisical/.bootstrapped` on diglett-infra
- Run: `INFISICAL_ADMIN_PASSWORD=<pass> ansible-playbook ansible/infra.yml`

### Jellyfin

No env var skips the setup wizard. The wizard is driven headlessly via the `/Startup/*` API.

- Script: `scripts/jellyfin-init.sh`
- Sequence: set locale → create admin → configure remote access → complete wizard
- Libraries added via `POST /Library/VirtualFolders` after wizard completion
- Idempotent: checks wizard status before running

### Radarr / Sonarr / Prowlarr

Pre-seeded `config.xml` placed in each app's `/config` directory before first container start.
API keys are generated by the Ansible service role, seeded to Infisical, and written into
the config files — making cross-app linking deterministic without Terraform involvement.

- Config files: `services/machamp/config/radarr.xml`, `sonarr.xml`, `prowlarr.xml`
- API keys generated by Ansible role (random hex), seeded to Infisical, written to config
- `AuthenticationRequired=DisabledForLocalAddresses` — LAN-only, behind Traefik
- Prowlarr → Radarr/Sonarr linked via `scripts/servarr-init.sh` (`POST /api/v1/applications`)

### Calibre-Web

Admin password set via the `cps.py -s` CLI after first start. Library path defaults to
`/books`, which is mounted from the NAS.

- Script: `scripts/calibre-init.sh`
- Runs: `docker exec calibre-web python3 /app/calibre-web/cps.py -p /config/app.db -s admin:$CALIBRE_ADMIN_PASSWORD`
- Calibre library must already exist at `/mnt/nas/media/books` on Alakazam

### n8n

Owner account created via `POST /api/v1/owner/setup` on first start. This unauthenticated
endpoint is only available on a fresh instance.

- Script: `scripts/n8n-init.sh`
- Idempotent: endpoint errors if owner already exists (ignored on re-run)

### Vaultwarden

Account creation requires client-side PBKDF2 key derivation — cannot be scripted without
implementing Bitwarden's full crypto client. Accepted as a one-time manual bootstrap step.

- Start Vaultwarden with `SIGNUPS_ALLOWED=true` (default on first boot)
- Register at `https://vault.home` in a browser
- Signups lock automatically after first account; `SIGNUPS_ALLOWED=false` enforced by env var on restart
- Account persists on Alakazam NFS — survives all VM rebuilds, never repeated

### CouchDB (Obsidian LiveSync)

Admin credentials set via env vars. Single-node initialization and CORS configuration
done via an init container.

- Init container: `couchdb-init` (curlimages/curl)
- Script: `services/machamp/couchdb-init.sh`
- Sequence: wait for healthy → `/_cluster_setup` → create `obsidian` DB → set CORS headers
- CORS origins: `app://obsidian.md,capacitor://localhost,http://localhost`
- Idempotent: `PUT /obsidian` 409 on existing DB is ignored

---

## Terraform State Backend

All workspaces use a local file backend on an NFS mount from Alakazam.

- Mount: `alakazam.local:/mnt/apps/terraform` → `/mnt/terraform-state` on the deploy VM
- State files: `/mnt/terraform-state/machamp/terraform.tfstate`, `/mnt/terraform-state/diglett/terraform.tfstate`
- Locking via local lockfile (Terraform default for `backend "local"`)
- Replicated to Ditto daily; ZFS snapshots provide version history

---

## Reverse Proxy

Single Traefik instance on Machamp (services VM at `192.168.0.30`) serves all services across
all nodes. Diglett-hosted services (Infisical, Vaultwarden) are configured as external backends
pointing at their local IPs (e.g. `192.168.0.21`). All nodes are on the same LAN so Traefik
on Machamp reaches them directly.

Traefik listens on two entrypoints:

| Entrypoint | Port | Protocol | Domain | Audience |
|------------|------|----------|--------|----------|
| `web` | 80 | HTTP | `*.home` | LAN devices (including guests without Tailscale) |
| `websecure` | 443 | HTTPS | `*.wsh` | Tailscale-connected devices; TLS via step-ca local CA |

Each service gets two Docker Compose router labels:

```yaml
# Tailscale path — HTTPS, personal devices
- "traefik.http.routers.<name>-wsh.rule=Host(`<name>.wsh`)"
- "traefik.http.routers.<name>-wsh.entrypoints=websecure"
- "traefik.http.routers.<name>-wsh.tls=true"
# LAN fallback — HTTP, guests
- "traefik.http.routers.<name>-home.rule=Host(`<name>.home`)"
- "traefik.http.routers.<name>-home.entrypoints=web"
# Backend
- "traefik.http.services.<name>-svc.loadbalancer.server.port=<port>"
```

To restrict a service to Tailscale-only, omit the `-home` router. To restrict to LAN-only,
omit the `-wsh` router. Both routers share the same backend service, so the same container
serves both domains.

TLS: Traefik uses a local ACME endpoint (`step` cert resolver) pointing at step-ca.
step-ca issues a wildcard cert for `*.wsh`. No Let's Encrypt — Let's Encrypt does not issue
certs for private TLDs. `*.home` is HTTP only (LAN fallback for guests; no TLS needed).

---

## Secret Storage

Three separate stores with distinct roles, split by **consumer**:

**`terraform.tfvars`** — alakazam-deploy VM, gitignored

The provisioning source of truth. Manually supplied values only:
- Proxmox API token + endpoint + username (one set per node)
- SSH public key
- Cloudflare API token (used by Terraform to create the tunnel and manage DNS)
- Headscale pre-auth key (written automatically by `ansible/bootstrap-headscale.yml`)

No service secrets are generated or stored in Terraform. Backed up as an encrypted
note in Vaultwarden. Never committed to Git.

**Infisical** — Diglett Infisical VM, machine-consumed secrets

Stores all secrets that services or processes read programmatically:
- Service API keys and inter-service tokens (Prowlarr → Radarr/Sonarr API keys, etc.)
- Developer API keys accessed via `infisical run -- <command>` on the operator laptop:
  `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, etc.

At VM boot, a systemd unit runs `infisical export --format dotenv > /etc/homelab.env`
before Docker Compose starts. Services read `/etc/homelab.env` via `env_file:`. The file
is ephemeral and regenerated on each boot.

Bootstrap secrets for diglett-infra itself (`MONGO_ROOT_PASSWORD`, `INFISICAL_AUTH_SECRET`,
`INFISICAL_ENCRYPTION_KEY`, `VAULTWARDEN_ADMIN_TOKEN`) are generated once by the `infra`
Ansible role, written to `/etc/homelab.env` (root:root, 0600) on diglett-infra, and
NFS-persisted at `/mnt/nas/docker/infisical-backups/.secrets.env` so they survive VM
rebuilds without requiring vzdump restore.

Machine identity credentials for other VMs (`client_id`, `client_secret`, `workspace_id`) are
written to `/etc/infisical.env` (root-owned, mode 0600) on each VM. This file is the only persistent secret on each VM and is the key that unlocks
all others.

Service secrets are seeded to Infisical by each service's Ansible role at bring-up time —
not via a central seed script. External API keys that cannot be generated locally are added
manually via the Infisical UI.

**Vaultwarden** — Diglett Infisical VM, human-consumed secrets

Stores every password a human types into a browser or UI:
- All service web UI admin passwords (Grafana, n8n, Jellyfin, Calibre-Web, PhotoPrism, etc.)
- The `terraform.tfvars` file itself (encrypted note or attachment)
- Infisical admin credentials
- Any other personal account credentials

Service admin passwords are stored by each service's Ansible role immediately after the
service is configured. Account creation is attempted automatically via the Bitwarden CLI
(`bw register`) during `ansible/site.yml`; if the CLI doesn't support registration against
Vaultwarden, one manual browser registration is the accepted fallback. Account persists on
Alakazam NFS across all VM rebuilds so it never needs to be repeated.

---

## Database Backup Strategy

Vaultwarden and Infisical databases are stored on **local VM disk** (not NFS) to avoid
corruption from soft-mount interruptions. Backups go to Alakazam NFS.

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
  - Tailscale install + auth (key from Terraform, --login-server pointing at Headscale)
  - Docker install
  - NFS mount entries in /etc/fstab (soft,timeo=30)
  - First boot: pull and start Docker Compose services

Ansible (push — all targets, all operations):
  - VMs: run manually from deploy VM after terraform apply
  - Physical devices: run manually when ansible/ paths change
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
    hosts.py          # dynamic inventory generated from network.yml at repo root
  tailscale.yml       # installs Tailscale on physical nodes, pointing at Headscale
  base.yml            # day-2 config for all VMs (push)
  physical.yml        # day-2 config for physical devices (push, targets physical group)
  roles/
    base/             # applied to all Ubuntu VMs and physical devices
    docker/           # applied to VMs running Docker Compose services
    headscale/        # applied to DNS VM — Headscale + cloudflared Docker Compose + config
    network/          # Proxmox bridge config for physical nodes
```

Headscale pre-auth keys for physical nodes are generated via the Headscale CLI on the
alakazam-deploy VM and stored in Infisical. The `tailscale.yml` playbook reads the key
from Infisical at run time.

---

## Physical Device Management

Physical devices (non-VM machines: Orange Pi, future devices) are managed via Ansible
push, the same as VMs. Terraform + cloud-init don't apply since there's no Proxmox
provisioning step.

**Bootstrap** (one manual SSH session per new device):

```bash
ssh root@<device-ip> \
  TAILSCALE_AUTH_KEY=<headscale-preauth-key> \
  bash -s < scripts/bootstrap-physical.sh
```

The bootstrap script installs Tailscale and joins the Headscale tailnet. That's all —
once the device is on Tailscale, Ansible can reach it.

Then from the operator laptop (or alakazam-deploy VM):

```bash
ansible-playbook ansible/physical.yml --limit <hostname>
```

**Ongoing**: run `ansible-playbook ansible/physical.yml --limit <hostname>` from the
alakazam-deploy VM when needed.

**Registration**: add the device to `network.yml` (under `physical`, with the correct
`type`). The dynamic inventory picks it up automatically.

---

## Deployment Automation

Deploys are triggered manually from the alakazam-deploy VM. No webhook or CI automation.

```
# SSH to alakazam-deploy, then:
./scripts/deploy.sh diglett  # terraform apply + ansible for Diglett VMs
./scripts/deploy.sh machamp  # terraform apply + ansible for Machamp VMs
./scripts/deploy.sh          # all nodes
./scripts/deploy-services.sh # redeploy Docker Compose stacks only (no Terraform)
```

The alakazam-deploy VM holds `terraform.tfvars` and all deploy credentials. It is not
internet-facing — only reachable over Tailscale or the local LAN. It is a TrueNAS SCALE
KVM VM and is intentionally outside Terraform management — bootstrapped once via
`scripts/bootstrap-alakazam-deploy.sh`, then self-sufficient.

**Concurrency**: the deploy script holds a lock (`/var/lock/homelab-deploy.lock`)
so concurrent runs are prevented rather than running in parallel.

---

## UPS / NUT Integration

UPS covers: Machamp, Alakazam, Orange Pi Zero 3

NUT server: Orange Pi Zero 3 (must be on UPS circuit to send shutdown signals before power loss)

NUT clients: Machamp, Diglett, Alakazam (shut down gracefully on power loss)

---

# 6. Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Terraform code drift | Acknowledged — code update deferred, plan is source of truth |
| HAOS provisioning | Terraform provisions VM via qcow2 image download; config restored from Proxmox vzdump backup |
| Reverse proxy for Diglett services | Single Traefik on Machamp; Diglett services as external backends by local IP |
| Vaultwarden/Infisical DB location | Local VM disk; Vaultwarden via Litestream (continuous), Infisical via mongodump every 6h |
| Infisical bootstrap | `ansible/infra.yml` deploys diglett-infra stack and bootstraps Infisical (admin, org, workspace) on first run. Run as: `INFISICAL_ADMIN_PASSWORD=<pass> ansible-playbook ansible/infra.yml`. Idempotent on re-run. |
| Infisical role | Single source of truth for all machine-consumed secrets. VMs fetch via `infisical export` at boot using credentials in `/etc/infisical.env`. Service secrets seeded by each service's Ansible role at bring-up time; external API keys added manually. |
| Vaultwarden role | Human-consumed secrets only (web UI admin passwords). Populated by each service's Ansible role after the service is configured. |
| Vaultwarden account creation | Attempted automatically via `bw register` (Bitwarden CLI) during `ansible/site.yml`. One manual browser registration accepted as fallback if CLI doesn't support it. Account persists on NFS — never repeated. |
| Diglett RAM headroom | Accept the risk; monitor closely |
| Tailscale exit node coupling | Accept DNS+exit node coupling on Diglett; diglett-dns is the sole exit node |
| Monitoring stack | Prometheus + Grafana + Loki only; Mimir/Tempo removed |
| AdGuard headless config | Pre-seeded `AdGuardHome.yaml`; setup wizard bypassed entirely |
| Jellyfin headless setup | `/Startup/*` API scripted in `jellyfin-init.sh` |
| Servarr headless setup | API keys generated by Ansible role, seeded to Infisical, written to pre-seeded `config.xml`; cross-app linking via `servarr-init.sh` |
| Calibre-Web headless setup | Post-start `cps.py -s` CLI; library at `/books` mount |
| n8n headless setup | `POST /api/v1/owner/setup` scripted in `n8n-init.sh` |
| CouchDB headless setup | Env vars for credentials; init container handles `/_cluster_setup` and CORS |
| Tailscale coordination server | Self-hosted Headscale on the Diglett DNS VM (`192.168.0.2`), co-located with AdGuard. Public HTTPS on port 443 via Eero port forward (TCP 443 → 192.168.0.2:443). TLS via Let's Encrypt DNS-01 challenge (Cloudflare API token; no port 80 needed). DNS A record kept current by a `cloudflare-ddns` sidecar. Cloudflare proxy disabled — the proxy strips the TS2021 upgrade header. Uses Tailscale's public DERP relays. |
| Terraform execution host | `alakazam-deploy` (TrueNAS SCALE KVM VM, out-of-band) runs all Terraform workspaces. Intentionally outside Terraform management — bootstrapped once via script. Operator laptop is break-glass fallback. |
| Terraform state backend | Local file backend on Alakazam NFS (`/mnt/terraform-state`) for all workspaces. NFS mounted on the deploy VM at bootstrap; state files at `machamp/terraform.tfstate`, `diglett/terraform.tfstate`. |
| Physical device management | Ansible push, same model as VMs. One-time bootstrap via `scripts/bootstrap-physical.sh` (installs Tailscale only). All further config pushed via `ansible-playbook ansible/physical.yml` from alakazam-deploy. |
| Deployment automation | Manual. Operator SSHes to alakazam-deploy and runs `./scripts/deploy.sh`. No webhook, no CI. Simpler and sufficient for a personal homelab. |
| DNS domain strategy | Two domains: `*.wsh` (Tailscale/HTTPS, personal devices) and `*.home` (LAN/HTTP, guests). Avoids subnet routing; guests can reach services without Tailscale. Single Traefik instance handles both. |
| TLS for private TLDs | Let's Encrypt does not issue certs for `.wsh` or `.home`. `*.wsh` uses step-ca (local CA, wildcard cert, Traefik ACME). `*.home` is plain HTTP (LAN only, acceptable). |
| AdGuard DNS rewrites | `*.wsh` CNAME → `machamp-services.ts.home` (MagicDNS). `*.home` A → `192.168.0.30` (LAN IP). Headscale `dns_config` pushes AdGuard's Tailscale IP as resolver for both TLDs to all tailnet members. |
| Per-service network exposure | Each service defines which domains it exposes via presence/absence of `-wsh` and `-home` Traefik router labels. Default is both. |
