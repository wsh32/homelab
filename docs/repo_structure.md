# Repo Structure

A walkthrough of every file in this repo and what it does.

## Root

**`network.yml`** — Single source of truth for all static IP assignments. Every host, VM, gateway, and DNS server is defined here. Terraform reads it directly via `yamldecode()`; Ansible inventory mirrors the IPs. Edit IPs here first.

**`.gitignore`** — Excludes secrets and Terraform internals from git: `terraform.tfvars`, `.env`, `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl`, `*.pem`, `*.key`. Nothing sensitive can accidentally be committed.

**`README.md`** — Top-level overview: architecture diagram, repo structure, bootstrap steps, and the three-store secrets model (tfvars / Vaultwarden / Infisical).

**`CLAUDE.md`** — Instructions for Claude when working in this repo. Key conventions: which Terraform provider to use, what goes in each secrets store, VM ID/IP ranges, NFS mount paths, Traefik label format, headless-config rule.

---

## `docs/`

**`plan.md`** — The primary architecture document. Full network design, storage layout, VM resource budgets, the complete service list per VM, headless configuration strategy for every service, and the bootstrap sequence. If you're making a decision about architecture, it lives here.

**`runbook.md`** — Step-by-step bootstrap runbook with exact commands. Follow this to rebuild the homelab from scratch.

**`TODOS.md`** — Deferred work items with full context. Each item has what/why/context/dependencies so they're actionable later.

**`hardware_inventory.md`** — Physical hardware reference: specs for Machamp, Diglett, Snorlax, Ditto, Orange Pi.

**`repo_structure.md`** — This file.

---

## `terraform/modules/proxmox-vm/`

The shared VM module. Every standard (Debian, cloud-init) VM is an instance of this module. HAOS uses a dedicated `proxmox_virtual_environment_vm` resource in `terraform/diglett/main.tf` instead.

**`variables.tf`** — All inputs: `node_name`, `vm_id`, `name`, `cores`, `memory_mb`, `disk_size_gb`, `datastore`, `image_file_id` (the already-downloaded cloud image), `ip_address`, `gateway`, `dns_servers`, `ssh_public_key`, `tailscale_auth_key`, `user_data_extra`, `tags`.

**`main.tf`** — Two resources:
1. `proxmox_virtual_environment_file` — uploads a cloud-init YAML snippet to Proxmox local snippets storage. The snippet sets hostname, installs base packages (qemu-guest-agent, git, nfs-common, etc.), installs Tailscale, and joins the network. Accepts `user_data_extra` to inject extra `runcmd` steps per VM.
2. `proxmox_virtual_environment_vm` — creates the VM: CPU/RAM/disk from variables, clones root disk from the cloud image, attaches the cloud-init drive, sets static IP.

**`outputs.tf`** — Exposes `vm_id`, `name`, `ip_address`, and `ipv4_addresses` (live addresses from QEMU guest agent) so root modules can reference them.

---

## `terraform/diglett/`

Root module for the Diglett node. VM ID range 200–299, IP range `192.168.0.20–29`.

**`main.tf`** — Defines:
- `proxmox_virtual_environment_download_file.debian_12` — downloads the Debian 12 cloud image once; re-applying is a no-op.
- `proxmox_virtual_environment_download_file.haos` — downloads the HAOS qcow2 image for the Home Assistant VM.
- `module.dns` — `diglett-dns` VM (VM 200, `192.168.0.2`, 2 cores, 2GB): AdGuard Home + primary Tailscale exit node.
- `module.infisical` — `diglett-infisical` VM (VM 201, `192.168.0.21`, 2 cores, 6GB): Infisical + Vaultwarden.
- `resource.proxmox_virtual_environment_vm.haos` — `diglett-haos` VM (VM 202, `192.168.0.22`, 2 cores, 4GB): Home Assistant OS. Uses a dedicated resource (not the shared module) because HAOS boots from its own qcow2 image, not cloud-init.
- `module.deploy` — `diglett-deploy` VM (VM 203, `192.168.0.23`, 1 core, 1GB): Terraform + Ansible + internal webhook listener.

---

## `terraform/machamp/`

Root module for Machamp. VM ID range 100–199, IP range `192.168.0.10–19`.

**`main.tf`** — Defines:
- `proxmox_virtual_environment_download_file.debian_12` — downloads the Debian 12 cloud image once.
- `module.ollama` — `machamp-ollama` VM (VM 100, `192.168.0.10`, 4 cores, 32GB): Ollama GPU inference + backup Tailscale exit node. RTX 3060 hostpci block pending (see TODOS.md).
- `module.services` — `machamp-services` VM (VM 103, `192.168.0.11`, 8 cores, 32GB): all Docker Compose services, Traefik reverse proxy, Quadro P2000 for Jellyfin transcoding. hostpci block pending.
- `module.openclaw` — `machamp-openclaw` VM (VM 102, `192.168.0.12`, 2 cores, 8GB): OpenClaw AI assistant gateway.
- `module.debian` — `machamp-debian` VM (VM 101, `192.168.0.13`, 6 cores, 16GB): personal development workstation.

---

## `terraform/vps/`

Root module for the DigitalOcean VPS. Runs only from the operator laptop — the VPS cannot manage its own existence. State stored locally (gitignored); back up in Vaultwarden.

**`main.tf`** — Creates a DigitalOcean droplet and firewall. Firewall opens SSH (22), the GitHub webhook port (9000), Headscale HTTPS (443), and Headscale DERP UDP (41641). Outputs `vps_ip`.

**`variables.tf`** — `do_token`, `do_region`, `do_size`, `ssh_public_key`.

---

## `services/dns/`

Docker Compose stack for the `diglett-dns` VM.

**`docker-compose.yml`** — AdGuard Home, `network_mode: host` (needs port 53 on host IP).

**`adguard/AdGuardHome.yaml`** — Pre-seeded config. AdGuard detects a valid config on startup and skips the setup wizard entirely. Contains: bcrypt admin password hash (plaintext in Vaultwarden), upstream DNS (8.8.8.8 / 8.8.4.4), DNS rewrites (`*.wsh` CNAME → `machamp-services.ts.home`, `*.home` A → `192.168.0.11`), and default blocklists.

---

## `services/diglett-infra/`

Docker Compose stack for the `diglett-infisical` VM.

**`docker-compose.yml`** — Infisical (+ MongoDB + Redis), Vaultwarden, and a Litestream sidecar that continuously streams the Vaultwarden SQLite WAL to Snorlax NFS. Infisical's MongoDB data lives on local VM disk (not NFS) to avoid soft-mount corruption; backed up every 6 hours via a mongodump container to Snorlax.

**`litestream.yml`** — Litestream replica config: streams `/var/lib/vaultwarden/db.sqlite3` to `/mnt/nas/docker/vaultwarden-backup/`.

**`.env.example`** — Documents all env vars this stack expects from Infisical.

---

## `services/diglett-deploy/`

Docker Compose stack for the `diglett-deploy` VM.

**`docker-compose.yml`** — `adnanh/webhook` listening on port 9001 (Tailscale only; not internet-facing). Receives forwarded payloads from the VPS webhook and runs `scripts/webhook-deploy.sh`.

**`hooks.json`** — Webhook hook definition: accepts any payload and passes the `ref` field to `webhook-deploy.sh`.

---

## `services/machamp/`

Docker Compose stack for the `machamp-services` VM. This is the main services stack.

**`docker-compose.yml`** — All services:
- **Traefik** — reverse proxy; two entrypoints: `web` (80, `*.home`) and `websecure` (443, `*.wsh`)
- **step-ca** — local CA; Traefik uses it as the ACME endpoint for `*.wsh` TLS certs
- **Jellyfin** — media server; `/dev/dri` passthrough for Quadro P2000 transcoding
- **Prowlarr, Radarr, Sonarr** — Servarr stack
- **PhotoPrism** — photo archive
- **Calibre-Web** — ebook server
- **n8n** — automation workflows
- **CouchDB + couchdb-init** — Obsidian LiveSync backend; init container runs `couchdb-init.sh`
- **Quartz** — read-only Obsidian vault web publishing
- **Homepage** — service dashboard
- **Prometheus, Grafana, Loki, Promtail** — metrics and log aggregation

**`traefik/traefik.yml`** — Static Traefik config: entrypoints, Docker provider, file provider pointing at `dynamic/`, and `step` ACME cert resolver.

**`traefik/dynamic/diglett-services.yml`** — Static Traefik routes for Diglett-hosted services (Infisical, Vaultwarden). Since those containers run on `diglett-infisical` (not in Docker on `machamp-services`), they're external backends pointing at `192.168.0.21`.

**`config/radarr.xml`, `sonarr.xml`, `prowlarr.xml`** — Pre-seeded config files mounted read-only into each container. API keys use `${RADARR_API_KEY}` etc., sourced from Infisical at boot via `.env`.

**`couchdb-init.sh`** — Runs as a one-shot init container: waits for CouchDB, runs `/_cluster_setup`, creates the `obsidian` database, and sets CORS headers for Obsidian LiveSync clients.

**`prometheus/prometheus.yml`** — Prometheus scrape config; lists all VMs as node_exporter targets.

**`loki/loki.yml`** — Loki local storage config.

**`loki/promtail.yml`** — Promtail config; scrapes Docker container logs via the Docker socket.

**`.env.example`** — Documents all env vars this stack expects from Infisical.

---

## `services/vps/`

Docker Compose stack for the DigitalOcean VPS. Deployed by `ansible/roles/headscale/` via `vps.yml`. The repo is synced to `/opt/homelab/` on the VPS by `ansible-playbook ansible/vps.yml`.

**`docker-compose.yml`** — Headscale (Tailscale coordination server) and a webhook forwarder (`adnanh/webhook`) that validates GitHub HMAC signatures and forwards payloads to the deploy VM over Tailscale.

**`headscale/config.yml`** — Headscale config: server URL, IP prefixes, DNS config (pushes AdGuard's Tailscale IP as resolver for `.wsh` and `.home` to all tailnet members).

**`webhook/hooks.json`** — Webhook hook definition: validates GitHub HMAC-SHA256, then shells out to forward the payload to `diglett-deploy.ts.home:9001`.

---

## `ansible/`

Day-2 configuration management. Runs after Terraform provisions VMs and cloud-init finishes. All Ansible is push — no pull mode, no crons on target machines.

**`ansible.cfg`** — Project-level config: points at the inventory, sets `debian` as remote user, disables host key checking (freshly provisioned VMs), enables SSH pipelining.

**`inventory/homelab.yml`** — Inventory source file; tells Ansible to use the `homelab` plugin.

**`plugins/inventory/homelab.py`** — Ansible inventory plugin. Reads `network.yml` (infrastructure facts) and `group_config.yml` (Ansible group config). Physical nodes are grouped by their `type` field; VMs are grouped per their parent node's entry in `group_config.yml`. VMs with `ansible_managed: false` are excluded (e.g. diglett-haos).

**`group_config.yml`** — Ansible-specific inventory config: maps each Proxmox node name to its VM group name and group vars (`proxmox_node`, `ansible_user`). Kept separate from `network.yml` so infrastructure facts and Ansible config don't mix.

**`base.yml`** — Applies the `base` role to all VMs.

**`physical.yml`** — Applies the `base` role to all physical devices (targets `physical` inventory group).

**`tailscale.yml`** — Bootstrap-only playbook for physical nodes: installs Tailscale and joins the Headscale network. Run once before Terraform.

**`network.yml`** — Configures static IP on Proxmox physical nodes by templating `/etc/network/interfaces` and running `ifreload -a`.

**`roles/base/`** — Applied to every Debian host (VMs and physical). Installs fail2ban, UFW, sets timezone, disables password SSH auth, keeps Tailscale up to date, creates `/mnt/nas`.

**`roles/docker/`** — Applied to VMs running Docker Compose. Adds the official Docker apt repo, installs Docker CE + compose plugin, configures log rotation, adds `debian` user to the `docker` group.

**`roles/headscale/`** — Applied to the VPS. Ensures `/var/lib/headscale/` exists and deploys `services/vps/` via `docker compose up`.

**`roles/network/`** — Installs `ifupdown2` and templates `/etc/network/interfaces` for Proxmox bridge config on physical nodes.

---

## `scripts/`

**`deploy.sh`** — Main entry point for VM provisioning. Runs `terraform apply` for the target node(s), waits for VMs to be SSH-reachable, then runs `ansible-playbook base.yml`. Usage: `./scripts/deploy.sh [diglett|machamp|both]`.

**`deploy-services.sh`** — SSHes to the relevant VM and runs `docker compose pull && docker compose up -d` for whichever `services/` subdirectory changed. Called by `webhook-deploy.sh`.

**`webhook-deploy.sh`** — Runs on `diglett-deploy`, triggered by the internal webhook. Pulls latest code, detects changed paths, and dispatches: Terraform changed → `deploy.sh`; `ansible/` changed → `base.yml` + `physical.yml` + `vps.yml`; `services/` changed → `deploy-services.sh`; `terraform/vps/` changed → exit 1 (notify operator). Holds a lock to prevent concurrent runs.

**`infisical-bootstrap.sh`** — Runs `infisical bootstrap` against a fresh Infisical instance. Creates admin user, organization, workspace, and machine identity. Outputs credentials to add to `terraform.tfvars`.

**`jellyfin-init.sh`** — Drives the Jellyfin `/Startup/*` API headlessly: sets locale, creates admin user, configures remote access, completes wizard.

**`servarr-init.sh`** — Links Prowlarr to Radarr and Sonarr via `POST /api/v1/applications`. Run after first container start.

**`calibre-init.sh`** — Sets the Calibre-Web admin password via `docker exec calibre-web python3 cps.py -s`.

**`n8n-init.sh`** — Creates the n8n owner account via `POST /api/v1/owner/setup`.

**`bootstrap-physical.sh`** — Minimal one-time bootstrap for new physical devices. Installs Tailscale and joins the tailnet so Ansible can reach the device. Run via SSH from the operator laptop.
