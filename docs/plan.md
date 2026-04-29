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

IP ranges: physical nodes `.2–.19`, NUC VMs `.20–.29`, Anton VMs `.30–.49`, services node VMs `.50–.69`.

| Device | Hostname | IP | Notes |
|--------|----------|----|-------|
| nuc-dns VM | dns | 192.168.0.2 | Static (Terraform) — AdGuard Home |
| (future) | dns2 | 192.168.0.3 | Reserved for backup DNS VM |
| Storinator | storinator | 192.168.0.4 | Static (TrueNAS UI) |
| Anton | anton | 192.168.0.5 | Static (Ansible — `/etc/network/interfaces`) |
| NUC | nuc | 192.168.0.6 | Static (Ansible — `/etc/network/interfaces`) |
| Orange Pi | orangepi | 192.168.0.7 | Static (TBD — depends on OS choice) |
| Gringotts | gringotts | 192.168.0.8 | Offsite — only reachable via Tailscale |
| Services node | services | 192.168.0.9 | Static (Ansible — `/etc/network/interfaces`) — planned |
| nuc-infisical VM | nuc-infisical | 192.168.0.21 | Static (Terraform) — Infisical + Vaultwarden |
| nuc-haos VM | nuc-haos | 192.168.0.22 | Static (Terraform) — Home Assistant OS |
| nuc-deploy VM | nuc-deploy | 192.168.0.23 | Static (Terraform) — Terraform + Ansible |
| anton-ollama VM | anton-ollama | 192.168.0.30 | Static (Terraform) |
| anton-services VM | anton-services | 192.168.0.31 | Static (Terraform) |
| anton-openclaw VM | anton-openclaw | 192.168.0.32 | Static (Terraform) |
| anton-debian VM | anton-debian | 192.168.0.33 | Static (Terraform) |
| services-node VM | services-node | 192.168.0.50 | Static (Terraform) — planned |

Note: Gringotts is offsite and not on the local network.

---

## Remote Access

All physical nodes and VMs join Tailscale. VM auth keys are provisioned automatically via Terraform cloud-init. All nodes communicate freely — no ACL segmentation for now.

---

## DNS Architecture

Two domains serve different audiences without subnet routing or internet exposure:

| Domain | Path | DNS resolution | Protocol | Audience |
|--------|------|----------------|----------|----------|
| `*.wsh` | Tailscale | AdGuard CNAME → `anton-services.ts.home` | HTTPS (step-ca TLS) | Personal devices on Tailscale |
| `*.home` | LAN | AdGuard A → `192.168.0.31` | HTTP | Any LAN device (including guests) |

**How resolution works:**

- Headscale pushes AdGuard's Tailscale IP as the authoritative resolver for both `.wsh` and
  `.home` to all tailnet members via `dns_config` → `nameservers`.
- On-tailnet devices query AdGuard over Tailscale. `*.wsh` resolves to
  `anton-services.ts.home` (Tailscale MagicDNS), which each node resolves locally from its
  peer map to the services VM's Tailscale IP. Traefik answers on port 443 with a valid
  step-ca TLS cert.
- LAN-only devices (guests, IoT) use AdGuard via the LAN IP `192.168.0.2`. `*.home` resolves
  to `192.168.0.31` directly. Traefik answers on port 80, plain HTTP.
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

**Storinator** is NAS-only. The only additional software is Tailscale and the TrueNAS Scale built-in MinIO S3 API (used as the Terraform state backend). No Docker, no services beyond TrueNAS.

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
   - `docker` — persistent Docker volumes for all services
4. **Enable MinIO** — enable the TrueNAS Scale S3 service, create a `terraform-state`
   bucket and an access key. Used as the Terraform state backend by both the deploy VM
   and the operator laptop over Tailscale.

### One-time manual steps (operator laptop)

5. **Bootstrap deploy VM** — chicken-and-egg: run `terraform apply -target=module.deploy`
   from the operator laptop. SSH in, clone repo, write `terraform.tfvars`.
6. **Bootstrap Headscale** — on the deploy VM, start the Headscale container and generate
   a reusable pre-auth key: `docker exec headscale headscale preauthkeys create --reusable --expiration 90d`.
   Save the key; add to `terraform.tfvars`.
7. **Create Cloudflare Tunnel** — in the Cloudflare dashboard, create a tunnel pointing at
   `http://headscale:8080` on the deploy VM's Docker network. Copy the tunnel token to
   Infisical (after step 10) and `terraform.tfvars`.

### Ansible (automated)

8. **Tailscale on physical nodes** — `ansible-playbook ansible/tailscale.yml`
   installs Tailscale on Anton, NUC, Storinator, Gringotts, Orange Pi, pointing at
   the Headscale server (`--login-server https://headscale.<domain>`).

### Terraform (from deploy VM or operator laptop)

9. **Write `terraform.tfvars`** — populate with Proxmox API token, Headscale pre-auth
   key, MinIO credentials, Cloudflare tunnel token, SSH public key.
10. **`terraform apply`** — run from the deploy VM via `./scripts/deploy.sh`. Provisions
    all VMs; cloud-init handles Tailscale auth (pointing at Headscale), Docker install,
    and Docker Compose startup.
11. **Bootstrap Infisical** — run `scripts/infisical-bootstrap.sh` against the newly
    provisioned Infisical VM. Creates admin user, organization, workspace, and machine
    identity. Outputs `workspace_id`, `client_id`, `client_secret`.
12. **Update `terraform.tfvars`** — add Infisical credentials from step 11.
13. **Create Vaultwarden account** — open `https://vault.home` in a browser and register.
    Vaultwarden starts with `SIGNUPS_ALLOWED=true`; after the first account is created
    it locks automatically. One-time manual step; account persists on Storinator NFS
    across all future VM rebuilds.
14. **Seed Infisical via UI** — add all service API keys, inter-service tokens, and
    developer API keys (Claude, Codex, GitHub, Cloudflare tunnel token, etc.). One-time manual step.
15. **Re-run cloud-init / reboot VMs** — services fetch secrets from Infisical via
    `infisical export` and write ephemeral `.env` files. Services start up.

After step 15, all further infrastructure changes are applied manually from the deploy VM
via `./scripts/deploy.sh`. No webhook or automation; operator triggers deploys explicitly.

---

## VM Resource Budget

### NUC (16GB RAM, i3-8109U 4c/4t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 2GB | — | OS overhead |
| DNS VM | 2GB | 2 | AdGuard + Tailscale exit node + Headscale + cloudflared |
| Home Assistant VM | 4GB | 2 | HAOS |
| Infisical VM | 6GB | 2 | Infisical + Vaultwarden |
| Deploy VM | 1GB | 1 | Terraform + Ansible |
| Headroom | 1GB | — | Buffer / future |

### Anton (128GB ECC RAM, Threadripper 3975WX 32c/64t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB | — | OS overhead |
| Ollama VM | 32GB | 4 | GPU passthrough (RTX 3060) |
| OpenClaw VM | 8GB | 2 | AI assistant gateway |
| Personal Debian VM | 16GB | 6 | Development workstation |
| Services VM | 32GB | 8 | All temporary services; GPU passthrough (Quadro P2000) for Jellyfin |
| Headroom | 40GB | — | Future VMs / workloads |

### Services node (planned — 128GB RAM, Ryzen 7 3700x 8c/16t)

| VM | RAM | vCPU | Notes |
|----|-----|------|-------|
| Proxmox host | 4GB | — | OS overhead |
| Services VM | 32GB | 8 | All migrated services from Anton |
| Headroom | 92GB | — | Future VMs / workloads |

---

## VM Strategy

- **Provisioning:** Terraform + cloud-init templates
- **Base OS:** Debian 12 (Bookworm)
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
| Headscale | Tailscale coordination server; Cloudflare Tunnel provides the public HTTPS endpoint |
| cloudflared | Cloudflare Tunnel client; exposes Headscale without a public IP or open port |

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
| Infisical | Machine-consumed secrets: service API keys, inter-service tokens, developer API keys |
| Vaultwarden | Human-consumed secrets: web UI admin passwords, personal credentials |

**Deploy VM** (`192.168.0.23`):

| Service | Notes |
|---------|-------|
| Terraform | Manages NUC, Anton, and services node VMs; `terraform.tfvars` lives here |
| Ansible | Runs `base.yml` after Terraform apply; reaches all VMs over Tailscale SSH |

Infisical stores all machine-read secrets — both service API keys (fetched at VM boot via
`infisical export`) and developer API keys accessed via `infisical run -- <command>` on the
operator laptop (Claude, Codex, GitHub tokens, etc.).
Vaultwarden stores all passwords a human types into a browser. The two stores never overlap.

### Anton (compute — GPU workloads)

**Ollama VM** (`192.168.0.30`):

| Service | Notes |
|---------|-------|
| Ollama | GPU inference via RTX 3060 passthrough |
| Tailscale exit node (backup) | Secondary exit node |

**OpenClaw VM** (`192.168.0.32`):

| Service | Notes |
|---------|-------|
| OpenClaw | Personal AI assistant gateway; permanent on Anton |

**Personal Debian VM** (`192.168.0.33`):

| Service | Notes |
|---------|-------|
| Debian Server | Development workstation |

**Services VM** (`192.168.0.31`) — temporary, migrates to services node when built:

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy; two entrypoints: `web` (80, `*.home`) and `websecure` (443, `*.wsh`) |
| step-ca | Local CA; issues wildcard `*.wsh` cert; Traefik ACME uses local step-ca endpoint |
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
| Traefik | Reverse proxy; `web` (80, `*.home`) and `websecure` (443, `*.wsh`) |
| step-ca | Local CA; issues wildcard `*.wsh` cert (migrates with services VM) |
| Jellyfin | GPU transcoding via P2000 (migrates with services VM) |
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
  - `*.wsh` → CNAME `anton-services.ts.home` (Tailscale MagicDNS hostname for the services VM)
  - `*.home` → A record `192.168.0.31` (services VM LAN IP)
- Headscale pushes the AdGuard VM's Tailscale IP as the DNS resolver for `.wsh` and `.home`
  to all tailnet members via `dns_config` → `nameservers`

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
API keys are generated by Terraform (`random_id`) and written into the config files — not
randomly generated at first boot — making cross-app linking deterministic.

- Config files: `services/anton/config/radarr.xml`, `sonarr.xml`, `prowlarr.xml`
- API key values sourced from `terraform.tfvars` (generated, not manually set)
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

### Vaultwarden

Account creation requires client-side PBKDF2 key derivation — cannot be scripted without
implementing Bitwarden's full crypto client. Accepted as a one-time manual bootstrap step.

- Start Vaultwarden with `SIGNUPS_ALLOWED=true` (default on first boot)
- Register at `https://vault.home` in a browser
- Signups lock automatically after first account; `SIGNUPS_ALLOWED=false` enforced by env var on restart
- Account persists on Storinator NFS — survives all VM rebuilds, never repeated

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

All workspaces use MinIO S3 on Storinator, accessed over Tailscale.

- Endpoint: `http://storinator:9000` (Tailscale MagicDNS)
- Bucket: `terraform-state`, keys `nuc/terraform.tfstate`, `anton/terraform.tfstate`, `services/terraform.tfstate`
- Locking via S3 lockfile (`use_lockfile = true`, Terraform ≥ 1.10) — no DynamoDB needed
- Accessible from deploy VM (normal execution) and operator laptop (break-glass)
- Replicated to Gringotts daily; ZFS snapshots provide version history

---

## Reverse Proxy

Single Traefik instance on Anton (services VM at `192.168.0.31`) serves all services across
all nodes. NUC-hosted services (Infisical, Vaultwarden) are configured as external backends
pointing at their local IPs (e.g. `192.168.0.21`). All nodes are on the same LAN so Traefik
on Anton reaches them directly.

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

**`terraform.tfvars`** — operator laptop, gitignored

The provisioning source of truth. Manually supplied values only:
- Proxmox API token + endpoint + username (one set per node)
- Tailscale API key
- SSH public key
- ACME email (Let's Encrypt via Traefik)
- Infisical `workspace_id`, `client_id`, `client_secret` (added after bootstrap step 9)
- Vaultwarden master password (added after bootstrap step 10)

No service secrets are generated or stored in Terraform. Backed up as an encrypted
note in Vaultwarden. Never committed to Git.

**Infisical** — NUC Infisical VM, machine-consumed secrets

Stores all secrets that services or processes read programmatically:
- Service API keys and inter-service tokens (Prowlarr → Radarr/Sonarr API keys, etc.)
- Developer API keys accessed via `infisical run -- <command>` on the operator laptop:
  `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, etc.

At VM boot, an init script runs `infisical export --format dotenv` to write an
ephemeral `.env` file. Services read `.env` at startup. The `.env` is not committed
and is regenerated on each boot from Infisical. Seeded manually via the Infisical UI
after the bootstrap script runs.

**Vaultwarden** — NUC Infisical VM, human-consumed secrets

Stores every password a human types into a browser or UI:
- All service web UI admin passwords (Grafana, n8n, Jellyfin, Calibre-Web, PhotoPrism, etc.)
- The `terraform.tfvars` file itself (encrypted note or attachment)
- Infisical admin credentials
- Any other personal account credentials

Populated manually when setting up each service — no Terraform automation.
Account creation is a one-time manual bootstrap step; account persists on Storinator NFS
across all VM rebuilds so it never needs to be repeated.

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
    hosts.yml         # all physical nodes and VMs
  tailscale.yml       # installs Tailscale on physical nodes, pointing at Headscale
  base.yml            # day-2 config for all VMs (push)
  physical.yml        # day-2 config for physical devices (push, targets physical group)
  roles/
    base/             # applied to all Debian VMs and physical devices
    docker/           # applied to VMs running Docker Compose services
    headscale/        # applied to DNS VM — Headscale + cloudflared Docker Compose + config
    network/          # Proxmox bridge config for physical nodes
```

Headscale pre-auth keys for physical nodes are generated via the Headscale CLI on the
deploy VM and stored in Infisical. The `tailscale.yml` playbook reads the key from
Infisical at run time.

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

Then from the operator laptop (or deploy VM):

```bash
ansible-playbook ansible/physical.yml --limit <hostname>
```

**Ongoing**: run `ansible-playbook ansible/physical.yml --limit <hostname>` from the
deploy VM when needed.

**Registration**: add the device to `network.yml` and `ansible/inventory/hosts.yml`
(under the appropriate `physical` subgroup).

---

## Deployment Automation

Deploys are triggered manually from the deploy VM. No webhook or CI automation.

```
# SSH to deploy VM, then:
./scripts/deploy.sh nuc      # terraform apply + ansible for NUC VMs
./scripts/deploy.sh anton    # terraform apply + ansible for Anton VMs
./scripts/deploy.sh services # terraform apply + ansible for services node VMs
./scripts/deploy.sh both     # all nodes
./scripts/deploy-services.sh # redeploy Docker Compose stacks only (no Terraform)
```

The deploy VM holds `terraform.tfvars` and all deploy credentials. It is not
internet-facing — only reachable over Tailscale or the local LAN.

**Concurrency**: the deploy script holds a lock (`/var/lock/homelab-deploy.lock`)
so concurrent runs are prevented rather than running in parallel.

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
| Infisical bootstrap | Single-pass terraform apply; `scripts/infisical-bootstrap.sh` runs after first apply, credentials added to `terraform.tfvars` |
| Infisical role | Single source of truth for all machine-consumed secrets: service API keys, inter-service tokens, developer API keys. VMs fetch via `infisical export` at boot to generate ephemeral `.env` files. |
| Vaultwarden role | Human-consumed secrets only (web UI admin passwords). Populated manually when setting up each service. No Terraform automation. |
| Vaultwarden account creation | Cannot be headlessly pre-seeded (client-side key derivation); one manual browser registration accepted as bootstrap exception alongside HAOS. Account persists on NFS — never repeated. |
| NUC RAM headroom | Accept the risk; monitor closely |
| Tailscale exit node coupling | Accept DNS+exit node coupling on NUC; Anton is backup exit node |
| Monitoring stack | Prometheus + Grafana + Loki only; Mimir/Tempo removed |
| OpenClaw placement | Permanent on Anton; not in services node migration list |
| AdGuard headless config | Pre-seeded `AdGuardHome.yaml`; setup wizard bypassed entirely |
| Jellyfin headless setup | `/Startup/*` API scripted in `jellyfin-init.sh` |
| Servarr headless setup | Pre-seeded `config.xml` with predetermined API keys; cross-app linking via `servarr-init.sh` |
| Calibre-Web headless setup | Post-start `cps.py -s` CLI; library at `/books` mount |
| n8n headless setup | `POST /api/v1/owner/setup` scripted in `n8n-init.sh` |
| CouchDB headless setup | Env vars for credentials; init container handles `/_cluster_setup` and CORS |
| Tailscale coordination server | Self-hosted Headscale on the NUC DNS VM (`192.168.0.2`), co-located with AdGuard. Public HTTPS endpoint provided by a Cloudflare Tunnel (cloudflared container). No public IP or open port required. Uses Tailscale's public DERP relays. Managed by Ansible (`roles/headscale`). |
| Terraform execution host | Deploy VM (`nuc-deploy`) runs all Terraform workspaces. Operator laptop is break-glass fallback. No VPS. |
| Terraform state backend | MinIO S3 on Storinator (`http://storinator:9000`) for all workspaces (`nuc/`, `anton/`, `services/`). S3 lockfile replaces NFS file locking. Both deploy VM and operator laptop reach MinIO over Tailscale. |
| Physical device management | Ansible push, same model as VMs. One-time bootstrap via `scripts/bootstrap-physical.sh` (installs Tailscale only). All further config pushed via `ansible-playbook ansible/physical.yml` from the deploy VM. |
| Deployment automation | Manual. Operator SSHes to deploy VM and runs `./scripts/deploy.sh`. No webhook, no CI. Simpler and sufficient for a personal homelab. |
| DNS domain strategy | Two domains: `*.wsh` (Tailscale/HTTPS, personal devices) and `*.home` (LAN/HTTP, guests). Avoids subnet routing; guests can reach services without Tailscale. Single Traefik instance handles both. |
| TLS for private TLDs | Let's Encrypt does not issue certs for `.wsh` or `.home`. `*.wsh` uses step-ca (local CA, wildcard cert, Traefik ACME). `*.home` is plain HTTP (LAN only, acceptable). |
| AdGuard DNS rewrites | `*.wsh` CNAME → `anton-services.ts.home` (MagicDNS). `*.home` A → `192.168.0.31` (LAN IP). Headscale `dns_config` pushes AdGuard's Tailscale IP as resolver for both TLDs to all tailnet members. |
| Per-service network exposure | Each service defines which domains it exposes via presence/absence of `-wsh` and `-home` Traefik router labels. Default is both. |
