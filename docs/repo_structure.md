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

**`hardware_inventory.md`** — Physical hardware reference: specs for Machamp, Diglett, Alakazam, Ditto, Orange Pi.

**`repo_structure.md`** — This file.

---

## `terraform/modules/proxmox-vm/`

The shared VM module. Every standard (Ubuntu, cloud-init) VM is an instance of this module. HAOS uses a dedicated `proxmox_virtual_environment_vm` resource in `terraform/diglett/main.tf` instead.

**`variables.tf`** — All inputs: `node_name`, `vm_id`, `name`, `cores`, `memory_mb`, `disk_size_gb`, `datastore`, `image_file_id` (the already-downloaded cloud image), `ip_address`, `gateway`, `dns_servers`, `ssh_public_key`, `tailscale_auth_key`, `user_data_extra`, `tags`.

**`main.tf`** — Two resources:
1. `proxmox_virtual_environment_file` — uploads a cloud-init YAML snippet to Proxmox local snippets storage. The snippet sets hostname, installs base packages (qemu-guest-agent, git, nfs-common, etc.), installs Tailscale, and joins the network. Accepts `user_data_extra` to inject extra `runcmd` steps per VM.
2. `proxmox_virtual_environment_vm` — creates the VM: CPU/RAM/disk from variables, clones root disk from the cloud image, attaches the cloud-init drive, sets static IP.

**`outputs.tf`** — Exposes `vm_id`, `name`, `ip_address`, and `ipv4_addresses` (live addresses from QEMU guest agent) so root modules can reference them.

---

## `terraform/diglett/`

Root module for the Diglett node. VM ID range 200–299, IP range `192.168.0.21–29`. Note: `diglett-dns` (VM 200) is special-cased at `192.168.0.2` as the primary DNS resolver.

**`main.tf`** — Defines:
- `proxmox_virtual_environment_download_file.ubuntu_2404` — downloads the Ubuntu 24.04 cloud image once; re-applying is a no-op.
- `proxmox_virtual_environment_download_file.haos` — downloads the HAOS qcow2 image for the Home Assistant VM.
- `module.dns` — `diglett-dns` VM (VM 200, `192.168.0.2`, 2 cores, 2GB): AdGuard Home + primary Tailscale exit node.
- `resource.proxmox_virtual_environment_vm.haos` — `diglett-haos` VM (VM 202, `192.168.0.22`, 2 cores, 4GB): Home Assistant OS. Uses a dedicated resource (not the shared module) because HAOS boots from its own qcow2 image, not cloud-init.
- `module.infra` — `diglett-infra` VM (VM 203, `192.168.0.23`, 4 cores, 12GB): Infisical + Vaultwarden + Authentik + Traefik + step-ca + Litestream.

---

## `terraform/machamp/`

Root module for Machamp. VM ID range 100–199, IP range `192.168.0.30–49`.

**`main.tf`** — Defines:
- `proxmox_virtual_environment_download_file.ubuntu_2404` — downloads the Ubuntu 24.04 cloud image once.
- `module.services` — `machamp-services` VM (VM 100, `192.168.0.30`, 8 cores, 36GB): all Docker Compose services, Quadro P2200 for Jellyfin transcoding. hostpci block pending.
- `module.dev` — `machamp-dev` VM (VM 101, `192.168.0.31`, 6 cores, 24GB): personal development workstation.

---

## `services/diglett-dns/`

Docker Compose stack for the `diglett-dns` VM.

**`docker-compose.yml`** — AdGuard Home, `network_mode: host` (needs port 53 on host IP).

**`adguard/AdGuardHome.yaml`** — Pre-seeded config. AdGuard detects a valid config on startup and skips the setup wizard entirely. Contains: bcrypt admin password hash (plaintext in Vaultwarden), upstream DNS (8.8.8.8 / 8.8.4.4), DNS rewrites (`*.wsh` CNAME → `machamp-services.ts.home`, `*.home` A → `192.168.0.30`), and default blocklists.

---

## `services/diglett-infra/`

Docker Compose stack for the `diglett-infra` VM.

**`docker-compose.yml`** — Traefik (reverse proxy, ports 80/443), step-ca (local CA for TLS), Infisical (+ PostgreSQL + Redis), Vaultwarden, Authentik (+ PostgreSQL + Redis), and a Litestream sidecar that continuously streams the Vaultwarden SQLite WAL to Alakazam NFS. Authentik's PostgreSQL runs on local VM disk (not NFS) to avoid soft-mount corruption; backed up every 6 hours to Alakazam NFS.

**`traefik/traefik.yml`** — Static Traefik config: entrypoints, Docker provider, file provider pointing at `dynamic/`, and `step` ACME cert resolver.

**`traefik/dynamic/services-vm.yml`** — Static Traefik routes for services running on other VMs (machamp-services at `192.168.0.30`, diglett-dns at `192.168.0.2`). Services with Docker labels on diglett-infra are handled by the Docker provider automatically.

**`litestream.yml`** — Litestream replica config: streams `/var/lib/vaultwarden/db.sqlite3` to `/mnt/nas/docker/vaultwarden-backup/`.

**`.env.example`** — Documents all env vars this stack expects from `/etc/homelab.env` (generated by the `infra` Ansible role on first provision).

---

## `services/diglett-deploy/`

Not yet created.

---

## `services/machamp-services/`

Docker Compose stack for the `machamp-services` VM. This is the main services stack.

**`docker-compose.yml`** — All services:
- **Jellyfin** — media server; `/dev/dri` passthrough for Quadro P2200 transcoding
- **Prowlarr, Radarr, Sonarr** — Servarr stack
- **PhotoPrism** — photo archive
- **Calibre-Web** — ebook server
- **n8n** — automation workflows
- **CouchDB + couchdb-init** — Obsidian LiveSync backend; init container runs `couchdb-init.sh`
- **Quartz** — read-only Obsidian vault web publishing
- **Homepage** — service dashboard
- **Prometheus, Grafana, Loki, Promtail** — metrics and log aggregation

**`config/radarr.xml`, `sonarr.xml`, `prowlarr.xml`** — Pre-seeded config files mounted read-only into each container. API keys use `${RADARR_API_KEY}` etc., sourced from Infisical at boot via `.env`.

**`couchdb-init.sh`** — Runs as a one-shot init container: waits for CouchDB, runs `/_cluster_setup`, creates the `obsidian` database, and sets CORS headers for Obsidian LiveSync clients.

**`prometheus/prometheus.yml`** — Prometheus scrape config; lists all VMs as node_exporter targets.

**`loki/loki.yml`** — Loki local storage config.

**`loki/promtail.yml`** — Promtail config; scrapes Docker container logs via the Docker socket.

**`.env.example`** — Documents all env vars this stack expects from Infisical.

---

## `ansible/`

Day-2 configuration management. Runs after Terraform provisions VMs and cloud-init finishes. All Ansible is push — no pull mode, no crons on target machines.

**`ansible.cfg`** — Project-level config: points at the inventory, sets `ubuntu` as remote user, disables host key checking (freshly provisioned VMs), enables SSH pipelining.

**`inventory/homelab.yml`** — Inventory source file; tells Ansible to use the `homelab` plugin.

**`plugins/inventory/homelab.py`** — Ansible inventory plugin. Reads `network.yml` (infrastructure facts) and `group_config.yml` (Ansible group config). Physical nodes are grouped by their `type` field; VMs are grouped per their parent node's entry in `group_config.yml`. VMs with `ansible_managed: false` are excluded (e.g. diglett-haos).

**`group_config.yml`** — Ansible-specific inventory config: maps each Proxmox node name to its VM group name and group vars (`proxmox_node`, `ansible_user`). Kept separate from `network.yml` so infrastructure facts and Ansible config don't mix.

**`base.yml`** — Applies the `base` role to all VMs.

**`physical.yml`** — Applies the `base` role to all physical devices (targets `physical` inventory group).

**`tailscale.yml`** — Bootstrap-only playbook for physical nodes: installs Tailscale and joins the Headscale network. Run once before Terraform.

**`network.yml`** — Configures static IP on Proxmox physical nodes by templating `/etc/network/interfaces` and running `ifreload -a`.

**`roles/base/`** — Applied to every Ubuntu host (VMs and physical). Installs fail2ban, UFW, sets timezone, disables password SSH auth, keeps Tailscale up to date, creates `/mnt/nas`.

**`roles/docker/`** — Applied to VMs running Docker Compose. Adds the official Docker apt repo, installs Docker CE + compose plugin, configures log rotation, adds `ubuntu` user to the `docker` group.

**`roles/network/`** — Installs `ifupdown2` and templates `/etc/network/interfaces` for Proxmox bridge config on physical nodes.

---

## `scripts/`

**`deploy.sh`** — Main entry point for VM provisioning. Runs `terraform apply` for the target node(s), waits for VMs to be SSH-reachable, then runs `ansible-playbook base.yml`. Usage: `./scripts/deploy.sh [diglett|machamp|both]`.

**`deploy-services.sh`** — SSHes to the relevant VM and runs `docker compose pull && docker compose up -d` for whichever `services/` subdirectory changed. Called by `webhook-deploy.sh`.

**`webhook-deploy.sh`** — Triggered by the internal webhook. Pulls latest code, detects changed paths, and dispatches: Terraform changed → `deploy.sh`; `ansible/` changed → `base.yml` + `physical.yml`; `services/` changed → `deploy-services.sh`. Holds a lock to prevent concurrent runs.

**`install-proxmox-ca.sh`** — Fetches the Proxmox cluster CA certificate from a Proxmox node and installs it system-wide on the deploy VM (`update-ca-certificates`). Run once after authorizing the deploy VM's SSH key on the Proxmox nodes. Required for Terraform to verify TLS connections to the Proxmox API (`insecure = false`). Usage: `bash install-proxmox-ca.sh [node]` (default: `machamp.local`).

**`infisical-bootstrap.sh`** — Runs `infisical bootstrap` against a fresh Infisical instance. Creates admin user, organization, workspace, and machine identity. Outputs credentials to add to `terraform.tfvars`.

**`jellyfin-init.sh`** — Drives the Jellyfin `/Startup/*` API headlessly: sets locale, creates admin user, configures remote access, completes wizard.

**`servarr-init.sh`** — Links Prowlarr to Radarr and Sonarr via `POST /api/v1/applications`. Run after first container start.

**`calibre-init.sh`** — Sets the Calibre-Web admin password via `docker exec calibre-web python3 cps.py -s`.

**`n8n-init.sh`** — Creates the n8n owner account via `POST /api/v1/owner/setup`.

**`bootstrap-physical.sh`** — Minimal one-time bootstrap for new physical devices. Installs Tailscale and joins the tailnet so Ansible can reach the device. Run via SSH from the operator laptop.
